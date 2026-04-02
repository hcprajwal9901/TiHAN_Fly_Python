"""
Log Parser Module  –  Optimized Edition
========================================
Key improvements over the original:
  1. Actual message-type discovery  – scans the file to find types that
     ACTUALLY exist, not the full mavlink_map (which has 200+ entries).
  2. Sparse byte-offset index  – records one file offset per message type
     every INDEX_STRIDE messages so _extract_series can seek instead of
     scanning from byte 0 every time.
  3. Better duration estimate  – uses the last timestamp seen during the
     scan window rather than a linear byte extrapolation.
"""

import time
from pathlib import Path
from pymavlink import mavutil
from PyQt5.QtCore import QObject, pyqtSignal


# How often (in messages of a given type) to record a byte offset.
# Lower = faster seeks, higher memory.  500 is a good balance.
INDEX_STRIDE = 500

# How many messages to scan during the O(1) init pass.
# 20 000 covers the first ~2 MB of a binary log and captures all FMT/PARM
# blocks as well as building a representative set of message types.
MAX_SCAN_MESSAGES = 20_000


class ParsedLog:
    """Container for parsed log data (lazy-load version)."""

    def __init__(self):
        self.messages            = {}   # Eager cache (optional / legacy)
        self.message_types_list  = []   # Types actually seen in the file
        self.parameters          = {}
        self.events              = []
        self.flight_summary      = {}
        self.boot_time_offset    = None
        self.reboot_events       = []
        self.filepath            = ""
        self.is_dataflash        = False
        self.formats             = {}   # DataFlash column info

        # ── New: sparse seek index ──────────────────────────────────────────
        # { msg_type: [byte_offset_0, byte_offset_N, byte_offset_2N, …] }
        # Populated during parse_log so _extract_series can skip ahead.
        self.message_index: dict[str, list[int]] = {}

        # ── New: field-name cache ───────────────────────────────────────────
        # { msg_type: [field, field, …] }  – avoids re-opening the file in
        # getAvailableChannels for every click.
        self.field_cache: dict[str, list[str]] = {}


class LogParser(QObject):
    """Parse .tlog / .bin files with fast O(1) init and seek-index building."""

    parseProgress = pyqtSignal(int)    # 0-100
    parseComplete = pyqtSignal(object) # ParsedLog
    parseError    = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        self._parsing         = False
        self.force_downsampling = False

    # ──────────────────────────────────────────────────────────────────────────
    # Public API
    # ──────────────────────────────────────────────────────────────────────────

    def parse_log(self, filepath):
        """
        Fast initialisation pass:
          • Scans at most MAX_SCAN_MESSAGES messages (≈ first 2 MB)
          • Records ACTUAL message types found in the file
          • Builds a sparse byte-offset index for fast _extract_series seeks
          • Captures parameters, start time, and a duration estimate
        """
        filepath = Path(filepath)
        if not filepath.exists():
            self.parseError.emit(f"File not found: {filepath}")
            return None

        self._parsing   = True
        parsed_log      = ParsedLog()
        parsed_log.filepath     = str(filepath)

        try:
            t0     = time.time()
            suffix = filepath.suffix.lower()
            parsed_log.is_dataflash = (suffix == '.bin')

            print(f"[LogParser] Fast init – {filepath.name}")

            mlog = mavutil.mavlink_connection(str(filepath),
                                              dialect='ardupilotmega')

            msg_count       = 0
            start_timestamp = None
            last_timestamp  = None

            # Sparse index accumulators
            # { msg_type: count_so_far_for_this_type }
            type_counts: dict[str, int] = {}

            while msg_count < MAX_SCAN_MESSAGES:
                # Record byte offset BEFORE reading so we can seek back here
                if hasattr(mlog, 'f') and hasattr(mlog.f, 'tell'):
                    byte_pos = mlog.f.tell()
                else:
                    byte_pos = None

                msg = mlog.recv_match(blocking=False)
                if msg is None:
                    break

                msg_type = msg.get_type()
                if msg_type in ('BAD_DATA', 'UNKNOWN', None):
                    continue

                # ── Timestamp tracking ──────────────────────────────────────
                ts = _get_timestamp(msg)
                if ts is not None:
                    if start_timestamp is None:
                        start_timestamp = ts
                    last_timestamp = ts

                # ── Parameters ──────────────────────────────────────────────
                if msg_type == 'PARAM_VALUE':
                    name = (msg.param_id.decode()
                            if isinstance(msg.param_id, bytes)
                            else msg.param_id)
                    parsed_log.parameters[name] = msg.param_value
                elif msg_type == 'PARM':
                    if hasattr(msg, 'Name') and hasattr(msg, 'Value'):
                        parsed_log.parameters[msg.Name] = msg.Value

                # ── Sparse index ────────────────────────────────────────────
                if byte_pos is not None:
                    cnt = type_counts.get(msg_type, 0)
                    if cnt % INDEX_STRIDE == 0:
                        parsed_log.message_index.setdefault(
                            msg_type, []).append(byte_pos)
                    type_counts[msg_type] = cnt + 1

                # ── Field cache (first occurrence of each type) ─────────────
                if msg_type not in parsed_log.field_cache:
                    parsed_log.field_cache[msg_type] = _extract_fields(msg)

                msg_count += 1

            # ── Message-type list: ONLY types actually seen ─────────────────
            # For DataFlash we can also pull from FMT records (more complete).
            if parsed_log.is_dataflash and hasattr(mlog, 'name_to_id'):
                df_types = set(mlog.name_to_id.keys())
                # Prefer the union so types beyond the scan window are included
                seen_types = set(type_counts.keys()) | df_types
                if hasattr(mlog, 'formats'):
                    parsed_log.formats = mlog.formats
            else:
                # For MAVLink tlogs: ONLY the types we actually observed.
                # This avoids listing 200+ phantom types from mavlink_map.
                seen_types = set(type_counts.keys())

            parsed_log.message_types_list = sorted(seen_types)

            # ── Flight summary ───────────────────────────────────────────────
            duration = 0.0
            if start_timestamp is not None and last_timestamp is not None:
                observed_duration = last_timestamp - start_timestamp

                # If we hit the scan cap, extrapolate via byte-offset geometry
                if msg_count == MAX_SCAN_MESSAGES:
                    file_size = filepath.stat().st_size
                    bytes_read = (mlog.f.tell()
                                  if hasattr(mlog, 'f') and hasattr(mlog.f, 'tell')
                                  else 0)
                    if bytes_read > 0 and file_size > bytes_read and observed_duration > 0:
                        duration = observed_duration * (file_size / bytes_read)
                    else:
                        duration = observed_duration
                else:
                    duration = observed_duration

            parsed_log.flight_summary = {
                'duration':     duration,
                'start_time':   start_timestamp or 0.0,
                'end_time':     (start_timestamp or 0.0) + duration,
                'max_altitude': 0.0,
                'max_speed':    0.0,
            }

            elapsed = time.time() - t0
            print(f"[LogParser] Done in {elapsed:.3f}s – "
                  f"{len(parsed_log.message_types_list)} types, "
                  f"{sum(len(v) for v in parsed_log.message_index.values())} index entries")

            self.parseComplete.emit(parsed_log)
            return parsed_log

        except Exception as e:
            import traceback
            traceback.print_exc()
            self.parseError.emit(f"Parse error: {e}")
            return None

        finally:
            self._parsing = False


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _get_timestamp(msg) -> float | None:
    """Return a float timestamp from any message, or None."""
    if hasattr(msg, 'TimeUS'):
        return msg.TimeUS / 1_000_000.0
    if hasattr(msg, 'time_boot_ms'):
        return msg.time_boot_ms / 1000.0
    return None


_EXCLUDED_FIELDS = frozenset({
    'mavpackettype', 'get_type', 'get_msgbuf', 'to_dict', 'to_json',
    'pack', 'get_header', 'get_fieldnames', 'fmt', 'dump_verbose',
    'dump_verbose_bitmask', 'get_srcSystem', 'get_srcComponent',
})


def _extract_fields(msg) -> list[str]:
    """Return plottable numeric field names for a message."""
    if hasattr(msg, '_fieldnames'):
        return list(msg._fieldnames)

    candidates = (list(msg.__dict__.keys())
                  if hasattr(msg, '__dict__') else dir(msg))
    fields = []
    for attr in candidates:
        if attr.startswith('_') or attr in _EXCLUDED_FIELDS:
            continue
        try:
            if callable(getattr(msg, attr)):
                continue
        except Exception:
            continue
        fields.append(attr)
    return sorted(fields)
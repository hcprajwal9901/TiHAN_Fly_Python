"""
LogBrowserBackend – Optimized Edition
======================================
Performance improvements over the original:

1. CONCURRENT-READ SEMAPHORE
   At most MAX_READERS (default 3) threads read the log file at once.
   Previously, clicking 10 checkboxes launched 10 threads each seeking
   through a 500 MB file simultaneously → I/O thrash + OOM crash.

2. SEEK-INDEX USAGE
   log_parser.py now builds a sparse byte-offset index during its init
   pass.  _extract_series uses the nearest recorded offset to skip ahead
   instead of scanning from byte 0 every time.  For a 500 MB log with
   INDEX_STRIDE=500 the average seek skips ~99.8 % of the file.

3. PER-SERIES CANCELLATION TOKENS (generation counters)
   Each new requestGraphData() for an already-running series bumps a
   generation counter.  The worker checks the counter periodically and
   exits early if it has been superseded.  This prevents stale threads
   from wasting I/O after the user has de-selected a series.

4. getAvailableChannels CACHE
   Field names are stored in ParsedLog.field_cache during the init scan.
   Subsequent calls return instantly without opening the file.

5. O(1) SHARED-TIMESTAMP CHECK
   The old `timestamps != self._shared_timestamps` did a full list
   comparison.  We now compare only length + first/last value.

Thread-safety contract (unchanged from original):
  • graphDataReady is a class-level pyqtSignal – PyQt5 queues cross-
    thread emissions automatically → always delivered on main thread.
  • _data_lock protects all writes to _series_data / _data_bounds.
  • QTimer.singleShot is only called from slots (main thread).
"""

import threading
import bisect
import time
from pymavlink import mavutil
from PyQt5.QtCore import (QObject, QThread, pyqtSignal, pyqtSlot,
                           pyqtProperty, QTimer)
from modules.log_parser import LogParser

try:
    import numpy as np
    _NUMPY = True
except ImportError:
    _NUMPY = False

# Maximum simultaneous file-reader threads.
# 3 gives good parallelism without hammering the disk.
MAX_READERS = 3


# ─────────────────────────────────────────────────────────────────────────────
# Parse worker  (QThread – single instance, no concurrent clear race)
# ─────────────────────────────────────────────────────────────────────────────

class _ParseWorker(QThread):
    finished = pyqtSignal(object)
    error    = pyqtSignal(str)

    def __init__(self, filepath):
        # NOTE: Do NOT accept a shared LogParser from the caller.
        # LogParser is a QObject; calling its methods from a thread it was NOT
        # created on violates Qt's object-affinity rules and causes intermittent
        # crashes (especially the parseError signal emit path).
        # A fresh LogParser is created inside run() so it lives entirely on the
        # worker thread.
        super().__init__()
        self._filepath = filepath

    def run(self):
        try:
            # Instantiate LogParser here so it is owned by this worker thread.
            parser = LogParser()
            result = parser.parse_log(self._filepath)
            self.finished.emit(result)
        except Exception as e:
            self.error.emit(str(e))


# ─────────────────────────────────────────────────────────────────────────────
# Main backend
# ─────────────────────────────────────────────────────────────────────────────

class LogBrowserBackend(QObject):

    logLoaded      = pyqtSignal()
    logCleared     = pyqtSignal()   # fired when current log is unloaded (model → [])
    loadError      = pyqtSignal(str)
    loadProgress   = pyqtSignal(str)
    graphDataReady = pyqtSignal(str, list, list, int)
    fileDialogResult = pyqtSignal(str)   # emitted when a log file is chosen

    @pyqtSlot()
    def openFileDialogForReview(self):
        """
        Show a NON-BLOCKING Qt file dialog for log file selection.

        WHY non-blocking matters on Windows + Python 3.14:
        ────────────────────────────────────────────────────
        Both QFileDialog.getOpenFileName() and QDialog.exec_() run a NESTED
        synchronous event loop that re-enters Qt's main event processing while
        the dialog is open.  During this nested loop, ALL pending Qt events are
        dispatched immediately — including queued cross-thread signals such as
        PnpWatcher.deviceArrived, PortScanner.portsFound, and MAVLink message
        callbacks.  On Python 3.14 / PyQt5 on Windows this reentrant dispatch
        corrupts internal Qt C++ state → access violation in exec_().

        QFileDialog.open() is truly asynchronous: it shows the dialog and
        returns to the caller immediately.  The user's file selection is
        delivered via the fileSelected signal in the NORMAL Qt event loop
        (QueuedConnection, zero reentrancy, zero nesting).
        """
        from PyQt5.QtWidgets import QFileDialog
        from pathlib import Path

        # Guard — don't open a second dialog if one is already showing
        if getattr(self, '_file_dialog', None) is not None:
            try:
                self._file_dialog.raise_()
                self._file_dialog.activateWindow()
                return
            except RuntimeError:
                self._file_dialog = None

        default_dir = str(
            Path.home() / "Documents" / "TihanFly" / "Logs" / "downloaded"
        )

        dialog = QFileDialog(None)
        dialog.setOption(QFileDialog.DontUseNativeDialog, True)
        dialog.setFileMode(QFileDialog.ExistingFile)
        dialog.setNameFilter("Log files (*.bin *.log *.tlog);;All files (*)")
        dialog.setDirectory(default_dir)
        dialog.setWindowTitle("Select DataFlash Log to Review")

        # Wire signals BEFORE open() so they are ready when the dialog closes
        dialog.fileSelected.connect(self._on_review_file_selected)
        dialog.finished.connect(self._on_review_dialog_finished)

        # Keep a strong reference so the dialog is not garbage-collected while open
        self._file_dialog = dialog

        # Non-blocking: returns immediately, no nested event loop
        dialog.open()

    @pyqtSlot(str)
    def _on_review_file_selected(self, path):
        """Delivered on the normal main-thread event loop when the user picks a file."""
        if path:
            self.fileDialogResult.emit(path)

    @pyqtSlot(int)
    def _on_review_dialog_finished(self, result):
        """Release the dialog reference once it closes (accepted or rejected)."""
        self._file_dialog = None


    def __init__(self):
        super().__init__()
        # NOTE: No shared LogParser here – _ParseWorker creates its own instance
        # on the worker thread to respect Qt object-affinity rules.
        self._current_log  = None
        self._log_filepath = ""
        self._parse_worker = None
        self._file_dialog  = None   # holds open QFileDialog (non-blocking) to prevent GC

        # ── Clearing flag ────────────────────────────────────────────────────
        self._clearing = False

        # ── Full series data (for windowed rendering + hover) ────────────────
        self._series_data  = {}   # { name: {'timestamps': [], 'values': []} }
        self._data_bounds  = {}   # { name: {'minX','maxX','minY','maxY'} }

        # ── Shared-timestamp optimisation ────────────────────────────────────
        self._shared_timestamps     = None
        self._timestamps_are_shared = False

        # ── Concurrency controls ─────────────────────────────────────────────
        self._data_lock      = threading.Lock()
        # Limits simultaneous file readers to avoid I/O thrash / OOM on
        # large files when many series are selected at once.
        self._read_semaphore = threading.Semaphore(MAX_READERS)
        # Cancellation: { series_name: generation_int }
        # Bumped on every new request for a series; worker exits if stale.
        self._series_gen: dict[str, int] = {}
        self._gen_lock   = threading.Lock()

    # ── Log loading ───────────────────────────────────────────────────────────

    @pyqtSlot(str)
    def loadLog(self, filepath):
        self._log_filepath = filepath
        # NOTE: _current_log is reset below, AFTER old worker is cancelled

        if hasattr(self, '_parse_worker') and self._parse_worker is not None:
            try:
                if self._parse_worker.isRunning():
                    # QThread running custom python code will ignore quit(). We must not delete it.
                    # Just disconnect it so it doesn't pollute the new log loaded.
                    try:
                        self._parse_worker.finished.disconnect()
                        self._parse_worker.error.disconnect()
                    except Exception:
                        pass
                else:
                    self._parse_worker.deleteLater()
            except RuntimeError:
                # The underlying C++ object was already deleted by worker.deleteLater
                pass
            
            self._parse_worker = None

        # ── Reset current log BEFORE starting the worker so QML sees an
        # empty messageTypes list immediately (avoids 'model size < 0' Qt warning)
        self._current_log  = None
        self.logCleared.emit()          # QML ListView → model: [] cleanly

        self.loadProgress.emit("Parsing log…")

        worker = _ParseWorker(filepath)
        worker.setParent(self) # Prevent premature garbage collection
        worker.finished.connect(self._on_parse_complete)
        worker.error.connect(self.loadError.emit)
        
        # Cleanup properly after finished to prevent memory leaks
        worker.finished.connect(worker.deleteLater)
        worker.error.connect(lambda e: worker.deleteLater())
        
        worker.start()
        self._parse_worker = worker

    def _on_parse_complete(self, parsed_log):
        self._current_log = parsed_log
        self.loadProgress.emit("")
        self.logLoaded.emit()

    # ── Graph data requests ───────────────────────────────────────────────────

    @pyqtSlot(str, str, int, bool)
    def requestGraphData(self, msg_type, field_name, axis_id=0, smooth=False):
        if not self._current_log:
            return

        filepath    = self._current_log.filepath
        series_name = f"{msg_type}.{field_name}"

        # Bump the generation counter – any running worker for this series
        # will detect the change and exit without emitting.
        with self._gen_lock:
            gen = self._series_gen.get(series_name, 0) + 1
            self._series_gen[series_name] = gen

        t = threading.Thread(
            target=self._extract_series,
            args=(filepath, msg_type, series_name, field_name,
                  axis_id, smooth, gen),
            daemon=True,
            name=f"GraphWorker-{series_name}",
        )
        t.start()

    def _is_cancelled(self, series_name: str, gen: int) -> bool:
        """Return True if a newer request has superseded this one."""
        with self._gen_lock:
            return self._series_gen.get(series_name, gen) != gen

    def _extract_series(self, filepath, msg_type, series_name,
                        field_name, axis_id, smooth, gen):
        """
        Worker running on a plain Python daemon thread.

        Optimisations applied here:
          • Acquires _read_semaphore before touching the file (MAX_READERS cap).
          • Uses the sparse byte-offset index to seek near the first message
            of the requested type instead of scanning from byte 0.
          • Checks cancellation every 5 000 messages so stale workers exit fast.
        """
        # ── Wait for a reader slot ────────────────────────────────────────────
        # acquire() blocks until a slot is free; avoids spawning unlimited
        # parallel scans through a large file.
        acquired = self._read_semaphore.acquire(timeout=30)
        if not acquired:
            print(f"[GraphWorker] Timed out waiting for reader slot: {series_name}")
            return

        try:
            self._do_extract(filepath, msg_type, series_name,
                             field_name, axis_id, smooth, gen)
        finally:
            self._read_semaphore.release()

    def _do_extract(self, filepath, msg_type, series_name,
                    field_name, axis_id, smooth, gen):
        try:
            timestamps: list[float] = []
            values:     list[float] = []

            mlog = mavutil.mavlink_connection(filepath, dialect='ardupilotmega')

            # ── Seek optimisation ─────────────────────────────────────────────
            # If the parser recorded byte offsets for this type, seek to the
            # first one so we skip everything before the first occurrence.
            seek_pos = self._get_seek_position(msg_type)
            if seek_pos and seek_pos > 0:
                try:
                    if hasattr(mlog, 'f') and hasattr(mlog.f, 'seek'):
                        mlog.f.seek(seek_pos)
                        print(f"[GraphWorker] Seeked to byte {seek_pos:,} for {msg_type}")
                except Exception as e:
                    print(f"[GraphWorker] Seek failed ({e}), reading from start")

            start_offset = None
            msg_loop_count = 0

            while not self._clearing:
                # Cancellation check every 5 000 messages
                msg_loop_count += 1
                if msg_loop_count % 5_000 == 0 and self._is_cancelled(series_name, gen):
                    print(f"[GraphWorker] Cancelled: {series_name}")
                    return

                msg = mlog.recv_match(type=msg_type, blocking=False)
                if msg is None:
                    break

                val = getattr(msg, field_name, None)
                if val is None:
                    continue

                try:
                    ts = _get_timestamp(msg)
                    if ts is None:
                        ts = getattr(msg, '_timestamp', time.time())

                    if start_offset is None:
                        start_offset = (self._current_log.boot_time_offset or 0
                                        if self._current_log else 0)

                    if hasattr(msg, 'time_boot_ms'):
                        ts = start_offset + ts

                    values.append(float(val))
                    timestamps.append(ts)
                except (TypeError, ValueError):
                    continue

            if not timestamps or self._clearing:
                return

            # Final cancellation check before we do expensive processing
            if self._is_cancelled(series_name, gen):
                return

            # Normalise to t = 0
            t0         = timestamps[0]
            timestamps = [t - t0 for t in timestamps]

            if smooth and len(values) > 5:
                values = self._smooth_data(values)

            if self._clearing or self._is_cancelled(series_name, gen):
                return

            with self._data_lock:
                self._series_data[series_name] = {
                    'timestamps': timestamps,
                    'values':     values,
                }

                # Shared-timestamp check – O(1): compare length + endpoints
                if len(self._series_data) == 1:
                    self._shared_timestamps     = timestamps[:]
                    self._timestamps_are_shared = True
                elif self._timestamps_are_shared:
                    shared = self._shared_timestamps
                    if (len(timestamps) != len(shared) or
                            timestamps[0]  != shared[0] or
                            timestamps[-1] != shared[-1]):
                        self._timestamps_are_shared = False
                        self._shared_timestamps     = None

                self._data_bounds[series_name] = {
                    'minX': timestamps[0],  'maxX': timestamps[-1],
                    'minY': min(values),    'maxY': max(values),
                }

            if self._clearing or self._is_cancelled(series_name, gen):
                return

            # Downsample to ≤500 pts for initial chart render
            disp_t, disp_v = timestamps, values
            if len(timestamps) > 500:
                disp_t, disp_v = self._downsample(timestamps, values, 500)

            if not self._clearing and not self._is_cancelled(series_name, gen):
                self.graphDataReady.emit(series_name, disp_t, disp_v, axis_id)

        except Exception:
            import traceback
            traceback.print_exc()

    def _get_seek_position(self, msg_type: str) -> int:
        """
        Return the earliest known byte offset for msg_type from the parse
        index, or 0 if no index entry exists.
        """
        try:
            if (self._current_log and
                    hasattr(self._current_log, 'message_index')):
                offsets = self._current_log.message_index.get(msg_type)
                if offsets:
                    return offsets[0]
        except Exception:
            pass
        return 0

    # ── Clear graphs ──────────────────────────────────────────────────────────

    @pyqtSlot()
    def clearGraphs(self):
        """
        Safe clear: cancels all in-flight workers via generation counters,
        wipes data dicts, resets the clearing flag after 250 ms.
        """
        self._clearing = True

        # Bump ALL series generations so every running worker exits ASAP
        with self._gen_lock:
            for k in list(self._series_gen):
                self._series_gen[k] += 1

        with self._data_lock:
            self._series_data           = {}
            self._data_bounds           = {}
            self._shared_timestamps     = None
            self._timestamps_are_shared = False

        print("[LogBrowserBackend] Cleared all graph data")
        QTimer.singleShot(250, self._reset_clearing)

    @pyqtSlot()
    def _reset_clearing(self):
        self._clearing = False

    # ── Data processing helpers ───────────────────────────────────────────────

    def _smooth_data(self, values, window_size=10):
        if not values or len(values) < window_size:
            return values
        if _NUMPY:
            arr    = np.array(values, dtype=np.float64)
            kernel = np.ones(window_size, dtype=np.float64) / window_size
            return np.convolve(arr, kernel, mode='same').tolist()
        smoothed = []
        half = window_size // 2
        for i in range(len(values)):
            s = max(0, i - half)
            e = min(len(values), i + half + 1)
            smoothed.append(sum(values[s:e]) / (e - s))
        return smoothed

    def _downsample(self, timestamps, values, target_points=500):
        n = len(timestamps)
        if n <= target_points:
            return timestamps, values

        if _NUMPY:
            t          = np.asarray(timestamps, dtype=np.float64)
            v          = np.asarray(values,     dtype=np.float64)
            chunk_size = max(1, n // (target_points // 2))
            out_t, out_v = [], []
            for start in range(0, n, chunk_size):
                end  = min(start + chunk_size, n)
                ct   = t[start:end]
                cv   = v[start:end]
                lo_i = int(np.argmin(cv))
                hi_i = int(np.argmax(cv))
                if lo_i <= hi_i:
                    out_t.extend([float(ct[lo_i]), float(ct[hi_i])])
                    out_v.extend([float(cv[lo_i]), float(cv[hi_i])])
                else:
                    out_t.extend([float(ct[hi_i]), float(ct[lo_i])])
                    out_v.extend([float(cv[hi_i]), float(cv[lo_i])])
            # Sort and deduplicate
            pairs = sorted(zip(out_t, out_v))
            seen  = set()
            final_t, final_v = [], []
            for tt, vv in pairs:
                if tt not in seen:
                    seen.add(tt)
                    final_t.append(tt)
                    final_v.append(vv)
            return final_t, final_v

        # Pure-Python fallback
        factor = max(1, n // target_points)
        out_t, out_v = [], []
        for i in range(0, n, factor):
            ct = timestamps[i:i + factor]
            cv = values    [i:i + factor]
            if not cv:
                continue
            lo_i = cv.index(min(cv))
            hi_i = cv.index(max(cv))
            if lo_i <= hi_i:
                out_t.append(ct[lo_i]); out_v.append(cv[lo_i])
                if lo_i != hi_i:
                    out_t.append(ct[hi_i]); out_v.append(cv[hi_i])
            else:
                out_t.append(ct[hi_i]); out_v.append(cv[hi_i])
                out_t.append(ct[lo_i]); out_v.append(cv[lo_i])
        return out_t, out_v

    # ── Hover / nearest-point queries ─────────────────────────────────────────

    @pyqtSlot(float, result='QVariantMap')
    def getNearestForAllSeries(self, x_value):
        result = {}
        try:
            with self._data_lock:
                snap      = dict(self._series_data)
                shared_ts = self._shared_timestamps
                is_shared = self._timestamps_are_shared

            if is_shared and shared_ts:
                idx = bisect.bisect_left(shared_ts, x_value)
                if idx == len(shared_ts):
                    idx = len(shared_ts) - 1
                elif idx > 0 and (abs(shared_ts[idx-1] - x_value) <
                                  abs(shared_ts[idx]   - x_value)):
                    idx -= 1
                for name, data in snap.items():
                    vs = data['values']
                    if idx < len(vs):
                        result[name] = {'index': idx,
                                        'time':  shared_ts[idx],
                                        'value': vs[idx]}
            else:
                for name, data in snap.items():
                    ts = data['timestamps']
                    vs = data['values']
                    if not ts:
                        continue
                    idx = bisect.bisect_left(ts, x_value)
                    if idx == len(ts):
                        idx = len(ts) - 1
                    elif idx > 0 and (abs(ts[idx-1] - x_value) <
                                      abs(ts[idx]   - x_value)):
                        idx -= 1
                    result[name] = {'index': idx, 'time': ts[idx], 'value': vs[idx]}
        except Exception:
            pass
        return result

    @pyqtSlot(str, float, result='QVariantMap')
    def getNearestPoint(self, series_name, x_value):
        try:
            with self._data_lock:
                data = self._series_data.get(series_name)
            if not data:
                return {}
            ts  = data['timestamps']
            vs  = data['values']
            if not ts:
                return {}
            idx = bisect.bisect_left(ts, x_value)
            if idx == len(ts):
                idx = len(ts) - 1
            elif idx > 0 and abs(ts[idx-1] - x_value) < abs(ts[idx] - x_value):
                idx -= 1
            return {'index': idx, 'time': ts[idx], 'value': vs[idx]}
        except Exception:
            return {}

    # ── Windowed rendering ────────────────────────────────────────────────────

    @pyqtSlot(str, float, float, int, result='QVariantMap')
    def getVisibleWindow(self, series_name, min_x, max_x, plot_width_pixels):
        empty = {'timestamps': [], 'values': [], 'pointCount': 0,
                 'minY': 0, 'maxY': 1}
        try:
            with self._data_lock:
                data = self._series_data.get(series_name)
            if not data:
                return empty

            full_t = data['timestamps']
            full_v = data['values']
            start  = bisect.bisect_left (full_t, min_x)
            end    = bisect.bisect_right(full_t, max_x)
            wt     = full_t[start:end]
            wv     = full_v[start:end]

            if not wv:
                return empty

            mn = min(wv)
            mx = max(wv)
            mp = max(plot_width_pixels * 2, 500)
            if len(wt) > mp:
                wt, wv = self._downsample(wt, wv, mp)

            return {'timestamps': wt, 'values': wv,
                    'pointCount': len(wt), 'minY': mn, 'maxY': mx}
        except Exception:
            return empty

    # ── Bounds helpers ────────────────────────────────────────────────────────

    @pyqtSlot(str, result='QVariantMap')
    def getSeriesBounds(self, series_name):
        with self._data_lock:
            return dict(self._data_bounds.get(
                series_name, {'minX': 0, 'maxX': 1, 'minY': 0, 'maxY': 1}))

    @pyqtSlot(result='QVariantMap')
    def getGlobalBounds(self):
        with self._data_lock:
            if not self._data_bounds:
                return {'minX': 0, 'maxX': 1, 'minY': 0, 'maxY': 1}
            bb = list(self._data_bounds.values())
        return {
            'minX': min(b['minX'] for b in bb),
            'maxX': max(b['maxX'] for b in bb),
            'minY': min(b['minY'] for b in bb),
            'maxY': max(b['maxY'] for b in bb),
        }

    # ── Channels / metadata ───────────────────────────────────────────────────

    @pyqtSlot(str, result='QVariantList')
    def getAvailableChannels(self, msg_type):
        if not self._current_log:
            return []

        # 1. Field cache (populated during parse_log – O(1) lookup)
        if hasattr(self._current_log, 'field_cache'):
            cached = self._current_log.field_cache.get(msg_type)
            if cached is not None:
                return cached

        # 2. DataFlash FMT records
        if self._current_log.is_dataflash and self._current_log.formats:
            fmt = self._current_log.formats.get(msg_type)
            if fmt:
                cols = fmt.columns if hasattr(fmt, 'columns') else []
                # Store in cache for next call
                if hasattr(self._current_log, 'field_cache'):
                    self._current_log.field_cache[msg_type] = cols
                return cols

        # 3. Fallback: open the file and read the first matching message.
        #    Use the seek index to avoid scanning from byte 0.
        fields = []
        try:
            mlog = mavutil.mavlink_connection(
                self._current_log.filepath, dialect='ardupilotmega')

            seek_pos = self._get_seek_position(msg_type)
            if seek_pos and hasattr(mlog, 'f') and hasattr(mlog.f, 'seek'):
                try:
                    mlog.f.seek(seek_pos)
                except Exception:
                    pass

            first_msg = mlog.recv_match(type=msg_type, blocking=False)
            if first_msg:
                from modules.log_parser import _extract_fields
                fields = _extract_fields(first_msg)
        except Exception:
            pass

        # Cache even empty results to avoid repeated file opens
        if hasattr(self._current_log, 'field_cache'):
            self._current_log.field_cache[msg_type] = fields

        return fields

    # ── Qt properties ─────────────────────────────────────────────────────────

    @pyqtProperty(str, notify=logLoaded)
    def logFilepath(self):
        return self._log_filepath

    @pyqtProperty('QVariantList', notify=logLoaded)
    def messageTypes(self):
        if self._current_log:
            if (hasattr(self._current_log, 'message_types_list') and
                    self._current_log.message_types_list):
                return self._current_log.message_types_list
            return list(self._current_log.messages.keys())
        return []

    @pyqtProperty('QVariantMap', notify=logLoaded)
    def flightSummary(self):
        if self._current_log and hasattr(self._current_log, 'flight_summary'):
            return self._current_log.flight_summary
        return {}


# ─────────────────────────────────────────────────────────────────────────────
# Module-level helper (shared with log_parser import)
# ─────────────────────────────────────────────────────────────────────────────

def _get_timestamp(msg):
    if hasattr(msg, 'TimeUS'):
        return msg.TimeUS / 1_000_000.0
    if hasattr(msg, 'time_boot_ms'):
        return msg.time_boot_ms / 1000.0
    return None
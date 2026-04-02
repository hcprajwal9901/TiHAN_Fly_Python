"""
auto_connect_worker.py
======================
Mission Planner-style AutoConnectWorker for TiHAN Fly GCS.

Improvements over the original implementation:
  1. Raw byte sniff   — checks for MAVLink magic bytes (0xFE / 0xFD) on the
                        raw serial port *before* spinning up the full mavutil
                        parser.  Dead ports are skipped in < 300 ms instead of
                        waiting 2 full seconds.
  2. VID/PID table    — known flight-controller USB Vendor/Product IDs are
                        prioritised and given a longer heartbeat timeout,
                        exactly as Mission Planner does.
  3. Dynamic timeout  — known FC chips get 2 s; unknown ports get 0.4 s.
  4. SITL-first       — UDP 127.0.0.1:14550 is always checked first (zero cost
                        when SITL is not running).
  5. Stop-safe        — every blocking call is guarded by _should_stop so the
                        Cancel button is always responsive.
"""

import time
import serial
import serial.tools.list_ports
from PyQt5.QtCore import QThread, pyqtSignal
from pymavlink import mavutil


# ---------------------------------------------------------------------------
# Known flight-controller USB Vendor / Product IDs
# Format: { vid: [pid, ...] }
# ---------------------------------------------------------------------------
FC_VID_PID: dict[int, list[int]] = {
    0x26AC: [0x0011, 0x0012, 0x0021],          # 3DRobotics / mRo Pixhawk
    0x2DAE: [0x1011, 0x1016, 0x1001],          # CubePilot (Cube Black / Orange / Purple)
    0x1209: [0x5741],                           # Holybro Pixhawk 6C / Kakute
    0x27AC: [0x1151],                           # Emlid Navio2 / Reach
    0x10C4: [0xEA60, 0xEA61],                  # Silicon Labs CP2102 / CP2104
    0x0403: [0x6001, 0x6010, 0x6011, 0x6015],  # FTDI FT232 / FT2232
    0x1A86: [0x7523, 0x7522, 0x55D4],          # WCH CH340 / CH341
    0x067B: [0x2303, 0x23A3],                  # Prolific PL2303
    0x0483: [0x5740, 0x5741],                  # STMicro virtual COM (F4/F7/H7 DFU)
    0x239A: [0x000F, 0x8022],                  # Adafruit / Feather M0
}

# Description keywords that indicate a likely FC port (fallback if no VID/PID)
FC_KEYWORDS = [
    "CP210", "FTDI", "CH340", "CH341", "PL230", "PL2303",
    "PIXHAWK", "CUBE", "ACM", "HOLYBRO", "RADIOLINK",
    "MATEK", "KAKUTE", "SPEEDYBEE",
]

# MAVLink framing magic bytes
MAVLINK_V1_MAGIC = 0xFE
MAVLINK_V2_MAGIC = 0xFD

# Scan configuration
BAUD_RATES       = [115200, 57600, 921600]   # Mission Planner order
HB_TIMEOUT_FC    = 3.5    # seconds — known FC chip
HB_TIMEOUT_SLOW  = 0.5    # seconds — unknown / generic port
RAW_SNIFF_BYTES  = 96     # bytes to read for quick magic-byte scan
RAW_SNIFF_TIME   = 0.25   # seconds to wait for raw bytes

def is_known_fc(port_info) -> bool:
    """Return True if the port looks like a flight-controller by VID/PID."""
    vid = port_info.vid
    pid = port_info.pid
    if vid and pid:
        allowed_pids = FC_VID_PID.get(vid)
        if allowed_pids is not None and pid in allowed_pids:
            return True
    # Fallback: description / manufacturer string match
    haystack = " ".join([
        port_info.description or "",
        str(port_info.manufacturer or ""),
        port_info.hwid or "",
    ]).upper()
    return any(k in haystack for k in FC_KEYWORDS)


class AutoConnectWorker(QThread):
    """
    Background worker that scans all available serial ports (plus SITL) and
    probes each one at common MAVLink baud rates until a heartbeat is found.
    """

    autoConnectFound    = pyqtSignal(str, int)
    autoConnectProgress = pyqtSignal(str)
    autoConnectFailed   = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._should_stop = False

    # ---------------------------------------------------------------------- #
    def run(self):
        """Main scan loop — runs in background thread."""
        self._should_stop = False

        if not self._should_stop:
            self.autoConnectProgress.emit("Checking SITL (udp:127.0.0.1:14550)…")
            result = self._probe_mavutil("udp:127.0.0.1:14550", 0, timeout=0.5)
            if result:
                print("[AutoConnect] ✅ SITL found on udp:127.0.0.1:14550")
                self.autoConnectFound.emit("udp:127.0.0.1:14550", 0)
                return

        if self._should_stop: return

        fc_ports, other_ports = self._gather_ports()
        all_ports = fc_ports + other_ports

        if not all_ports:
            print("[AutoConnect] No serial ports found to scan.")
            self.autoConnectProgress.emit("No serial ports detected")
            self.autoConnectFailed.emit()
            return

        total = len(all_ports)
        print(f"[AutoConnect] Scanning {total} port(s): FC={len(fc_ports)}, other={len(other_ports)}")

        for idx, (device, port_info) in enumerate(all_ports):
            if self._should_stop: return

            known_fc = port_info is not None and is_known_fc(port_info)
            hb_timeout = HB_TIMEOUT_FC if known_fc else HB_TIMEOUT_SLOW

            for baud in BAUD_RATES:
                if self._should_stop: return

                msg = f"[{idx+1}/{total}] Probing {device} @ {baud}…"
                print(f"[AutoConnect] {msg}")
                self.autoConnectProgress.emit(msg)

                if device.startswith(("COM", "/dev/")):
                    if not self._raw_sniff(device, baud):
                        continue

                if self._should_stop: return

                found = self._probe_mavutil(device, baud, timeout=hb_timeout)
                if found:
                    print(f"[AutoConnect] ✅ MAVLink device found on {device} @ {baud}")
                    self.autoConnectFound.emit(device, baud)
                    return

        print("[AutoConnect] No MAVLink device found after scanning all ports.")
        self.autoConnectFailed.emit()

    # ---------------------------------------------------------------------- #
    def _gather_ports(self):
        fc_ports = []
        other_ports = []
        try:
            serial_ports = list(serial.tools.list_ports.comports())
            for p in serial_ports:
                entry = (p.device, p)
                if is_known_fc(p):
                    fc_ports.append(entry)
                else:
                    other_ports.append(entry)
        except Exception as e:
            print(f"[AutoConnect] Error listing serial ports: {e}")
        return fc_ports, other_ports

    # ---------------------------------------------------------------------- #
    def _raw_sniff(self, port: str, baud: int) -> bool:
        """
        Open the raw serial port and look for MAVLink magic bytes (0xFE / 0xFD)
        within a short window.
        """
        ser = None
        for attempt in range(5):
            if self._should_stop: return False
            try:
                ser = serial.Serial()
                ser.port = port
                ser.baudrate = baud
                ser.timeout = RAW_SNIFF_TIME
                ser.write_timeout = 0.1
                # Disable DTR/RTS manipulation so we don't reboot USB FCs
                ser.dtr = False
                ser.rts = False
                ser.exclusive = True
                ser.open()
                break
            except serial.SerialException as e:
                err_str = str(e)
                if "Access is denied" in err_str or "PermissionError" in err_str:
                    time.sleep(0.2)  # Wait for background port_manager to release it
                else:
                    return False
            except Exception:
                return False
        else:
            return False   # Exhausted retries

        try:
            # We don't reset input buffer because that also takes time to stabilise
            data = ser.read(RAW_SNIFF_BYTES)
            if MAVLINK_V2_MAGIC in data or MAVLINK_V1_MAGIC in data:
                print(f"[AutoConnect]   → Magic bytes found on {port} @ {baud} ✓")
                return True
            return False
        except Exception:
            return False
        finally:
            if ser and ser.is_open:
                try:
                    ser.close()
                    time.sleep(0.15)  # Give Windows time to release the COM port handle
                except Exception:
                    pass

    # ---------------------------------------------------------------------- #
    def _probe_mavutil(self, port: str, baud: int, timeout: float) -> bool:
        """
        Full MAVLink connection probe at the given port/baud.
        """
        conn = None
        # Retry loop to handle 'Access Denied' if port_manager locked it for a moment
        for attempt in range(5):
            if self._should_stop: return False
            try:
                conn = mavutil.mavlink_connection(
                    port,
                    baud=baud,
                    source_system=255,
                    source_component=0,
                    force_connected=True,
                )
                break
            except Exception as e:
                err_str = str(e)
                if "Access is denied" in err_str or "PermissionError" in err_str:
                    time.sleep(0.25)
                else:
                    print(f"[AutoConnect] ⚠️ _probe_mavutil open failed {port}: {e}")
                    return False
        else:
            return False

        try:
            msg = conn.wait_heartbeat(timeout=timeout)
            if msg is not None:
                # If we get ANY valid heartbeat message, connection is good!
                return True
        except Exception as e:
            print(f"[AutoConnect] ⚠️ _probe_mavutil heartbeat wait failed {port}: {e}")
            pass
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass
        return False

    # ---------------------------------------------------------------------- #
    def stop(self):
        """Request cancellation of the ongoing scan."""
        self._should_stop = True

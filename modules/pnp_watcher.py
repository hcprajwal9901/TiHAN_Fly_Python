"""
pnp_watcher.py
==============
Windows Plug-and-Play (USB hotplug) watcher for TiHAN Fly GCS.

Architecture mirrors ArduPilot Mission Planner on Windows:
  • Listens for Win32 USB device-arrival events via WMI.
  • When a USB device is plugged in, waits 1.5 s for Windows to enumerate
    the COM port, then emits deviceArrived(port_name).
  • When a USB device is removed, emits deviceRemoved(port_name).
  • On non-Windows OS or if the `wmi` package is not installed, the class
    is a harmless no-op stub — the application continues to work normally.

Usage:
    from modules.pnp_watcher import PnpWatcher

    watcher = PnpWatcher()
    watcher.deviceArrived.connect(lambda port: ...)
    watcher.deviceRemoved.connect(lambda port: ...)
    watcher.start()          # starts background thread
    ...
    watcher.stop(); watcher.wait()
"""

import sys
import time
import serial.tools.list_ports
from PyQt5.QtCore import QThread, pyqtSignal

# ── Platform guard ──────────────────────────────────────────────────────────
_WMI_AVAILABLE = False
_wmi = None

if sys.platform == "win32":
    try:
        import wmi as _wmi_module
        _wmi = _wmi_module
        _WMI_AVAILABLE = True
        print("[PnpWatcher] ✅ WMI available — USB hotplug detection enabled")
    except ImportError:
        print("[PnpWatcher] ⚠️  `wmi` package not found — hotplug disabled (pip install wmi)")
    except Exception as e:
        print(f"[PnpWatcher] ⚠️  WMI initialisation error: {e} — hotplug disabled")
else:
    print(f"[PnpWatcher] ℹ️  Non-Windows platform ({sys.platform}) — hotplug detection skipped")


def _get_com_ports() -> set[str]:
    """Return the set of currently active COM port device names."""
    try:
        return {p.device for p in serial.tools.list_ports.comports()}
    except Exception:
        return set()


class PnpWatcher(QThread):
    """
    Background thread that monitors USB device-arrival events and emits Qt
    signals so the rest of the application can react immediately.

    Signals
    -------
    deviceArrived(port_name: str)
        Emitted ~1.5 s after a USB serial device is plugged in.
        port_name is the OS device path (e.g. "COM7" on Windows,
        "/dev/ttyUSB0" on Linux).  Empty string if the new COM port
        cannot yet be determined.

    deviceRemoved(port_name: str)
        Emitted when a USB serial device's COM port disappears.
    """

    deviceArrived = pyqtSignal(str)   # port that just appeared
    deviceRemoved = pyqtSignal(str)   # port that just disappeared

    # Polling interval (seconds) used on non-WMI path
    POLL_INTERVAL = 2.0
    # How long to wait after a USB event before re-reading the port list
    USB_ENUM_DELAY = 1.5

    def __init__(self, parent=None):
        super().__init__(parent)
        self._should_stop = False
        self.setObjectName("PnpWatcherThread")

    # ---------------------------------------------------------------------- #
    def run(self):
        if _WMI_AVAILABLE:
            self._run_wmi()
        else:
            self._run_polling()

    # ---------------------------------------------------------------------- #
    def _run_wmi(self):
        """
        WMI event-driven path (Windows only).
        Subscribes to Win32_DeviceChangeEvent to get notified of USB events
        and then diffs the COM port list to find what changed.
        """
        try:
            # Each thread needs its own WMI connection
            c = _wmi.WMI()
            watcher = c.Win32_DeviceChangeEvent.watch_for()
            print("[PnpWatcher] WMI event loop started — watching for USB events…")

            known_ports = _get_com_ports()

            while not self._should_stop:
                try:
                    # Non-blocking poll — timeout 1 s so we can check _should_stop
                    event = watcher(timeout_ms=1000)
                    if event is None:
                        continue

                    # Win32_DeviceChangeEvent.EventType:
                    #   1 = ConfigurationChanged, 2 = DeviceArrival,
                    #   3 = DeviceRemoval,        4 = DockingChange
                    event_type = getattr(event, "EventType", None)

                    if event_type in (2, 3):           # arrival or removal
                        # Give Windows 1.5 s to enumerate the new COM port
                        deadline = time.monotonic() + self.USB_ENUM_DELAY
                        while time.monotonic() < deadline:
                            if self._should_stop:
                                return
                            time.sleep(0.1)

                        new_ports = _get_com_ports()
                        appeared  = new_ports - known_ports
                        removed   = known_ports - new_ports
                        known_ports = new_ports

                        for p in appeared:
                            print(f"[PnpWatcher] 🔌 USB device arrived → {p}")
                            self.deviceArrived.emit(p)

                        for p in removed:
                            print(f"[PnpWatcher] 🔌 USB device removed → {p}")
                            self.deviceRemoved.emit(p)

                except Exception as inner_e:
                    # WMI raises an exception for normal poll timeouts (WBEM_E_TIMED_OUT).
                    # This is expected behaviour — NOT a real error.
                    # Suppress silently; only log genuinely unexpected errors.
                    if self._should_stop:
                        return
                    err_str = str(inner_e)
                    # -2147209215 == WBEM_E_TIMED_OUT  (normal 1-s poll timeout)
                    # "Timed out" is the human-readable form in the exception tuple
                    _is_normal_timeout = (
                        "-2147209215" in err_str          # numeric WBEM_E_TIMED_OUT
                        or "timed out" in err_str.lower() # string form (any case)
                        or "timeout"   in err_str.lower() # alternative spelling
                    )
                    if not _is_normal_timeout:
                        print(f"[PnpWatcher] WMI unexpected error: {inner_e}")
                    time.sleep(0.05)

        except Exception as outer_e:
            print(f"[PnpWatcher] ❌ WMI initialisation failed in thread: {outer_e}")
            print("[PnpWatcher] Falling back to polling mode…")
            self._run_polling()

    # ---------------------------------------------------------------------- #
    def _run_polling(self):
        """
        Polling fallback — diffs the port list every POLL_INTERVAL seconds.
        Used on non-Windows or when WMI is unavailable.
        Slower (up to 2 s latency) but totally portable.
        """
        print(f"[PnpWatcher] Polling mode active (interval={self.POLL_INTERVAL}s)")
        known_ports = _get_com_ports()

        while not self._should_stop:
            time.sleep(self.POLL_INTERVAL)
            if self._should_stop:
                break

            current_ports = _get_com_ports()
            appeared = current_ports - known_ports
            removed  = known_ports  - current_ports
            known_ports = current_ports

            for p in appeared:
                print(f"[PnpWatcher] 🔌 New port detected (polling) → {p}")
                self.deviceArrived.emit(p)

            for p in removed:
                print(f"[PnpWatcher] 🔌 Port removed (polling) → {p}")
                self.deviceRemoved.emit(p)

    # ---------------------------------------------------------------------- #
    def stop(self):
        """Request the watcher to stop cleanly."""
        print("[PnpWatcher] Stop requested.")
        self._should_stop = True

import threading
# All callers of serial.tools.list_ports.comports() must acquire this lock.
# Windows SetupAPI is not re-entrant — concurrent calls cause access violations.
PORT_SCAN_LOCK = threading.Lock()

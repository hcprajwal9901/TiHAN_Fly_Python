"""
modules/rtsp_frame_provider.py
================================
TiHAN GCS — subprocess-isolated RTSP frame provider for QML Image element.

Thread-safety design (Python 3.14 / PyQt5 compatible):
  • The pipe-reader daemon thread puts raw JPEG bytes into a thread-safe
    queue.SimpleQueue — it NEVER calls any Qt/PyQt5 API.
  • A QTimer running on the main Qt thread drains the queue every ~33 ms
    and calls QImage.loadFromData() — all Qt work is on the main thread.
  • No cross-thread signal emission (which can be fragile on Python 3.14).

Frame flow:
    child  : cv2 → JPEG → 4-byte-length-framed binary → stdout
    reader : pipe → SimpleQueue (raw bytes only — NO Qt here)
    timer  : main thread → drains queue → QImage.loadFromData()
    Qt     : requestImage() returns self._latest to QML Image
"""

import os
import sys
import struct
import threading
import traceback
import queue
import time
from pathlib import Path

from PyQt5.QtCore import QTimer, QSize
from PyQt5.QtGui import QImage
from PyQt5.QtQuick import QQuickImageProvider

# Detect PyInstaller frozen environment
_IS_FROZEN = getattr(sys, 'frozen', False)

# Absolute path to the standalone worker script (same directory as this file)
# Only meaningful when NOT frozen.
_WORKER_SCRIPT = str(Path(__file__).parent / "rtsp_worker_script.py")

_HEADER = struct.Struct('>I')   # 4-byte big-endian frame length

# Sentinel objects used in the status queue
_CONNECTED  = object()
_STREAMING  = object()
_STOPPED    = object()


def _read_exactly(fp, n: int) -> bytes:
    """Read exactly n bytes from a binary file object. Returns b'' on EOF."""
    buf = bytearray()
    while len(buf) < n:
        chunk = fp.read(n - len(buf))
        if not chunk:
            return b''
        buf += chunk
    return bytes(buf)


class RtspFrameProvider(QQuickImageProvider):
    """
    QQuickImageProvider backed by an isolated subprocess running cv2.

    Register with the QML engine:
        engine.addImageProvider("rtspframes", rtsp_provider)

    Reference in QML:
        Image { cache: false; asynchronous: false;
                source: "image://rtspframes/frame" }
    """

    def __init__(self, on_stream_failed=None):
        super().__init__(QQuickImageProvider.Image)
        self._lock             = threading.Lock()
        self._latest           = self._blank()
        self._running          = False
        self._on_stream_failed = on_stream_failed
        self._proc             = None   # subprocess.Popen
        self._reader_thread    = None
        self._stop_event       = threading.Event()   # used by thread-worker fallback

        # Thread-safe queues — the ONLY bridge between reader thread and main thread.
        # SimpleQueue is lock-based and safe to put/get across threads.
        self._frame_q  = queue.SimpleQueue()   # raw JPEG bytes
        self._status_q = queue.SimpleQueue()   # str: 'connected'|'streaming'|
                                               #       'stopped'|'error:<msg>'

        # QTimer lives on (and fires on) the main Qt thread.
        # It drains queues and does all Qt work.
        self._poll_timer = QTimer()
        self._poll_timer.timeout.connect(self._drain_queues)
        self._poll_timer.start(33)   # ~30 fps drain rate

        print("[RtspFrameProvider] Initialized (queue+timer mode)")

    # ── QQuickImageProvider ────────────────────────────────────────────────

    def requestImage(self, _id, size, requestedSize=None):
        """
        Called on the main thread by QML to get the latest frame.

        PyQt5 requires the return value to be a (QImage, QSize) tuple.
        The QSize tells Qt the actual pixel dimensions of the image.
        """
        try:
            with self._lock:
                img = self._latest.copy()
            if (requestedSize is not None
                    and requestedSize.isValid()
                    and requestedSize.width() > 0
                    and requestedSize.height() > 0):
                img = img.scaled(requestedSize.width(), requestedSize.height())
            return img, QSize(img.width(), img.height())
        except Exception as e:
            print(f"[RtspFrameProvider] requestImage error: {e}")
            blank = self._blank()
            return blank, QSize(blank.width(), blank.height())

    # ── Public API ─────────────────────────────────────────────────────────

    def start(self, rtsp_url: str):
        """Launch the child process (or thread fallback). Call from the main thread."""
        self.stop()
        if not rtsp_url:
            return

        self._running = True
        self._stop_event.clear()

        if _IS_FROZEN:
            # ── Frozen .exe: run cv2 capture in a daemon thread ──────────
            print(f"[RtspFrameProvider] Frozen build detected — using thread worker")
            self._reader_thread = threading.Thread(
                target=self._thread_worker,
                args=(rtsp_url,),
                daemon=True,
                name="RtspThreadWorker",
            )
            self._reader_thread.start()
            print(f"[RtspFrameProvider] Started thread worker → {rtsp_url}")
        else:
            # ── Normal Python: launch isolated subprocess ────────────────
            try:
                import subprocess  # noqa: PLC0415

                self._proc = subprocess.Popen(
                    [sys.executable, _WORKER_SCRIPT, rtsp_url],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    stdin=subprocess.DEVNULL,
                )
            except Exception as exc:
                print(f"[RtspFrameProvider] Failed to launch child process: {exc}")
                self._running = False
                return

            self._reader_thread = threading.Thread(
                target=self._pipe_reader,
                daemon=True,
                name="RtspPipeReader",
            )
            self._reader_thread.start()
            print(f"[RtspFrameProvider] Started child process → {rtsp_url}")

    def stop(self):
        """Kill the child process (or signal thread) and drain queues. Call from the main thread."""
        self._running = False
        self._stop_event.set()   # signal thread worker to stop

        proc, self._proc = self._proc, None
        if proc is not None:
            try:
                proc.terminate()
                proc.wait(timeout=1.0)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

        # Drain leftover items from the queues (no Qt calls, just discard)
        _drain_simple_queue(self._frame_q)
        _drain_simple_queue(self._status_q)

        # Reset to blank (main thread — safe)
        with self._lock:
            self._latest = self._blank()

        print("[RtspFrameProvider] Stopped")

    # ── Main-thread timer slot ─────────────────────────────────────────────

    def _drain_queues(self):
        """
        Called on the main Qt thread every ~33 ms by self._poll_timer.
        Processes status messages and the most recent JPEG frame.
        All Qt API calls happen here — NEVER in the reader thread.
        """
        # ── Status messages ──────────────────────────────────────────────
        while True:
            try:
                status = self._status_q.get_nowait()
            except queue.Empty:
                break
            self._handle_status(status)

        # ── Frames: consume ALL pending, keep only the newest ────────────
        latest_jpeg = None
        while True:
            try:
                latest_jpeg = self._frame_q.get_nowait()
            except queue.Empty:
                break

        if latest_jpeg is not None:
            try:
                img = QImage()
                if img.loadFromData(latest_jpeg):
                    with self._lock:
                        self._latest = img
            except Exception as e:
                print(f"[RtspFrameProvider] Frame decode error: {e}")

    def _handle_status(self, status: str):
        """Handle a status string on the main thread."""
        if status == 'connected':
            print("[RtspFrameProvider] Child connected to RTSP server")
        elif status == 'streaming':
            print("[RtspFrameProvider] ✅ Child streaming — first frame received")
        elif status == 'stopped':
            print("[RtspFrameProvider] Child stopped normally")
        elif status == 'reader_exited':
            print("[RtspFrameProvider] Pipe reader thread exited")
        elif status.startswith('error:'):
            msg = status[6:]
            print(f"[RtspFrameProvider] ❌ Child error: {msg}")
            if self._on_stream_failed:
                try:
                    self._on_stream_failed()
                except Exception:
                    pass
        else:
            print(f"[RtspFrameProvider] Status: {status}")

    # ── Internal ───────────────────────────────────────────────────────────

    @staticmethod
    def _blank():
        """Create a blank black QImage. Only call from the main thread."""
        img = QImage(640, 480, QImage.Format_RGB888)
        img.fill(0)
        return img

    def _pipe_reader(self):
        """
        Daemon thread: reads length-framed messages from the child stdout.

        *** MUST NOT call any Qt/PyQt5 API. ***
        Uses only SimpleQueue.put() and Python stdlib.
        """
        proc = self._proc
        try:
            fp = proc.stdout
            while self._running and proc.poll() is None:

                # ── Read 4-byte length header ────────────────────────────
                header = _read_exactly(fp, 4)
                if len(header) < 4:
                    break   # EOF / pipe closed

                length = _HEADER.unpack(header)[0]
                if length == 0 or length > 10 * 1024 * 1024:
                    # Sanity check: skip corrupt frame and stop
                    break

                # ── Read payload ─────────────────────────────────────────
                payload = _read_exactly(fp, length)
                if len(payload) < length:
                    break   # truncated

                # ── Route to appropriate queue ───────────────────────────
                if payload == b'CONNECTED':
                    self._status_q.put('connected')
                elif payload == b'STREAMING':
                    self._status_q.put('streaming')
                elif payload == b'STOPPED':
                    self._status_q.put('stopped')
                    break
                elif payload.startswith(b'ERROR:'):
                    msg = payload[6:].decode(errors='replace')
                    self._status_q.put(f'error:{msg}')
                    break
                else:
                    # JPEG frame — put raw bytes; main thread decodes to QImage
                    self._frame_q.put(payload)

        except Exception:
            traceback.print_exc()
        finally:
            self._status_q.put('reader_exited')

    def _thread_worker(self, rtsp_url: str):
        """
        Fallback for frozen (PyInstaller) builds.
        Runs cv2.VideoCapture directly in a daemon thread and feeds
        JPEG frames into self._frame_q / self._status_q.

        *** MUST NOT call any Qt/PyQt5 API. ***
        """
        try:
            import cv2  # noqa: PLC0415

            os.environ.setdefault(
                'OPENCV_FFMPEG_CAPTURE_OPTIONS',
                'rtsp_transport;tcp|timeout;5000000'
            )

            cap = cv2.VideoCapture(rtsp_url, cv2.CAP_FFMPEG)
            if not cap.isOpened():
                self._status_q.put(f'error:Cannot open {rtsp_url}')
                return

            self._status_q.put('connected')

            fail_count = 0
            first_frame = True

            while self._running and not self._stop_event.is_set():
                ret, frame = cap.read()
                if not ret or frame is None:
                    fail_count += 1
                    if fail_count > 20:
                        self._status_q.put('error:Too many read failures')
                        break
                    time.sleep(0.05)
                    continue

                fail_count = 0

                try:
                    small = cv2.resize(frame, (640, 480))
                    ok, jpeg_buf = cv2.imencode(
                        '.jpg', small, [cv2.IMWRITE_JPEG_QUALITY, 80])
                    if ok:
                        if first_frame:
                            self._status_q.put('streaming')
                            first_frame = False
                        self._frame_q.put(jpeg_buf.tobytes())
                except Exception:
                    pass

            cap.release()

        except Exception as exc:
            self._status_q.put(f'error:{exc}')
        finally:
            self._status_q.put('stopped')


# ── Module-level helper ────────────────────────────────────────────────────

def _drain_simple_queue(q: queue.SimpleQueue):
    """Discard all items currently in a SimpleQueue without blocking."""
    while True:
        try:
            q.get_nowait()
        except queue.Empty:
            break

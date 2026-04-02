"""
modules/rtsp_worker.py
========================
Standalone RTSP frame-capture worker — runs in a child process.

WHY A SEPARATE PROCESS:
    cv2.VideoCapture(url, cv2.CAP_FFMPEG) can crash at the C level
    (access violation / segfault) when initialising FFmpeg's RTSP client
    on Windows.  A C-level crash in a Python *thread* kills the entire
    process.  A C-level crash in a child *process* kills only that child;
    the main application stays alive.

NO Qt HERE — this file must not import PyQt5.  The child process started
by multiprocessing does not have a QApplication, so any Qt import would
fail.  Frames are JPEG-encoded and sent back to the parent via a
multiprocessing.Queue.
"""

import os
import time

FRAME_W = 640
FRAME_H = 480
JPEG_QUALITY = 80          # good balance of quality vs. throughput
MAX_READ_FAILURES = 20     # give up after this many consecutive failures


def worker(url: str, queue):
    """
    Entry point for the child process.

    Puts tuples into `queue`:
        ('connected', None)           — stream opened successfully
        ('frame',     bytes)          — JPEG-encoded frame
        ('error',     str)            — unrecoverable error
        ('stopped',   None)           — worker finished (normal exit)
    """
    import cv2  # noqa: PLC0415 — local import; child has no Qt, just cv2

    os.environ.setdefault(
        "OPENCV_FFMPEG_CAPTURE_OPTIONS",
        "rtsp_transport;tcp|timeout;5000000"
    )

    try:
        cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
        if not cap.isOpened():
            queue.put(('error', f'Cannot open stream: {url}'))
            return

        queue.put(('connected', None))

        fail_count = 0
        while True:
            ret, frame = cap.read()
            if not ret or frame is None:
                fail_count += 1
                if fail_count > MAX_READ_FAILURES:
                    queue.put(('error', 'Too many consecutive read failures'))
                    break
                time.sleep(0.1)
                continue

            fail_count = 0

            try:
                # Resize to a fixed canvas so QImage receives consistent dims
                small = cv2.resize(frame, (FRAME_W, FRAME_H))
                ok, jpeg_buf = cv2.imencode(
                    '.jpg', small,
                    [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY]
                )
                if ok:
                    try:
                        queue.put_nowait(('frame', jpeg_buf.tobytes()))
                    except Exception:
                        pass   # queue full — drop frame, stay real-time
            except Exception:
                pass  # frame conversion error — skip frame

        cap.release()

    except Exception as exc:
        queue.put(('error', str(exc)))
    finally:
        queue.put(('stopped', None))

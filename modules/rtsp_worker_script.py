#!/usr/bin/env python3
"""
modules/rtsp_worker_script.py
================================
Standalone script launched as a child process by RtspFrameProvider.

Usage: python rtsp_worker_script.py <rtsp_url>

Protocol (binary stdout):
    Each message = 4-byte big-endian length + that many bytes of payload.
    Payload is either:
        b'CONNECTED'           — stream opened OK
        b'STREAMING'          — first frame received
        b'ERROR:<message>'    — unrecoverable error
        b'STOPPED'            — worker finished
        <JPEG bytes>          — encoded video frame

No PyQt5 / Qt here. Only cv2 and stdlib.
If cv2 crashes at C level, only this child process dies.
The parent (main Qt app) continues running.
"""

import sys
import os
import struct
import time


def _write(out, data: bytes):
    out.write(struct.pack('>I', len(data)))
    out.write(data)
    out.flush()


def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    url = sys.argv[1]
    out = sys.stdout.buffer   # binary stdout → pipe to parent

    import cv2  # noqa — cv2 crash here only kills this child

    os.environ.setdefault(
        'OPENCV_FFMPEG_CAPTURE_OPTIONS',
        'rtsp_transport;tcp|timeout;5000000'
    )

    try:
        cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
        if not cap.isOpened():
            _write(out, f'ERROR:Cannot open {url}'.encode())
            return

        _write(out, b'CONNECTED')

        fail_count = 0
        first_frame = True

        while True:
            ret, frame = cap.read()
            if not ret or frame is None:
                fail_count += 1
                if fail_count > 20:
                    _write(out, b'ERROR:Too many read failures')
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
                        _write(out, b'STREAMING')
                        first_frame = False
                    _write(out, jpeg_buf.tobytes())
            except Exception:
                pass

        cap.release()

    except Exception as exc:
        try:
            _write(out, f'ERROR:{exc}'.encode())
        except Exception:
            pass
    finally:
        try:
            _write(out, b'STOPPED')
        except Exception:
            pass


if __name__ == '__main__':
    main()

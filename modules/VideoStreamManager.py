"""
modules/VideoStreamManager.py  (GStreamer Edition)
====================================================
TiHAN GCS — Multi-Camera GStreamer RTSP Stream Manager
Version: 2.0.0

Manages up to N concurrent GStreamer RTSP streams, one per camera_id.
Each stream runs in its own VideoWorkerThread (strict thread isolation).

Public API (callable from QML via context property):
  • startStream(camera_id, rtsp_url, username="", password="")
  • stopStream(camera_id)
  • stopAllStreams()
  • switchActiveCamera(camera_id)

Signals:
  • frameReady(camera_id, QImage)        — decoded video frame
  • streamStarted(camera_id)
  • streamStopped(camera_id)
  • streamError(camera_id, error_msg)
  • activeCameraChanged(camera_id)
  • connectionStatusChanged(camera_id, status_text)

Design:
  • Never blocks the main/UI thread
  • Each camera gets its own VideoWorkerThread
  • Parallel stream hard limit = MAX_PARALLEL_STREAMS (3)
  • Auto-reconnect handled inside VideoWorkerThread
"""

import logging
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer

from modules.GStreamerPipelineFactory import GStreamerPipelineFactory
# VideoWorkerThread is imported LAZILY inside _start_stream_impl().
# Importing it at module level would run Gst.init(None) immediately, loading
# GStreamer's bundled FFmpeg DLLs.  When cv2.VideoCapture(CAP_FFMPEG) then
# loads OpenCV's own FFmpeg DLLs the two conflict → process crash.
# By importing lazily, GStreamer DLLs are NEVER loaded unless startStream()
# is actually called (which it isn't when using the OpenCV rtsp_provider).

logger = logging.getLogger(__name__)

MAX_PARALLEL_STREAMS = 3


class VideoStreamManager(QObject):
    """
    Multi-camera GStreamer RTSP stream manager.
    One instance per application — expose to QML as a context property.
    """

    # ── Signals ───────────────────────────────────────────────────────────────
    frameReady              = pyqtSignal(str, object)   # (camera_id, QImage)
    streamStarted           = pyqtSignal(str)            # camera_id
    streamStopped           = pyqtSignal(str)            # camera_id
    streamError             = pyqtSignal(str, str)       # (camera_id, error_msg)
    activeCameraChanged     = pyqtSignal(str)            # camera_id
    connectionStatusChanged = pyqtSignal(str, str)       # (camera_id, status_text)
    streamReconnecting      = pyqtSignal(str, int)       # (camera_id, seconds)

    # ── Construction ──────────────────────────────────────────────────────────

    def __init__(self, parent: QObject = None):
        super().__init__(parent)
        self._factory        = GStreamerPipelineFactory()
        self._workers        = {}   # {camera_id: VideoWorkerThread}
        self._urls           = {}   # {camera_id: rtsp_url}
        self._active_cam_id  = ""

        print("[VideoStreamManager] ✅ Initialized (GStreamer edition)")
        print(f"[VideoStreamManager]   Hardware profile: {self._factory.profile}")

    # ── Qt Properties ─────────────────────────────────────────────────────────

    @pyqtProperty(str, notify=activeCameraChanged)
    def activeCameraId(self) -> str:
        return self._active_cam_id

    @pyqtProperty(str, notify=activeCameraChanged)
    def hardwareProfile(self) -> str:
        return self._factory.profile

    # ── Public Slots ──────────────────────────────────────────────────────────

    @pyqtSlot(str, str)
    def startStream(self, camera_id: str, rtsp_url: str):
        """Start a stream for camera_id with the given RTSP URL (no auth)."""
        self._start_stream_impl(camera_id, rtsp_url, "", "")

    @pyqtSlot(str, str, str, str)
    def startStreamWithAuth(self, camera_id: str, rtsp_url: str,
                            username: str, password: str):
        """Start a stream with RTSP credentials."""
        self._start_stream_impl(camera_id, rtsp_url, username, password)

    @pyqtSlot(str)
    def stopStream(self, camera_id: str):
        """Stop the stream for a specific camera_id."""
        if camera_id not in self._workers:
            logger.warning(f"[VideoStreamManager] stopStream: unknown id '{camera_id}'")
            return

        logger.info(f"[VideoStreamManager] Stopping stream: {camera_id}")
        worker = self._workers.pop(camera_id)
        self._urls.pop(camera_id, None)
        worker.stop()
        worker.wait(5000)
        worker.deleteLater()

        self.streamStopped.emit(camera_id)
        self.connectionStatusChanged.emit(camera_id, "Disconnected")
        print(f"[VideoStreamManager] ⬛ Stopped: {camera_id}")

        if self._active_cam_id == camera_id:
            self._active_cam_id = next(iter(self._workers), "")
            self.activeCameraChanged.emit(self._active_cam_id)

    @pyqtSlot()
    def stopAllStreams(self):
        """Stop all active streams (e.g., on application shutdown)."""
        ids = list(self._workers.keys())
        for camera_id in ids:
            self.stopStream(camera_id)
        print("[VideoStreamManager] ⬛ All streams stopped")

    @pyqtSlot(str)
    def switchActiveCamera(self, camera_id: str):
        """
        Change which camera's frames are forwarded to QML.
        All workers keep running; only 'active' frames are forwarded.
        """
        if camera_id not in self._workers and camera_id:
            logger.warning(f"[VideoStreamManager] switchActiveCamera: '{camera_id}' not running")
            return
        self._active_cam_id = camera_id
        self.activeCameraChanged.emit(camera_id)
        self.connectionStatusChanged.emit(camera_id, f"Active camera: {camera_id}")
        print(f"[VideoStreamManager] 📷 Switched active camera → {camera_id}")

    @pyqtSlot(result=int)
    def activeStreamCount(self) -> int:
        return len(self._workers)

    @pyqtSlot(str, result=bool)
    def isStreaming(self, camera_id: str) -> bool:
        return camera_id in self._workers

    # ── Cleanup ───────────────────────────────────────────────────────────────

    def cleanup(self):
        """Release all resources. Safe to call multiple times."""
        print("[VideoStreamManager] 🧹 Cleaning up...")
        self.stopAllStreams()
        print("[VideoStreamManager] ✅ Cleanup complete")

    # ── Internal ──────────────────────────────────────────────────────────────

    def _start_stream_impl(
        self, camera_id: str, rtsp_url: str,
        username: str, password: str
    ):
        """Internal: build pipeline, create worker, wire signals."""
        rtsp_url = rtsp_url.strip()
        if not rtsp_url:
            self.streamError.emit(camera_id, "RTSP URL cannot be empty")
            return

        # Stop existing stream for this camera if running
        if camera_id in self._workers:
            logger.info(f"[VideoStreamManager] Replacing existing stream: {camera_id}")
            self.stopStream(camera_id)

        # Enforce parallel stream limit
        if len(self._workers) >= MAX_PARALLEL_STREAMS:
            oldest = next(iter(self._workers))
            logger.warning(f"[VideoStreamManager] Stream limit reached — dropping: {oldest}")
            self.stopStream(oldest)

        # Build hardware-appropriate pipeline
        pipeline_str = self._factory.build_pipeline(rtsp_url, username, password)

        # Lazy import — keeps GStreamer DLLs out of the process until needed
        from modules.VideoWorkerThread import VideoWorkerThread  # noqa: PLC0415
        worker = VideoWorkerThread(pipeline_str, parent=None)

        # Capture camera_id in closures for signal forwarding
        def _on_frame(img, cid=camera_id):
            self.frameReady.emit(cid, img)

        def _on_started(cid=camera_id):
            self.streamStarted.emit(cid)
            self.connectionStatusChanged.emit(cid, "Connected")
            print(f"[VideoStreamManager] ✅ Stream live: {cid}")

        def _on_stopped(cid=camera_id):
            # Worker finished — remove from registry if still there
            self._workers.pop(cid, None)
            self._urls.pop(cid, None)
            self.streamStopped.emit(cid)
            self.connectionStatusChanged.emit(cid, "Disconnected")

        def _on_error(msg, cid=camera_id):
            self.streamError.emit(cid, msg)
            self.connectionStatusChanged.emit(cid, f"Error: {msg}")

        def _on_status(status, cid=camera_id):
            self.connectionStatusChanged.emit(cid, status)

        def _on_reconnecting(secs, cid=camera_id):
            self.streamReconnecting.emit(cid, secs)

        worker.frameReady.connect(_on_frame)
        worker.streamStarted.connect(_on_started)
        worker.streamStopped.connect(_on_stopped)
        worker.streamError.connect(_on_error)
        worker.statusChanged.connect(_on_status)
        worker.reconnecting.connect(_on_reconnecting)

        self._workers[camera_id] = worker
        self._urls[camera_id]    = rtsp_url

        # Make first camera the active one automatically
        if not self._active_cam_id:
            self._active_cam_id = camera_id
            self.activeCameraChanged.emit(camera_id)

        worker.start()
        self.connectionStatusChanged.emit(camera_id, "Connecting…")
        print(f"[VideoStreamManager] ▶️ Stream started: {camera_id} → {rtsp_url}")

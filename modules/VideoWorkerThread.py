"""
modules/VideoWorkerThread.py
=============================
TiHAN GCS — Dedicated GStreamer Video Worker Thread
Version: 1.0.0

Runs a GStreamer pipeline in a dedicated QThread.
Decodes RTSP frames and emits them as QImage via Qt signals
for zero-latency display in QML without blocking the UI thread.

Key design decisions:
  • QThread wraps gi.repository (GLib mainloop) — strict thread isolation
  • Auto-reconnect with configurable interval
  • Max 2 frame buffers, old frames dropped (meets latency target <200ms)
  • All logging goes through Python logging + print for console visibility
"""

import time
import logging
import traceback
from PyQt5.QtCore import QThread, pyqtSignal, QTimer

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# GStreamer import guard — GStreamer may not be installed on all dev machines
# ──────────────────────────────────────────────────────────────────────────────

try:
    import gi
    gi.require_version("Gst", "1.0")
    from gi.repository import Gst, GLib
    Gst.init(None)
    GSTREAMER_AVAILABLE = True
except Exception as _gst_err:
    GSTREAMER_AVAILABLE = False
    print(f"[VideoWorkerThread] ⚠️ GStreamer not available: {_gst_err}")
    print("[VideoWorkerThread]   VideoWorkerThread will run in stub mode only.")


# ──────────────────────────────────────────────────────────────────────────────
# Helper: convert GStreamer buffer to QImage
# ──────────────────────────────────────────────────────────────────────────────

def _gst_sample_to_qimage(sample):
    """
    Convert a GStreamer sample (BGR format) to a QImage.
    Returns None on failure.
    """
    try:
        from PyQt5.QtGui import QImage

        buf  = sample.get_buffer()
        caps = sample.get_caps()

        if not buf or not caps:
            return None

        struct  = caps.get_structure(0)
        width   = struct.get_value("width")
        height  = struct.get_value("height")
        fmt     = struct.get_string("format")

        # Map GStreamer buffer into Python bytes
        success, map_info = buf.map(Gst.MapFlags.READ)
        if not success:
            return None

        try:
            data  = bytes(map_info.data)
            # GStreamer outputs BGR; QImage(Format_BGR888) available Qt 5.14+
            try:
                img = QImage(data, width, height, width * 3, QImage.Format_BGR888)
            except AttributeError:
                # Fallback for Qt < 5.14 — convert BGR → RGB
                import struct as _struct
                rgb = bytearray(len(data))
                for i in range(0, len(data), 3):
                    rgb[i]   = data[i + 2]
                    rgb[i+1] = data[i + 1]
                    rgb[i+2] = data[i]
                img = QImage(bytes(rgb), width, height, width * 3, QImage.Format_RGB888)

            return img.copy()   # .copy() detaches from the raw buffer memory
        finally:
            buf.unmap(map_info)

    except Exception as exc:
        logger.warning(f"[VideoWorkerThread] _gst_sample_to_qimage error: {exc}")
        return None


# ──────────────────────────────────────────────────────────────────────────────
# VideoWorkerThread
# ──────────────────────────────────────────────────────────────────────────────

class VideoWorkerThread(QThread):
    """
    Dedicated QThread that owns and manages a GStreamer pipeline.

    Signals
    -------
    frameReady(QImage)          — emitted for each decoded frame
    streamStarted()             — pipeline entered PLAYING state successfully
    streamStopped()             — pipeline fully stopped
    streamError(str)            — pipeline error; auto-reconnect will follow
    reconnecting(int)           — emitted with countdown (seconds) before retry
    statusChanged(str)          — human-readable status update

    Design note: We do NOT use GLib.MainLoop() inside this QThread.
    Running a GLib event loop inside a QThread conflicts with PyQt5's signal
    dispatch on Windows — exceptions in GLib-dispatched callbacks propagate
    as 'Unhandled Python exception', killing the process.
    Instead we poll the GStreamer bus with bus.timed_pop_filtered() directly
    from the QThread loop.  appsink new-sample callbacks are unaffected (they
    fire from GStreamer's own internal streaming thread, no GLib loop needed).
    """

    frameReady     = pyqtSignal(object)   # QImage — use object to avoid import issues
    streamStarted  = pyqtSignal()
    streamStopped  = pyqtSignal()
    streamError    = pyqtSignal(str)
    reconnecting   = pyqtSignal(int)
    statusChanged  = pyqtSignal(str)

    # Auto-reconnect interval (ms)
    RECONNECT_INTERVAL_MS = 2000
    # Maximum reconnect wait shown in countdown
    RECONNECT_COUNTDOWN_S = 2
    # Bus poll timeout (ms) — how often we check for bus messages and stop signals
    BUS_POLL_MS = 100

    def __init__(
        self,
        pipeline_str: str,
        parent=None
    ):
        super().__init__(parent)
        self._pipeline_str   = pipeline_str
        self._pipeline       = None
        self._bus            = None
        self._running        = False
        self._user_stopped   = False
        self._connected      = False

    # ── Public interface (safe to call from main thread) ──────────────────────

    def stop(self):
        """Request graceful shutdown. Returns immediately."""
        logger.info("[VideoWorkerThread] stop() requested")
        self._user_stopped = True
        self._running      = False

    # ── QThread entry point ───────────────────────────────────────────────────

    def run(self):
        """Thread body — runs until stop() is called or fatal error occurs."""
        logger.info("[VideoWorkerThread] Thread started")
        self._user_stopped = False
        self._running      = True

        if not GSTREAMER_AVAILABLE:
            self.streamError.emit("GStreamer not installed — cannot render video")
            self.statusChanged.emit("⚠️ GStreamer not available")
            return

        while self._running and not self._user_stopped:
            try:
                self._start_pipeline()
                self._poll_bus()            # blocks until error/EOS/stop
            except Exception as exc:
                err_msg = f"Pipeline exception: {exc}"
                logger.error(f"[VideoWorkerThread] {err_msg}")
                traceback.print_exc()
                self.streamError.emit(err_msg)
                self.statusChanged.emit(f"❌ {err_msg}")
            finally:
                self._stop_pipeline()

            # Auto-reconnect unless user requested stop
            if self._running and not self._user_stopped:
                self._do_reconnect_countdown()

        self.streamStopped.emit()
        self.statusChanged.emit("⬛ Stream stopped")
        logger.info("[VideoWorkerThread] Thread exited gracefully")

    # ── Pipeline lifecycle ────────────────────────────────────────────────────

    def _start_pipeline(self):
        """Parse and start the GStreamer pipeline."""
        logger.info(f"[VideoWorkerThread] Starting pipeline: {self._pipeline_str}")
        self.statusChanged.emit("🔄 Connecting...")

        self._pipeline = Gst.parse_launch(self._pipeline_str)

        # Get the appsink element
        appsink = self._pipeline.get_by_name("sink")
        if appsink is None:
            raise RuntimeError("appsink element 'sink' not found in pipeline")

        appsink.set_property("emit-signals", True)
        appsink.set_property("sync", False)
        appsink.set_property("drop", True)
        appsink.set_property("max-buffers", 2)
        appsink.connect("new-sample", self._on_new_sample)

        # Get pipeline bus — we poll it manually (no GLib.MainLoop needed)
        self._bus = self._pipeline.get_bus()

        ret = self._pipeline.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("Failed to set pipeline to PLAYING")

        print("[VideoWorkerThread] ▶️ Pipeline PLAYING")

    def _poll_bus(self):
        """
        Poll the GStreamer bus for messages.

        Replaces GLib.MainLoop() — runs directly in the QThread body with no
        GLib dispatcher involved.  Exits when an error/EOS is received or
        self._running becomes False.
        """
        poll_ns = self.BUS_POLL_MS * Gst.MSECOND

        while self._running and not self._user_stopped:
            msg = self._bus.timed_pop_filtered(
                poll_ns,
                Gst.MessageType.ERROR
                | Gst.MessageType.EOS
                | Gst.MessageType.STATE_CHANGED
            )
            if msg is None:
                continue    # timeout — check _running and loop again

            mtype = msg.type
            if mtype == Gst.MessageType.ERROR:
                err, debug = msg.parse_error()
                error_text = f"{err.message} ({debug})"
                logger.error(f"[VideoWorkerThread] Bus ERROR: {error_text}")
                print(f"[VideoWorkerThread] ❌ Error: {error_text}")
                self.streamError.emit(error_text)
                self.statusChanged.emit(f"❌ Stream error: {err.message}")
                self._connected = False
                return      # exit poll loop → reconnect

            elif mtype == Gst.MessageType.EOS:
                logger.info("[VideoWorkerThread] EOS received")
                self.streamError.emit("Stream ended (EOS)")
                self.statusChanged.emit("⚠️ Stream ended")
                self._connected = False
                return      # exit poll loop → reconnect

            elif mtype == Gst.MessageType.STATE_CHANGED:
                if msg.src == self._pipeline:
                    _, new_state, _ = msg.parse_state_changed()
                    if new_state == Gst.State.PLAYING and not self._connected:
                        self._connected = True
                        logger.info("[VideoWorkerThread] Stream LIVE")
                        print("[VideoWorkerThread] ✅ Stream connected and playing")
                        self.streamStarted.emit()
                        self.statusChanged.emit("✅ Stream live")

    def _stop_pipeline(self):
        """Gracefully tear down the pipeline."""
        if self._pipeline:
            try:
                self._pipeline.set_state(Gst.State.NULL)
                logger.info("[VideoWorkerThread] Pipeline set to NULL")
            except Exception as exc:
                logger.warning(f"[VideoWorkerThread] stop_pipeline error: {exc}")
            self._pipeline = None

        self._bus       = None
        self._connected = False

    # ── GStreamer appsink callback (GStreamer internal thread) ────────────────

    def _on_new_sample(self, appsink):
        """Called by appsink for every decoded frame (GStreamer streaming thread)."""
        try:
            sample = appsink.emit("pull-sample")
            if sample is None:
                return Gst.FlowReturn.ERROR

            img = _gst_sample_to_qimage(sample)
            if img is not None:
                self.frameReady.emit(img)

        except Exception as exc:
            logger.warning(f"[VideoWorkerThread] Frame callback error: {exc}")

        return Gst.FlowReturn.OK

    # ── Reconnect countdown ───────────────────────────────────────────────────

    def _do_reconnect_countdown(self):
        """Sleep for RECONNECT_INTERVAL_MS while emitting countdown ticks."""
        secs = max(1, self.RECONNECT_INTERVAL_MS // 1000)
        for remaining in range(secs, 0, -1):
            if self._user_stopped:
                return
            self.reconnecting.emit(remaining)
            self.statusChanged.emit(f"🔄 Reconnecting in {remaining}s…")
            time.sleep(1.0)

        if not self._user_stopped:
            self.statusChanged.emit("🔄 Reconnecting…")
            logger.info("[VideoWorkerThread] Retrying pipeline...")




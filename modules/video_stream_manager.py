"""
modules/video_stream_manager.py
================================
TiHAN GCS — Professional RTSP Video Stream Manager
Version: 1.0.1
"""

from PyQt5.QtCore import (
    QObject,
    QTimer,
    pyqtSignal,
    pyqtSlot,
    pyqtProperty,
    Qt,
)
from PyQt5.QtMultimedia import (
    QMediaPlayer,
    QMediaContent,
)
from PyQt5.QtCore import QUrl


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_RETRY_INTERVAL_MS = 3000
_BUFFER_PROGRESS_THRESHOLD = 100


# ---------------------------------------------------------------------------
# VideoStreamManager
# ---------------------------------------------------------------------------

class VideoStreamManager(QObject):
    """
    Non-blocking RTSP stream manager backed by QMediaPlayer.

    Lifecycle
    ---------
    setStreamUrl(url)  →  startStream()
                              │
                        QMediaPlayer.play()
                              │
                    ┌─────────┴──────────┐
               buffered?            error?
                    │                    │
               "Connected"          "Error"
             streamStarted()      streamError()
                                       │
                                  retry timer
                                  (3 s loop)
                                       │
                               stopStream() breaks loop
    """

    # ------------------------------------------------------------------ #
    #  Signals                                                             #
    # ------------------------------------------------------------------ #

    streamStarted           = pyqtSignal()
    streamStopped           = pyqtSignal()
    streamError             = pyqtSignal(str)
    connectionStatusChanged = pyqtSignal(str)
    playerChanged           = pyqtSignal()   # emitted so QML can refresh source

    # ------------------------------------------------------------------ #
    #  Construction / destruction                                          #
    # ------------------------------------------------------------------ #

    def __init__(self, parent: QObject = None):
        super().__init__(parent)

        self._stream_url: str = ""
        self._is_streaming: bool = False
        self._connection_status: str = "Disconnected"
        self._user_stopped: bool = False

        # QMediaPlayer — created once; reused across connect/disconnect cycles
        self._player = QMediaPlayer(self, QMediaPlayer.StreamPlayback)
        self._player.setVolume(0)

        # Retry timer
        self._retry_timer = QTimer(self)
        self._retry_timer.setSingleShot(True)
        self._retry_timer.setInterval(_RETRY_INTERVAL_MS)
        self._retry_timer.timeout.connect(self._on_retry_timeout)

        # Wire QMediaPlayer signals
        self._player.stateChanged.connect(self._on_player_state_changed)
        self._player.mediaStatusChanged.connect(self._on_media_status_changed)
        self._player.error.connect(self._on_player_error)

        print("[VideoStreamManager] Initialised — waiting for RTSP URL")

    # ------------------------------------------------------------------ #
    #  Qt Properties (readable from QML)                                   #
    # ------------------------------------------------------------------ #

    @pyqtProperty(bool, notify=connectionStatusChanged)
    def isStreaming(self) -> bool:
        return self._is_streaming

    @pyqtProperty(str, notify=connectionStatusChanged)
    def connectionStatus(self) -> str:
        return self._connection_status

    @pyqtProperty(QObject, notify=playerChanged)
    def player(self) -> QMediaPlayer:
        """
        Expose QMediaPlayer as a QML-readable property so VideoOutput can bind:

            VideoOutput { source: videoManager.player }

        This is the recommended approach — QML properties are always accessible,
        unlike Python methods which require @pyqtSlot to be callable from QML.
        """
        return self._player

    # ------------------------------------------------------------------ #
    #  Public slots (callable from QML)                                    #
    # ------------------------------------------------------------------ #

    @pyqtSlot(str)
    def setStreamUrl(self, url: str):
        """Store the RTSP URL. Does NOT start playback — call startStream() next."""
        url = url.strip()
        if not url:
            print("[VideoStreamManager] setStreamUrl: empty URL ignored")
            return
        self._stream_url = url
        print(f"[VideoStreamManager] Stream URL set → {url}")

    @pyqtSlot()
    def startStream(self):
        """Begin RTSP playback. Transitions: current state → Connecting → Connected (or Error)."""
        if not self._stream_url:
            msg = "No RTSP URL configured — call setStreamUrl() first"
            print(f"[VideoStreamManager] startStream: {msg}")
            self._set_status("Error")
            self.streamError.emit(msg)
            return

        self._user_stopped = False
        self._retry_timer.stop()

        print(f"[VideoStreamManager] Starting stream → {self._stream_url}")
        self._set_status("Connecting")

        media = QMediaContent(QUrl(self._stream_url))
        self._player.setMedia(media)
        self._player.play()

    @pyqtSlot()
    def stopStream(self):
        """Stop playback and cancel any pending reconnect attempts. Emits streamStopped."""
        print("[VideoStreamManager] stopStream() called — halting playback")

        self._user_stopped = True
        self._retry_timer.stop()
        self._player.stop()
        self._player.setMedia(QMediaContent())

        self._is_streaming = False
        self._set_status("Disconnected")
        self.streamStopped.emit()

    # ------------------------------------------------------------------ #
    #  Public helpers                                                       #
    # ------------------------------------------------------------------ #

    @pyqtSlot(result=QObject)
    def getPlayer(self) -> QMediaPlayer:
        """
        Return the underlying QMediaPlayer as a pyqtSlot so QML can call it.

        PREFERRED: use the `player` property instead — it is always accessible
        from QML without a function call:

            VideoOutput { source: videoManager.player }

        This slot is kept for backwards compatibility only.
        """
        return self._player

    def cleanup(self):
        """Release all resources. Called from ApplicationManager.cleanup_all()."""
        print("[VideoStreamManager] cleanup() — releasing resources")
        self._retry_timer.stop()
        self._player.stop()
        self._player.setMedia(QMediaContent())
        self._player.deleteLater()

    # ------------------------------------------------------------------ #
    #  Internal — QMediaPlayer signal handlers                             #
    # ------------------------------------------------------------------ #

    def _on_player_state_changed(self, state: QMediaPlayer.State):
        state_names = {
            QMediaPlayer.StoppedState: "Stopped",
            QMediaPlayer.PlayingState: "Playing",
            QMediaPlayer.PausedState:  "Paused",
        }
        print(f"[VideoStreamManager] Player state → {state_names.get(state, state)}")

    def _on_media_status_changed(self, status: QMediaPlayer.MediaStatus):
        status_names = {
            QMediaPlayer.UnknownMediaStatus: "Unknown",
            QMediaPlayer.NoMedia:            "NoMedia",
            QMediaPlayer.LoadingMedia:       "Loading",
            QMediaPlayer.LoadedMedia:        "Loaded",
            QMediaPlayer.StalledMedia:       "Stalled",
            QMediaPlayer.BufferingMedia:     "Buffering",
            QMediaPlayer.BufferedMedia:      "Buffered",
            QMediaPlayer.EndOfMedia:         "EndOfMedia",
            QMediaPlayer.InvalidMedia:       "InvalidMedia",
        }
        print(f"[VideoStreamManager] Media status → {status_names.get(status, status)}")

        if status == QMediaPlayer.BufferedMedia:
            # Fully buffered — stream is live and stable
            self._is_streaming = True
            self._set_status("Connected")
            self.streamStarted.emit()

        elif status == QMediaPlayer.BufferingMedia:
            # Data is flowing; frames are arriving — show the feed immediately.
            # VideoOutput renders frames as soon as Qt decodes the first one,
            # so we set Connected here too rather than waiting for full buffer.
            if not self._is_streaming:
                self._is_streaming = True
                self._set_status("Connected")
                self.streamStarted.emit()

        elif status in (QMediaPlayer.StalledMedia, QMediaPlayer.EndOfMedia):
            if not self._user_stopped:
                self._on_error("Stream stalled or ended unexpectedly")

        elif status == QMediaPlayer.InvalidMedia:
            self._on_error("Invalid or unreachable media source")

    def _on_player_error(self, error: QMediaPlayer.Error):
        error_string = self._player.errorString() or f"QMediaPlayer error code {error}"
        print(f"[VideoStreamManager] Player error → {error_string}")
        if error != QMediaPlayer.NoError:
            self._on_error(error_string)

    # ------------------------------------------------------------------ #
    #  Internal — error handling and retry logic                           #
    # ------------------------------------------------------------------ #

    def _on_error(self, message: str):
        self._is_streaming = False
        self._set_status("Error")
        self.streamError.emit(message)
        print(f"[VideoStreamManager] Error: {message}")

        if not self._user_stopped and self._stream_url:
            print(f"[VideoStreamManager] Scheduling reconnect in {_RETRY_INTERVAL_MS} ms …")
            self._retry_timer.start()

    def _on_retry_timeout(self):
        if self._user_stopped:
            print("[VideoStreamManager] Retry cancelled — stream was stopped by user")
            return
        print("[VideoStreamManager] Retrying connection …")
        self.startStream()

    # ------------------------------------------------------------------ #
    #  Internal — status management                                         #
    # ------------------------------------------------------------------ #

    def _set_status(self, status: str):
        if self._connection_status != status:
            self._connection_status = status
            self.connectionStatusChanged.emit(status)
            print(f"[VideoStreamManager] Status → {status}")
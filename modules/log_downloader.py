"""
Log Downloader Module
Professional log downloader with sliding window burst requests.
Downloads onboard DataFlash logs from flight controller via MAVLink protocol.
"""

import os
import time
import struct
import math
import sys
import threading
from collections import deque
from pathlib import Path
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, QTimer
from pymavlink import mavutil


class _StreamFilter:
    """
    Thread-safe wrapper for sys.stdout / sys.stderr that silently drops
    lines containing 'bad header' (pymavlink prints these directly via
    print(..., file=sys.stderr) - Python logging cannot intercept them).
    """
    def __init__(self, stream):
        self._stream = stream
        self._lock = threading.Lock()
        self._buf = ''

    def write(self, text):
        with self._lock:
            self._buf += text
            while '\n' in self._buf:
                line, self._buf = self._buf.split('\n', 1)
                if 'bad header' not in line.lower():
                    try:
                        self._stream.write(line + '\n')
                        self._stream.flush()
                    except Exception:
                        pass  # never crash on log write

    def flush(self):
        with self._lock:
            if self._buf:
                if 'bad header' not in self._buf.lower():
                    try:
                        self._stream.write(self._buf)
                    except Exception:
                        pass
                self._buf = ''
            try:
                self._stream.flush()
            except Exception:
                pass

    def __getattr__(self, name):
        return getattr(self._stream, name)


# _StreamFilter is now installed in LogDownloader.__init__



class LogDownloader(QObject):
    """Professional log downloader with sliding window burst requests"""
    
    logListReceived = pyqtSignal(list)  # List of {id, size, date, num_logs}
    downloadProgress = pyqtSignal(int, int, int)  # log_id, bytes_downloaded, total_bytes
    downloadComplete = pyqtSignal(int, str)  # log_id, file_path
    downloadError = pyqtSignal(str)
    logDownloadMessage = pyqtSignal(str)  # Message for UI console
    downloadSpeed = pyqtSignal(float)  # Current speed in KB/s
    logsCleared = pyqtSignal()  # Emitted when drone confirms all logs erased
    
    # Internal cross-thread routing signal
    _mavlinkMsgSignal = pyqtSignal(object)
    
    # Constants
    CHUNK_SIZE = 90  # MAVLink LOG_DATA payload size
    MAX_RETRIES = 20
    
    # Link-adaptive parameters
    # ArduPilot log server handles 80-100+ concurrent requests over USB/UDP.
    # Larger windows saturate the pipeline and dramatically reduce download time
    # for large logs; the FC's TX queue is the real bottleneck, not the window.
    LINK_PARAMS = {
        'usb':    {'window_size': 100, 'timeout_ms': 150},
        'wifi':   {'window_size':  60, 'timeout_ms': 300},
        'radio':  {'window_size':  15, 'timeout_ms': 800},
        'default':{'window_size':  50, 'timeout_ms': 400},
    }

    # Emit downloadProgress at most every N chunks to avoid flooding the QML
    # paint loop. 100 chunks ≈ 9 KB per UI update — still silky-smooth at scale.
    _PROGRESS_THROTTLE_CHUNKS = 100
    
    def __init__(self, drone_model):
        super().__init__()
        self._drone_model = drone_model
        self._drone = None
        
        # Professional sliding window state
        self._downloading = False
        self._current_log_id = None
        self._expected_size = 0
        self._total_chunks = 0
        
        # Bitmap tracking (precise chunk-level completion)
        self._received = []  # [False] * total_chunks
        self._received_count = 0  # O(1) completion check, avoids all() scan
        
        # In-flight tracking with timestamps
        self._in_flight = {}  # {chunk_index: timestamp}
        self._retry_counts = {}  # {chunk_index: count}
        
        # Forward progress pointer
        self._next_chunk_to_request = 0
        
        # Adaptive parameters
        self._window_size = 20
        self._timeout_ms = 600
        
        # Speed calculation (1s sliding window) — deque for O(1) popleft
        self._bytes_received_total = 0
        self._last_speed_update = 0
        self._speed_samples = deque()  # deque of (timestamp, bytes_received)

        # Progress signal throttle counter
        self._progress_chunk_counter = 0

        # Console progress bar — last render timestamp (render at most every 0.25 s)
        self._last_bar_print = 0.0
        
        # Global stall detection
        self._last_progress_time = 0
        self._global_stall_timeout = 10.0  # seconds
        
        # File handle for random-access writing
        self._file_handle = None
        self._file_path = None
        
        # Queue state
        self._download_queue = []
        
        # Retransmission timer (100ms)
        self._retransmit_timer = QTimer()
        self._retransmit_timer.timeout.connect(self._check_timeouts)
        
        # Storage
        docs = Path.home() / "Documents" / "TihanFly" / "Logs" / "downloaded"
        self.download_directory = docs
        self.download_directory.mkdir(parents=True, exist_ok=True)
        
        # Install stream filter HERE (inside __init__, not at module level)
        self._install_stream_filter()
        
        # Connect internal signal for thread safety
        self._mavlinkMsgSignal.connect(self._process_mavlink_message_gui)
    
    @staticmethod
    def _install_stream_filter():
        """Suppress pymavlink 'bad header' noise from stderr."""
        if not isinstance(sys.stdout, _StreamFilter):
            sys.stdout = _StreamFilter(sys.stdout)
        if not isinstance(sys.stderr, _StreamFilter):
            sys.stderr = _StreamFilter(sys.stderr)

    @pyqtSlot()
    def requestLogList(self):
        """Request list of onboard logs from flight controller"""
        if not self._drone_model or not self._drone_model.isConnected:
            print("[LogDownloader] ❌ Not connected to drone")
            self.downloadError.emit("Not connected to drone")
            return
        
        self._drone = self._drone_model.drone_connection
        if not self._drone:
            print("[LogDownloader] ❌ No drone connection")
            self.downloadError.emit("No drone connection")
            return
        
        # NOTE: MAVLink message routing is handled via register_msg_callback()
        # in main.py's _wire_mavlink_callbacks_on_connect(). No need to
        # connect/disconnect mavlinkMessageReceived here.
        
        try:
            # Send LOG_REQUEST_LIST
            self._drone.mav.log_request_list_send(
                self._drone.target_system,
                self._drone.target_component,
                0,      # start
                0xFFFF  # end (all logs)
            )
            print("[LogDownloader] 📤 Requested log list")
            
            # Initialize log list collection
            self._log_list = []
            
        except Exception as e:
            print(f"[LogDownloader] ❌ Failed to request log list: {e}")
            self.downloadError.emit(f"Failed to request log list: {e}")
    
    def _process_mavlink_message(self, msg):
        """Called by MAVLinkThread (background). Bounces to GUI thread."""
        self._mavlinkMsgSignal.emit(msg)
        
    def _process_mavlink_message_gui(self, msg):
        """Process incoming MAVLink messages for log-related data safely on GUI thread"""
        try:
            msg_type = msg.get_type()
            
            if msg_type == 'LOG_ENTRY':
                self._handle_log_entry(msg)
            elif msg_type == 'LOG_DATA':
                self._handle_log_data(msg)
            elif msg_type == 'LOG_REQUEST_END':
                self._handle_log_request_end(msg)
            elif msg_type == 'LOG_ERASE':
                # Some firmwares echo back LOG_ERASE as acknowledgment
                print("[LogDownloader] ✅ LOG_ERASE acknowledged by drone")
                self.logDownloadMessage.emit("✅ All logs erased from drone SD card.")
                self.logsCleared.emit()
                
        except Exception as e:
            print(f"[LogDownloader] ⚠️ Error processing message: {e}")
    
    def _handle_log_entry(self, msg):
        """Handle LOG_ENTRY message"""
        print(f"[LogDownloader] 📥 LOG_ENTRY received: ID={msg.id}, Size={msg.size} bytes, NumLogs={msg.num_logs}")
        
        log_info = {
            'id': msg.id,
            'num_logs': msg.num_logs,
            'last_log_num': msg.last_log_num,
            'time_utc': msg.time_utc,
            'size': msg.size
        }
        
        # Initialize log list if needed
        if not hasattr(self, '_log_list'):
            self._log_list = []
        
        # Add to list if valid log
        if msg.id > 0:
            self._log_list.append(log_info)
            print(f"[LogDownloader]   Added log {msg.id} to list ({len(self._log_list)}/{msg.num_logs})")
        
        # Emit complete list when all logs received
        if len(self._log_list) >= msg.num_logs and msg.num_logs > 0:
            print(f"[LogDownloader] ✅ Received all {len(self._log_list)} logs, emitting list")
            self.logListReceived.emit(self._log_list)
        elif msg.num_logs == 0:
            print("[LogDownloader] ⚠️ No logs available on flight controller")
            self.logListReceived.emit([])
            self.logDownloadMessage.emit("No logs found on flight controller")

    @pyqtSlot(list)
    def downloadLogs(self, log_ids):
        """
        Download multiple logs
        Args:
            log_ids: List of log IDs to download
        """
        count = len(log_ids)
        if count == 0:
            return
            
        self.logDownloadMessage.emit(f"Queued {count} logs for download")
        
        # Add to queue
        for log_id in log_ids:
            if log_id not in self._download_queue:
                self._download_queue.append(log_id)
        
        # Start if not downloading
        if not self._downloading:
            self._process_download_queue()

    def _process_download_queue(self):
        """Process next log in queue"""
        if not self._download_queue:
            self.logDownloadMessage.emit("All downloads complete")
            return
            
        next_id = self._download_queue.pop(0)
        self.downloadLog(next_id)
    
    @pyqtSlot(int)
    def downloadLog(self, log_id):
        """
        Download specific log using professional sliding window burst requests
        
        Args:
            log_id: Log ID to download
        """
        log_id = int(log_id)
        if self._downloading:
            self.downloadError.emit("Download already in progress")
            return
        
        if not self._drone:
            self.downloadError.emit("Not connected to drone")
            return
        
        # Get expected size
        self._expected_size = 0
        if hasattr(self, '_log_list'):
            for log in self._log_list:
                if log['id'] == log_id:
                    self._expected_size = log['size']
                    break
        
        if self._expected_size == 0:
            self.downloadError.emit("Unknown log size")
            return
        
        # Initialize professional state
        self._downloading = True
        self._current_log_id = log_id
        self._total_chunks = math.ceil(self._expected_size / self.CHUNK_SIZE)
        
        # Reset bitmap and tracking
        self._received = [False] * self._total_chunks
        self._received_count = 0
        self._total_retries = 0  # Global retry counter for progress bar
        
        # Detect link type and set adaptive parameters
        link_type = self._detect_link_type()
        params = self.LINK_PARAMS.get(link_type, self.LINK_PARAMS['default'])
        self._timeout_ms = params['timeout_ms']
        
        # Speed tracking
        self._bytes_received_total = 0
        self._speed_samples = deque()
        self._progress_chunk_counter = 0
        self._last_progress_time = time.time()
        self._last_speed_update = time.time()
        
        # Pre-allocate file for random-access writing.
        # FAST PATH: truncate() is an OS-level sparse allocation — near-instant
        # even for 500 MB logs. The old approach (write b'\x00' * size) blocked
        # for seconds because it physically wrote every byte before download began.
        try:
            filename = f"log_{self._current_log_id:03d}.bin"
            self._file_path = self.download_directory / filename

            with open(self._file_path, 'wb') as f:
                f.truncate(self._expected_size)  # sparse allocation — O(1)

            # Reopen in r+b mode for random access
            self._file_handle = open(self._file_path, 'r+b')
            
        except Exception as e:
            self.downloadError.emit(f"Failed to create file: {e}")
            self._downloading = False
            return
        
        self.logDownloadMessage.emit(
            f"Starting download of log #{log_id} ({self._expected_size} bytes, "
            f"{self._total_chunks} chunks, bulk stream mode)"
        )
        print(f"[LogDownloader] Bulk stream download started: {self._total_chunks} chunks, "
              f"timeout={self._timeout_ms}ms")
        
        # Emit initial progress (0%) to make progress bar visible
        self.downloadProgress.emit(self._current_log_id, 0, self._expected_size)
        
        # Start gap detection and retransmission timer
        self._retransmit_timer.start(min(200, self._timeout_ms // 2))
        
        # Initial bulk request for the entire log
        self._request_data(0, self._expected_size)
    
    def _detect_link_type(self):
        """Detect connection type. mavudp stores address in .address not .port."""
        candidates = []
        for attr in ('port', 'address', '_address', 'portname', 'device'):
            val = getattr(self._drone, attr, None)
            if val is not None:
                candidates.append(str(val).lower())
        candidates.append(type(self._drone).__name__.lower())  # 'mavudp', 'mavserial'
        combined = ' '.join(candidates)
        print(f"[LogDownloader] Link detection: {combined!r}")
        if any(k in combined for k in ('usb', 'com', 'tty', 'serial', '/dev/', 'mavserial')):
            print("[LogDownloader] Link type: USB -> window=40")
            return 'usb'
        if any(k in combined for k in ('udp', 'tcp', 'mavudp', 'mavtcp',
                                        '127.', '192.168.', '10.', '172.')):
            print("[LogDownloader] Link type: WiFi/UDP -> window=30")
            return 'wifi'
        print("[LogDownloader] Link type: default -> window=25")
        return 'default'
    
    def _request_data(self, offset, count):
        """Request a continuous block of data. The drone will stream back LOG_DATA packets."""
        try:
            # We cap count at 0xFFFFFFFF per MAVLink spec
            count = min(count, 0xFFFFFFFF)
            self._drone.mav.log_request_data_send(
                self._drone.target_system,
                self._drone.target_component,
                self._current_log_id,
                offset,
                count
            )
        except Exception as e:
            print(f"[LogDownloader] Failed to request log data (offset={offset}, count={count}): {e}")
    
    def _handle_log_data(self, msg):
        """
        Handle LOG_DATA message with professional sliding window logic
        
        Args:
            msg: LOG_DATA MAVLink message
        """
        if not self._downloading or msg.id != self._current_log_id:
            return
        
        # Validate chunk index
        offset = msg.ofs
        if offset % self.CHUNK_SIZE != 0:
            print(f"[LogDownloader] ⚠️ Malformed offset: {offset}")
            return
        
        chunk_idx = offset // self.CHUNK_SIZE
        if chunk_idx >= self._total_chunks:
            print(f"[LogDownloader] ⚠️ Chunk index out of range: {chunk_idx}")
            return
        
        # Ignore duplicates
        if self._received[chunk_idx]:
            return
        
        # Extract data — pymavlink may return list of ints; bytes() handles both
        data = bytes(msg.data[:msg.count])

        # Write to file using random access
        try:
            self._file_handle.seek(offset)
            self._file_handle.write(data)  # no per-chunk flush - OS cache handles durability
        except Exception as e:
            print(f"[LogDownloader] ❌ Failed to write chunk {chunk_idx}: {e}")
            self._abort_download(f"File write error: {e}")
            return

        # Mark as received
        self._received[chunk_idx] = True
        self._received_count += 1
        self._bytes_received_total += len(data)

        # Update progress time
        self._last_progress_time = time.time()

        # Update speed calculation
        self._update_speed()

        # Throttled progress signal: emit every _PROGRESS_THROTTLE_CHUNKS chunks.
        # Firing on every 90-byte chunk causes ~1.1 M QML repaints per 100 MB log.
        self._progress_chunk_counter += 1
        if self._progress_chunk_counter >= self._PROGRESS_THROTTLE_CHUNKS:
            self._progress_chunk_counter = 0
            received_bytes = min(self._received_count * self.CHUNK_SIZE, self._expected_size)
            self.downloadProgress.emit(
                self._current_log_id,
                received_bytes,
                self._expected_size
            )

        # Check completion — O(1) via counter, not O(n) all()
        if self._received_count >= self._total_chunks:
            self._finish_download()
    
    def _update_speed(self):
        """Update download speed using 1s sliding window (O(1) amortised via deque)."""
        now = time.time()

        # Append current sample and evict stale entries from the left — O(1) each
        self._speed_samples.append((now, self._bytes_received_total))
        while self._speed_samples and now - self._speed_samples[0][0] > 1.0:
            self._speed_samples.popleft()

        # Emit speed reading every 500 ms
        if now - self._last_speed_update >= 0.5 and len(self._speed_samples) >= 2:
            oldest = self._speed_samples[0]
            newest = self._speed_samples[-1]
            time_delta = newest[0] - oldest[0]
            bytes_delta = newest[1] - oldest[1]
            if time_delta > 0:
                speed_kbps = (bytes_delta / time_delta) / 1024.0
                self.downloadSpeed.emit(speed_kbps)
                self._last_speed_update = now
    
    def _check_timeouts(self):
        """Check for stalled data streams and request gap fillers"""
        if not self._downloading:
            return
        
        now = time.time()
        timeout_sec = self._timeout_ms / 1000.0
        
        # Global stall detection
        if now - self._last_progress_time > self._global_stall_timeout:
            self._abort_download("Download stalled (no progress for 10s)")
            return
        
        # Check if the stream stalled (no data for timeout_sec)
        if now - self._last_progress_time > timeout_sec:
            gaps_requested = 0
            i = 0
            
            while i < self._total_chunks and gaps_requested < 10:
                if not self._received[i]:
                    gap_start = i
                    gap_length = 0
                    
                    # Measure contiguous gap
                    while i < self._total_chunks and not self._received[i]:
                        gap_length += 1
                        i += 1
                        
                        # Cap single gap request to e.g. 500 chunks (45KB) to avoid 
                        # overloading during spot recovery, but large enough for speed
                        if gap_length >= 500:
                            break
                            
                    req_offset = gap_start * self.CHUNK_SIZE
                    req_count = gap_length * self.CHUNK_SIZE
                    self._request_data(req_offset, req_count)
                    
                    gaps_requested += 1
                    self._total_retries += 1
                else:
                    i += 1
                    
            if gaps_requested > 0:
                self._last_progress_time = now

        # ── Console progress bar ──────────────
        # Render at most once every 250 ms so the terminal stays readable.
        now2 = time.time()
        if self._downloading and now2 - self._last_bar_print >= 0.25:
            self._last_bar_print = now2
            self._print_console_bar()
    
    def _print_console_bar(self, done: bool = False):
        """
        Render a single-line overwriting progress bar to stdout.

            [LogDownloader] ████████████░░░░░░░░  62%  5.8 MB / 9.3 MB  ↻ 14 retries

        Uses \\r so it overwrites the previous line — zero log spam.
        Prints a newline when done=True to leave the final state visible.
        """
        pct = (self._received_count / max(self._total_chunks, 1)) * 100
        filled = int(pct / 5)          # 20-cell bar
        bar = '█' * filled + '░' * (20 - filled)

        recv_mb  = self._received_count * self.CHUNK_SIZE / 1_048_576
        total_mb = self._expected_size / 1_048_576

        retry_str = f"  ↻ {self._total_retries} retries" if self._total_retries else ""

        # Speed from last emitted value (reuse existing speed machinery)
        speed_str = ""
        if self._speed_samples and len(self._speed_samples) >= 2:
            oldest, newest = self._speed_samples[0], self._speed_samples[-1]
            dt = newest[0] - oldest[0]
            if dt > 0:
                kbps = (newest[1] - oldest[1]) / dt / 1024.0
                speed_str = f"  {kbps:.1f} KB/s"

        line = (f"\r[LogDownloader] [{bar}] {pct:5.1f}%"
                f"  {recv_mb:.2f} / {total_mb:.2f} MB"
                f"{speed_str}{retry_str}  ")

        end = "\n" if done else ""
        try:
            sys.__stdout__.write(line + end)
            sys.__stdout__.flush()
        except Exception:
            pass

    def _finish_download(self):
        """Complete the download successfully"""

        # Render final 100% bar and move to next line before any other output
        self._print_console_bar(done=True)

        print(f"[LogDownloader] ✅ Download complete for log {self._current_log_id}")

        # Stop timer
        self._retransmit_timer.stop()

        # Close file
        if self._file_handle:
            self._file_handle.close()
            self._file_handle = None

        # Guarantee the progress bar reaches 100 % regardless of throttle counter
        self.downloadProgress.emit(
            self._current_log_id,
            self._expected_size,
            self._expected_size
        )

        # Emit completion
        self.logDownloadMessage.emit(f"✅ Saved log #{self._current_log_id} to {self._file_path.name}")
        self.downloadComplete.emit(self._current_log_id, str(self._file_path))

        # Reset state
        self._downloading = False
        self._current_log_id = None

        # Process next in queue
        self._process_download_queue()
    
    def _abort_download(self, reason):
        """Abort download with error"""
        # Move cursor to new line if the progress bar was active
        if self._downloading:
            try:
                sys.__stdout__.write("\n")
                sys.__stdout__.flush()
            except Exception:
                pass

        print(f"[LogDownloader] ❌ Aborting download: {reason}")
        
        # Stop timer
        self._retransmit_timer.stop()
        
        # Close and delete partial file
        if self._file_handle:
            self._file_handle.close()
            self._file_handle = None
        
        if self._file_path and self._file_path.exists():
            try:
                self._file_path.unlink()
            except:
                pass
        
        # Emit error
        self.downloadError.emit(reason)
        
        # Reset state
        self._downloading = False
        self._current_log_id = None
    
    def _handle_log_request_end(self, msg):
        """Handle LOG_REQUEST_END message"""
        if self._downloading and msg.id == self._current_log_id:
            print(f"[LogDownloader] LOG_REQUEST_END received for log {self._current_log_id}")
    
    @pyqtSlot()
    def cancelAllDownloads(self):
        """Cancel all downloads and clear queue"""
        self._download_queue.clear()
        self.logDownloadMessage.emit("Cancelling all downloads...")
        if self._downloading:
            self.cancelDownload()
            
    @pyqtSlot(int)
    def cancelDownload(self):
        """Cancel current download"""
        if self._downloading:
            print("[LogDownloader] Download cancelled")
            self._abort_download("Cancelled by user")

    @pyqtSlot()
    def clearLogs(self):
        """Erase all DataFlash logs from the drone's SD card via MAVLink LOG_ERASE."""
        if not self._drone_model or not self._drone_model.isConnected:
            self.logDownloadMessage.emit("❌ Cannot clear logs: not connected to drone.")
            return

        self._drone = self._drone_model.drone_connection
        if not self._drone:
            self.logDownloadMessage.emit("❌ Cannot clear logs: no drone connection.")
            return

        if self._downloading:
            self.logDownloadMessage.emit("❌ Cannot clear logs while a download is in progress.")
            return

        try:
            # Send MAVLink LOG_ERASE command
            self._drone.mav.log_erase_send(
                self._drone.target_system,
                self._drone.target_component
            )
            print("[LogDownloader] 🗑️ Sent LOG_ERASE command to drone")
            self.logDownloadMessage.emit("🗑️ Erase command sent. Waiting for confirmation...")

            # Use a one-shot timer so we don't block the UI thread.
            # If the drone doesn't echo LOG_ERASE within 5 s, we treat it as success
            # (ArduPilot erases silently on most builds).
            def _on_erase_timeout():
                self.logDownloadMessage.emit("✅ Logs cleared from drone SD card (no echo received).")
                self.logsCleared.emit()

            self._erase_timer = QTimer()
            self._erase_timer.setSingleShot(True)
            self._erase_timer.timeout.connect(_on_erase_timeout)
            self._erase_timer.start(5000)  # 5 seconds

        except Exception as e:
            print(f"[LogDownloader] ❌ Failed to send LOG_ERASE: {e}")
            self.logDownloadMessage.emit(f"❌ Failed to clear logs: {e}")
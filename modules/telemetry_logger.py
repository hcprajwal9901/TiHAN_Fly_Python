"""
Telemetry Logger Module
Captures raw MAVLink bytes and writes to .tlog files with timestamp normalization.
"""

import os
import time
import queue
import gzip
from pathlib import Path
from datetime import datetime
from threading import Thread, Lock
from PyQt5.QtCore import QObject, pyqtSignal


class TelemetryLogger(QObject):
    """Real-time telemetry logger with raw MAVLink byte capture"""
    
    logStarted = pyqtSignal(str)  # Emits log file path
    logStopped = pyqtSignal()
    logError = pyqtSignal(str)
    
    def __init__(self, log_directory=None):
        super().__init__()
        
        # Storage configuration
        if log_directory is None:
            docs = Path.home() / "Documents" / "TihanFly" / "Logs"
            self.log_directory = docs
        else:
            self.log_directory = Path(log_directory)
        
        # Create directory if needed
        self.log_directory.mkdir(parents=True, exist_ok=True)
        
        # Logging state
        self._current_log_file = None
        self._log_file_path = None
        self._is_logging = False
        self._lock = Lock()
        
        # Message queue for buffered writes (10MB buffer)
        self._message_queue = queue.Queue(maxsize=10000)
        self._writer_thread = None
        
        # Timestamp normalization
        self._boot_time_offset = None
        self._previous_time_boot_ms = 0
        
        # MAVLink version detection
        self._mavlink_version = None
    
    def startLogging(self):
        """Start logging to new .tlog file"""
        if self._is_logging:
            return
        
        # Generate timestamped filename
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        filename = f"{timestamp}_Flight.tlog"
        self._log_file_path = self.log_directory / filename
        
        try:
            # Open file in binary write mode
            self._current_log_file = open(self._log_file_path, 'wb')
            self._is_logging = True
            
            # Reset state
            self._boot_time_offset = None
            self._previous_time_boot_ms = 0
            self._mavlink_version = None
            
            # Start writer thread
            self._writer_thread = Thread(target=self._write_loop, daemon=True)
            self._writer_thread.start()
            
            self.logStarted.emit(str(self._log_file_path))
            
        except Exception as e:
            self.logError.emit(f"Failed to start logging: {e}")
    
    def stopLogging(self):
        """Stop logging and close file"""
        if not self._is_logging:
            return
        
        self._is_logging = False
        
        # Signal writer thread to stop
        self._message_queue.put(None)
        
        # Wait for writer thread to finish
        if self._writer_thread:
            self._writer_thread.join(timeout=5)
        
        # Close file
        if self._current_log_file:
            self._current_log_file.close()
            self._current_log_file = None
        
        # Compress if older than 7 days (for future runs)
        self._compress_old_logs()
        
        self.logStopped.emit()
    
    def logRawMessage(self, msg):
        """
        Log raw MAVLink message bytes
        
        Args:
            msg: pymavlink message object
        """
        if not self._is_logging:
            return
        
        try:
            # Extract raw MAVLink packet bytes
            raw_bytes = msg.get_msgbuf()
            
            # Detect MAVLink version on first message
            if self._mavlink_version is None:
                self._detect_mavlink_version(raw_bytes)
            
            # Detect FC reboot
            if hasattr(msg, 'time_boot_ms'):
                self._detect_reboot(msg.time_boot_ms)
            
            # Queue for async write
            self._message_queue.put(raw_bytes)
            
        except Exception as e:
            self.logError.emit(f"Error logging message: {e}")
    
    def _detect_mavlink_version(self, raw_bytes):
        """Detect MAVLink version from magic byte"""
        if len(raw_bytes) > 0:
            magic = raw_bytes[0]
            if magic == 0xFE:
                self._mavlink_version = 1
            elif magic == 0xFD:
                self._mavlink_version = 2
    
    def _detect_reboot(self, time_boot_ms):
        """
        Detect FC reboot by checking if time_boot_ms decreased
        
        Args:
            time_boot_ms: Current boot time in milliseconds
        """
        # Initialize boot time offset on first message
        if self._boot_time_offset is None:
            self._boot_time_offset = time.time() - (time_boot_ms / 1000.0)
            self._previous_time_boot_ms = time_boot_ms
            return
        
        # Detect reboot: time_boot_ms decreased
        if time_boot_ms < self._previous_time_boot_ms:
            print(f"FC reboot detected: time_boot_ms {time_boot_ms} < previous {self._previous_time_boot_ms}")
            # Reset boot time offset
            self._boot_time_offset = time.time() - (time_boot_ms / 1000.0)
        
        self._previous_time_boot_ms = time_boot_ms
    
    def _write_loop(self):
        """Background thread for writing messages to disk"""
        while self._is_logging:
            try:
                # Get message from queue (blocking with timeout)
                raw_bytes = self._message_queue.get(timeout=1)
                
                # None signals shutdown
                if raw_bytes is None:
                    break
                
                # Write raw bytes to file
                with self._lock:
                    if self._current_log_file:
                        self._current_log_file.write(raw_bytes)
                        self._current_log_file.flush()
                
            except queue.Empty:
                continue
            except Exception as e:
                self.logError.emit(f"Write error: {e}")
    
    def _compress_old_logs(self):
        """Compress logs older than 7 days"""
        try:
            cutoff_time = time.time() - (7 * 24 * 60 * 60)  # 7 days ago
            
            for log_file in self.log_directory.glob("*.tlog"):
                # Skip if already compressed
                if log_file.suffix == '.gz':
                    continue
                
                # Check file age
                if log_file.stat().st_mtime < cutoff_time:
                    # Compress
                    gz_path = log_file.with_suffix('.tlog.gz')
                    with open(log_file, 'rb') as f_in:
                        with gzip.open(gz_path, 'wb') as f_out:
                            f_out.writelines(f_in)
                    
                    # Delete original
                    log_file.unlink()
                    
        except Exception as e:
            print(f"Compression error: {e}")
    
    def get_storage_stats(self):
        """
        Get storage statistics
        
        Returns:
            dict: {used_gb, num_logs, oldest_log, newest_log}
        """
        total_size = 0
        log_files = []
        
        for log_file in self.log_directory.glob("*.tlog*"):
            total_size += log_file.stat().st_size
            log_files.append(log_file)
        
        used_gb = total_size / (1024 ** 3)
        
        return {
            'used_gb': used_gb,
            'num_logs': len(log_files),
            'oldest_log': min(log_files, key=lambda f: f.stat().st_mtime) if log_files else None,
            'newest_log': max(log_files, key=lambda f: f.stat().st_mtime) if log_files else None
        }

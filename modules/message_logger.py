"""
Enhanced Message Logger Backend for QML Integration
Captures ALL terminal messages (print, errors, warnings, QML console.log) and forwards them to QML MessagesPanel
Similar to Mission Planner's message console
"""

import sys
import traceback
from io import StringIO
from PyQt5.QtCore import (
    QObject, pyqtSignal, pyqtSlot, QTimer, 
    qInstallMessageHandler, QtDebugMsg, QtInfoMsg, 
    QtWarningMsg, QtCriticalMsg, QtFatalMsg, QCoreApplication
)
from datetime import datetime


class MessageLogger(QObject):
    """Backend for logging messages to QML - Mission Planner style"""
    
    # CRITICAL: Signal signature must match QML exactly
    # QML expects: function onMessageAdded(message, severity)
    messageAdded = pyqtSignal(str, str)  # (message, severity)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._original_stdout = sys.stdout
        self._original_stderr = sys.stderr
        self._capturing = False
        self._message_buffer = []
        self._signal_test_done = False
        
        print("📨 MessageLogger initialized")
        
        # Install Qt message handler to capture qml: messages
        self._qt_message_handler_installed = False
        try:
            qInstallMessageHandler(self._qt_message_handler)
            self._qt_message_handler_installed = True
            print("✅ Qt message handler installed - QML console.log will be captured")
        except Exception as e:
            print(f"⚠️ Warning: Could not install Qt message handler: {e}")
    
    def start_capture(self):
        """Start capturing stdout/stderr"""
        if not self._capturing:
            sys.stdout = StreamCapture(self._original_stdout, self, "info")
            sys.stderr = StreamCapture(self._original_stderr, self, "error")
            self._capturing = True
            print("📨 Starting message logger capture...")
            
            # Send initial test message immediately
            self.logMessage("📨 Message Logger started - capturing all system output", "success")
            
            # Test signal emission after a short delay
            QTimer.singleShot(2000, self._test_signal_emission)
    
    def _test_signal_emission(self):
        """Test if signals are being received by QML"""
        if not self._signal_test_done:
            self._signal_test_done = True
            print("🧪 Testing MessageLogger → QML signal connection...")
            try:
                self.messageAdded.emit("🧪 SIGNAL TEST: If you see this in MessagesPanel, the connection works!", "info")
                print("✅ Test signal emitted - check MessagesPanel")
            except Exception as e:
                print(f"❌ Signal emission test failed: {e}")
                traceback.print_exc()
    
    def _qt_message_handler(self, msg_type, context, message):
        """Handle Qt messages (including qml: messages)"""
        try:
            # Determine severity based on Qt message type
            if msg_type == QtDebugMsg or msg_type == QtInfoMsg:
                severity = "info"
            elif msg_type == QtWarningMsg:
                severity = "warning"
            elif msg_type == QtCriticalMsg or msg_type == QtFatalMsg:
                severity = "error"
            else:
                severity = "info"
            
            # Also print to original stdout for debugging
            self._original_stdout.write(f"qml: {message}\n")
            self._original_stdout.flush()
            
            # Send to message panel if capturing
            if self._capturing and message.strip():
                # Remove "qml: " prefix if present
                clean_message = message.replace("qml: ", "").strip()
                if clean_message and self._should_log_qml_message(clean_message):
                    try:
                        self.messageAdded.emit(clean_message, severity)
                    except Exception as e:
                        self._original_stdout.write(f"❌ QML message emit error: {e}\n")
                        self._original_stdout.flush()
        except Exception as e:
            # Fallback to print if emit fails
            try:
                self._original_stdout.write(f"qml: {message}\n")
                self._original_stdout.flush()
            except:
                pass
    
    def _should_log_qml_message(self, message):
        """Filter out noisy/repetitive QML messages"""
        # Filter out these patterns
        filter_patterns = [
            "WebEngine: Updating drone position:",  # Too frequent
        ]
        
        # Always log important messages
        important_patterns = [
            "✅", "❌", "⚠️", "🛸", "📡", "🔌", 
            "ERROR", "WARNING", "CRITICAL",
            "Signal test", "MessagesPanel", "MessageLogger",
            "STATUSTEXT"  # Drone messages
        ]
        
        # Check if it's important
        for pattern in important_patterns:
            if pattern in message:
                return True
        
        # Check if it should be filtered
        for pattern in filter_patterns:
            if pattern in message:
                return False
        
        return True
    
    def stop_capture(self):
        """Stop capturing and restore original streams"""
        if self._capturing:
            sys.stdout = self._original_stdout
            sys.stderr = self._original_stderr
            self._capturing = False
            print("📨 Message capture stopped")
    
    @pyqtSlot(str, str)
    def logMessage(self, message, severity="info"):
        """
        Log a message from Python or QML
        
        Args:
            message (str): The message to log
            severity (str): Message severity - "info", "success", "warning", or "error"
        
        CRITICAL: This is the main method that QML calls and Python uses
        """
        if not message or not message.strip():
            return
            
        try:
            clean_message = message.strip()
            
            # Debug output (comment out after testing)
            # print(f"[MessageLogger.logMessage] Emitting: '{clean_message}' | Severity: '{severity}'")
            
            # EMIT SIGNAL TO QML
            self.messageAdded.emit(clean_message, severity)
            
        except Exception as e:
            # Fallback to console if signal fails
            print(f"[MessageLogger] ❌ Emit failed: {e}")
            print(f"   Message was: {message}")
            print(f"   Severity was: {severity}")
            traceback.print_exc()
            
            # Try to print to original stdout as last resort
            try:
                self._original_stdout.write(f"{message}\n")
                self._original_stdout.flush()
            except:
                pass
    
    def log_info(self, message):
        """Log info message"""
        self.logMessage(message, "info")
    
    def log_success(self, message):
        """Log success message"""
        self.logMessage(message, "success")
    
    def log_warning(self, message):
        """Log warning message"""
        self.logMessage(message, "warning")
    
    def log_error(self, message):
        """Log error message"""
        self.logMessage(message, "error")
    
    def log_drone_message(self, message, severity="info"):
        """Log drone MAVLink STATUSTEXT message"""
        self.logMessage(f"🚁 DRONE: {message}", severity)
    
    def log_exception(self, exc_info=None):
        """Log exception with traceback"""
        if exc_info is None:
            exc_info = sys.exc_info()
        
        if exc_info[0] is not None:
            error_msg = ''.join(traceback.format_exception(*exc_info))
            self.messageAdded.emit(f"❌ Exception occurred:\n{error_msg}", "error")
    
    def cleanup(self):
        """Cleanup resources"""
        print("📨 Cleaning up MessageLogger...")
        self.stop_capture()
        
        # Restore Qt message handler
        if self._qt_message_handler_installed:
            try:
                qInstallMessageHandler(None)
                print("✅ Qt message handler restored")
            except:
                pass


class StreamCapture:
    """Captures output from stdout/stderr and forwards to MessageLogger"""
    
    def __init__(self, original_stream, logger, default_severity):
        self.original_stream = original_stream
        self.logger = logger
        self.default_severity = default_severity
        self.buffer = ""
        
    def write(self, text):
        """Capture written text"""
        # ALWAYS write to original stream (keep terminal output)
        self.original_stream.write(text)
        self.original_stream.flush()
        
        # Buffer and process complete lines
        self.buffer += text
        
        # Process complete lines
        while '\n' in self.buffer:
            line, self.buffer = self.buffer.split('\n', 1)
            if line.strip() and self._should_log_message(line):
                severity = self._determine_severity(line)
                try:
                    # EMIT TO MESSAGE PANEL
                    self.logger.messageAdded.emit(line.strip(), severity)
                except Exception as e:
                    self.original_stream.write(f"[StreamCapture] Emit error: {e}\n")
                    self.original_stream.flush()
    
    def _should_log_message(self, message):
        """Determine if message should be logged to panel"""
        # Filter out internal debug messages
        filter_patterns = [
            "[StreamCapture]",
            "[MessageLogger.logMessage]",
            "Remote debugging server",
            "DevTools listening",
        ]
        
        # Always log important messages
        important_indicators = [
            "✅", "❌", "⚠️", "🛸", "📡", "🔌", "📨", "🎮", "📧", "🚁",
            "ERROR", "CRITICAL", "FATAL", "Exception",
            "[Drone", "STATUSTEXT", "MAVLink",
            "Connected", "Disconnected", "Failed", "Success",
            "Pre-arm", "EKF", "GPS", "Armed", "Disarmed"
        ]
        
        # Check if important
        for indicator in important_indicators:
            if indicator in message:
                return True
        
        # Check if filtered
        for pattern in filter_patterns:
            if pattern in message:
                return False
        
        return True
    
    def _determine_severity(self, message):
        """Determine message severity from content"""
        msg_lower = message.lower()
        
        # Critical/Fatal errors
        if any(x in msg_lower for x in ['fatal', 'critical', 'exception occurred']):
            return "error"
        
        # Error indicators
        if any(x in msg_lower for x in ['❌', 'error', 'failed', 'failure', 'exception', 'traceback']):
            return "error"
        
        # Warning indicators
        if any(x in msg_lower for x in ['⚠️', 'warning', 'warn', 'caution', 'deprecated']):
            return "warning"
        
        # Success indicators
        if any(x in msg_lower for x in ['✅', 'success', 'completed', 'initialized', 'connected', 'started']):
            return "success"
        
        # Default to info
        return "info"
    
    def flush(self):
        """Flush any remaining buffered content"""
        if self.buffer.strip() and self._should_log_message(self.buffer):
            severity = self._determine_severity(self.buffer)
            try:
                self.logger.messageAdded.emit(self.buffer.strip(), severity)
            except:
                pass
            self.buffer = ""
        self.original_stream.flush()
    
    def isatty(self):
        """Check if stream is a TTY"""
        return self.original_stream.isatty()


# ============================================================================
# GLOBAL EXCEPTION HOOK
# ============================================================================
def setup_exception_hook(message_logger):
    """Setup global exception hook to catch all uncaught exceptions"""
    
    def exception_hook(exc_type, exc_value, exc_traceback):
        """Handle uncaught exceptions"""
        error_msg = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
        message_logger.log_error(f"❌ UNCAUGHT EXCEPTION:\n{error_msg}")
        
        # Also print to stderr
        sys.__stderr__.write(f"\n❌ UNCAUGHT EXCEPTION:\n{error_msg}\n")
        sys.__stderr__.flush()
    
    sys.excepthook = exception_hook
    message_logger.log_info("🛡️ Global exception handler installed")


# ============================================================================
# GLOBAL LOGGER INSTANCE
# ============================================================================
_global_logger = None

def set_global_logger(logger):
    """Set the global logger instance"""
    global _global_logger
    _global_logger = logger
    setup_exception_hook(logger)

def log_info(message):
    if _global_logger:
        _global_logger.log_info(message)
    else:
        print(f"ℹ️ {message}")

def log_success(message):
    if _global_logger:
        _global_logger.log_success(message)
    else:
        print(f"✅ {message}")

def log_warning(message):
    if _global_logger:
        _global_logger.log_warning(message)
    else:
        print(f"⚠️ {message}")

def log_error(message):
    if _global_logger:
        _global_logger.log_error(message)
    else:
        print(f"❌ {message}")

def log_exception(exc_info=None):
    if _global_logger:
        _global_logger.log_exception(exc_info)
    else:
        traceback.print_exc()
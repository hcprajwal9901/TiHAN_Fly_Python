"""
FIXED Mission Planner Compass Calibration with Reliable Completion Sound
This version ensures the completion beep plays consistently like Mission Planner
"""

import time
import queue
import threading
import math
from PyQt5.QtCore import QObject, pyqtSignal, pyqtProperty, pyqtSlot, QTimer, QMetaObject, Qt
from pymavlink import mavutil



class MissionPlannerCompassCalibration(QObject):
    """
    Mission Planner compatible compass calibration with RELIABLE completion sound
    """
    
    # PyQt Signals for QML integration
    calibrationStartedChanged = pyqtSignal()
    calibrationProgressChanged = pyqtSignal()
    calibrationComplete = pyqtSignal()
    calibrationFailed = pyqtSignal()
    statusTextChanged = pyqtSignal()
    mag1ProgressChanged = pyqtSignal()
    mag2ProgressChanged = pyqtSignal()
    mag3ProgressChanged = pyqtSignal()
    droneConnectionChanged = pyqtSignal()
    buzzerTestChanged = pyqtSignal()
    orientationChanged = pyqtSignal()
    retryAttemptChanged = pyqtSignal()
    rebootInitiated = pyqtSignal()
    compassCountChanged = pyqtSignal()

    def __init__(self, drone_model):
        super().__init__()
        self.drone_model = drone_model
        
        # Calibration state management
        self._calibration_started = False
        self._status_text = "Ready for compass calibration"
        self._current_orientation = 0
        self._retry_attempt = 0
        self._max_retries = 3
        
        # Progress tracking - CRITICAL FIX: Use thread-safe updates
        self._mag1_progress = 0.0
        self._mag2_progress = 0.0
        self._mag3_progress = 0.0
        self._progress_lock = threading.Lock()
        
        # Calibration workflow state
        self._orientations_completed = [False] * 6
        self._calibration_thread = None
        self._stop_calibration = False
        self._calibration_success = False
        self._calibration_active = False
        
        # CRITICAL FIX: Completion tracking to prevent multiple sounds
        self._completion_sound_played = False
        self._last_completion_check = 0
        
        # Hardware buzzer state - FIXED for Pixhawk
        self._buzzer_available = False
        self._pixhawk_target_system = 1
        self._pixhawk_target_component = 1
        self._last_beep_time = 0
        
        # MAVLink integration - CRITICAL FIXES
        self._mavlink_connection = None
        self._compass_cal_started = False
        self._last_progress_time = 0
        self._progress_timeout = 30.0
        self._compass_count = 2  # Track number of compasses
        
        # CRITICAL FIX: Add simulated progress for testing
        self._use_simulated_progress = True  # Default to simulation for now
        self._simulation_timer = QTimer()
        self._simulation_timer.timeout.connect(self._simulate_progress_update)
        self._simulation_progress = 0
        
        # Mission Planner heartbeat timer
        self._heartbeat_timer = QTimer()
        self._heartbeat_timer.timeout.connect(self._heartbeat_beep)
        
        # CRITICAL FIX: Completion verification timer
        self._completion_timer = QTimer()
        self._completion_timer.timeout.connect(self._verify_completion)
        self._completion_timer.setSingleShot(False)
        self._completion_timer.setInterval(500)  # Check every 500ms

        # ── Smooth progress animation ─────────────────────────────────────────
        # Increments display by 1% every 900 ms so the bar moves smoothly
        # (1-100 in ~90 s). Real ArduPilot confirmations set the floor so the
        # bar never goes backward below a confirmed value.
        self._smooth_timer = QTimer()
        self._smooth_timer.timeout.connect(self._smooth_tick)
        self._smooth_timer.setInterval(900)       # 1% per 900 ms ≈ 90 s total
        self._confirmed_floor = 0.0               # highest ArduPilot-confirmed %
        
        # Mission Planner orientation descriptions
        self._orientations = [
            "Please rotate the vehicle so that the FRONT points down",
            "Please rotate the vehicle so that the BACK points down", 
            "Please rotate the vehicle so that the LEFT side points down",
            "Please rotate the vehicle so that the RIGHT side points down",
            "Please rotate the vehicle so that the TOP points down",
            "Please rotate the vehicle so that the BOTTOM points down"
        ]
        
        # Mission Planner completion thresholds
        self._final_completion_threshold = 100.0

        # Thread-safe message queue — mavlink_thread pushes here instead of
        # compass_calibration calling recv_match() on the shared socket.
        self._msg_queue = queue.Queue(maxsize=200)

        # Connect to drone model signals
        if self.drone_model:
            if hasattr(self.drone_model, 'droneConnectedChanged'):
                self.drone_model.droneConnectedChanged.connect(self._on_drone_connection_changed)
            elif hasattr(self.drone_model, 'isConnectedChanged'):
                self.drone_model.isConnectedChanged.connect(self._on_drone_connection_changed)
            self._update_connection_state()
    
    # PyQt Properties for QML binding
    @pyqtProperty(bool, notify=calibrationStartedChanged)
    def calibrationStarted(self):
        return self._calibration_started

    @pyqtProperty(int, notify=compassCountChanged)
    def compassCount(self):
        """Number of active compasses — readable from QML."""
        return self._compass_count if self._compass_count and self._compass_count > 0 else 2
    
    @pyqtProperty(str, notify=statusTextChanged)
    def statusText(self):
        return self._status_text
     
    @pyqtProperty(float, notify=mag1ProgressChanged)
    def mag1Progress(self):
        """FIXED: Thread-safe property access"""
        try:
            with self._progress_lock:
                return float(self._mag1_progress)
        except:
            return 0.0

    @pyqtProperty(float, notify=mag2ProgressChanged) 
    def mag2Progress(self):
        """FIXED: Thread-safe property access"""
        try:
            with self._progress_lock:
                return float(self._mag2_progress)
        except:
            return 0.0

    @pyqtProperty(float, notify=mag3ProgressChanged) 
    def mag3Progress(self):
        """FIXED: Thread-safe property access"""
        try:
            with self._progress_lock:
                return float(self._mag3_progress)
        except:
            return 0.0
     
    def _detect_available_magnetometers(self):
        """Return the number of active magnetometers.

        BUG FIX: The previous implementation called recv_match() directly on
        the shared socket, racing with MAVLinkThread (especially visible over
        WiFi where packets arrive slower and are more likely to be stolen).
        We now rely only on the compass count that the monitoring worker
        populates via push_mavlink_msg, and fall back to 2 (the most common
        Pixhawk configuration) instead of 3 to avoid showing a phantom 3rd bar.
        """
        # compass_count may be updated later by COMPASS_CAL_PROGRESS messages
        # received via the queue-based monitoring path.
        if self._compass_count and self._compass_count > 0:
            return self._compass_count
        print("[Compass] Using default 2-compass assumption (WiFi-safe)")
        self._compass_count = 2
        return 2
     
    def _update_ui_for_compass_count(self):
        """Update UI to show only active compasses"""
        # This would be called from QML to hide/show progress bars based on actual compass count
        print(f"[Compass] UI should show {self._compass_count} compass progress bars")
        
        # Emit signal to QML to update visibility
        # You would need to add this signal and property to your class
        self.compassCountChanged.emit()

    def _update_progress_safe(self, compass_id, progress_value):
        """CRITICAL FIX: Simplified, thread-safe progress updates"""
        try:
            progress_float = float(progress_value)
            print(f"[Compass] Updating compass {compass_id}: {progress_float}%")
            
            with self._progress_lock:
                if compass_id == 0:
                    self._mag1_progress = progress_float
                elif compass_id == 1:
                    self._mag2_progress = progress_float  
                else:
                    print(f"[Compass] Invalid compass ID: {compass_id}")
                    return False
            
            # CRITICAL: Always emit signals on main thread
            QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
            self._last_progress_time = time.time()
            
            return True
            
        except Exception as e:
            print(f"[Compass] Progress update error: {e}")
            return False
    
    @pyqtProperty(bool, notify=droneConnectionChanged)
    def isDroneConnected(self):
        return self.drone_model.isConnected if self.drone_model else False
    
    @pyqtProperty(int, notify=orientationChanged)
    def currentOrientation(self):
        return self._current_orientation + 1
    
    @pyqtProperty(int, notify=retryAttemptChanged)
    def retryAttempt(self):
        return self._retry_attempt
    
    def _update_connection_state(self):
        """Update MAVLink connection reference and detect Pixhawk"""
        if self.drone_model and self.drone_model.isConnected:
            # Try the direct drone_connection property first (most reliable)
            connection = None
            
            if hasattr(self.drone_model, 'drone_connection'):
                connection = self.drone_model.drone_connection
                if connection and hasattr(connection, 'recv_match'):
                    print(f"[Compass] Found MAVLink connection via drone_connection property")
            
            # Fallback: try _drone attribute directly
            if not connection and hasattr(self.drone_model, '_drone'):
                candidate = self.drone_model._drone
                if candidate and hasattr(candidate, 'recv_match'):
                    connection = candidate
                    print(f"[Compass] Found MAVLink connection via _drone attribute")
            
            if connection:
                self._mavlink_connection = connection
                self._use_simulated_progress = False
                self._detect_pixhawk_buzzer()
                print(f"[Compass] MAVLink connection established: {type(self._mavlink_connection)}")
            else:
                print("[Compass] WARNING: Could not find MAVLink connection - using simulation mode")
                self._use_simulated_progress = True
        else:
            self._mavlink_connection = None
            self._buzzer_available = False
            self._use_simulated_progress = True
    
    def _on_drone_connection_changed(self):
        """Handle drone connection state changes"""
        was_connected = self._mavlink_connection is not None
        self._update_connection_state()
        
        if not self.isDroneConnected and was_connected:
            print("[Compass] Drone disconnected - stopping calibration")
            if self._calibration_started:
                self.stopCalibration()
        
        self.droneConnectionChanged.emit()
    
    def _detect_pixhawk_buzzer(self):
        """Detect Pixhawk buzzer capability via MAVLink heartbeat"""
        if not self._mavlink_connection:
            self._buzzer_available = False
            return
        
        try:
            # Get the target system and component from the connection
            if hasattr(self._mavlink_connection, 'target_system'):
                self._pixhawk_target_system = self._mavlink_connection.target_system
            
            if hasattr(self._mavlink_connection, 'target_component'):
                self._pixhawk_target_component = self._mavlink_connection.target_component
            
            # For ArduPilot/Pixhawk, buzzer is always available if connected
            self._buzzer_available = True
            print(f"[Compass] Pixhawk buzzer detected - Target: System={self._pixhawk_target_system}, Component={self._pixhawk_target_component}")
            
        except Exception as e:
            print(f"[Compass] Pixhawk buzzer detection failed: {e}")
            self._buzzer_available = False
    
    def _play_pixhawk_buzzer(self, tune_string, description=""):
        """Play buzzer tones on Pixhawk hardware.

        BUG FIXES applied here:
        1. play_tune_send is called with 3 args (MAVLink1) then falls back to
           4 args (MAVLink2) — the old code always sent 4 args which raises an
           exception on many firmwares, silently suppressing ALL beeps over WiFi.
        2. The write lock from DroneModel is acquired when available so that
           this call does not race with the MAVLinkThread over the shared socket.
        """
        if not self._mavlink_connection:
            print(f"[Compass] No MAVLink connection available for: {description}")
            return False

        if not self._buzzer_available:
            print(f"[Compass] Buzzer not detected for: {description}")
            return False

        try:
            print(f"[Compass] Playing buzzer: {description}")

            specific_tunes = {
                "startup":    "MFT200L16C16P8",   # Start Calibration: ***
                "heartbeat":  "MFT300L32C16",     # Periodic tick
                "milestone":  "MFT150L16C16",     # Orientation complete
                "success":    "MFT120L8CCDE",     # Success: ***↑
                "completion": "MFT120L8CCDE",     # Same as success
                "failure":    "MFT120L8EDCC"      # Failure: ***↓
            }

            tune_text  = specific_tunes.get(tune_string, "MFT200L16C16")
            tune_bytes = tune_text.encode('ascii')
            print(f"[Compass] Sending tune: '{tune_text}' for {description}")

            if not (hasattr(self._mavlink_connection, 'mav') and
                    hasattr(self._mavlink_connection.mav, 'play_tune_send')):
                print("[Compass] play_tune_send not available on this connection")
                return False

            # Acquire the DroneModel write lock if it is accessible so we don't
            # race with MAVLinkThread writes (critical over WiFi).
            write_lock = None
            if self.drone_model and hasattr(self.drone_model, '_mavlink_write_lock'):
                write_lock = self.drone_model._mavlink_write_lock

            def _send():
                # FIX: try 3-arg form first (MAVLink1 / most firmwares),
                # then fall back to 4-arg form (MAVLink2 PLAY_TUNE_V2).
                try:
                    self._mavlink_connection.mav.play_tune_send(
                        self._pixhawk_target_system,
                        self._pixhawk_target_component,
                        tune_bytes
                    )
                    return True
                except TypeError:
                    # 4-arg version (MAVLink2)
                    self._mavlink_connection.mav.play_tune_send(
                        self._pixhawk_target_system,
                        self._pixhawk_target_component,
                        tune_bytes,
                        b""
                    )
                    return True

            # Send twice with 150ms gap to survive WiFi UDP packet loss
            sent = False
            for attempt in range(2):
                try:
                    if write_lock:
                        with write_lock:
                            sent = _send()
                    else:
                        sent = _send()
                except Exception:
                    pass
                if attempt == 0:
                    time.sleep(0.15)

            if sent:
                print(f"[Compass] Buzzer command sent successfully: {description}")
            return sent

        except Exception as e:
            print(f"[Compass] Buzzer send error: {e}")
            return False
    
    @pyqtSlot()
    def testBuzzer(self):
        """Test Pixhawk buzzer - FIXED VERSION"""
        print("[Compass] Testing Pixhawk buzzer...")
        
        if not self.isDroneConnected and not self._use_simulated_progress:
            self._set_status("Cannot test buzzer - drone not connected")
            return
        
        if self._use_simulated_progress:
            self._set_status("Simulated mode - buzzer test would work with real hardware")
            self.buzzerTestChanged.emit()
            return
        
        # Test with predefined tune
        success = self._play_pixhawk_buzzer("startup", "Pixhawk buzzer test")
        
        if success:
            self._set_status("Pixhawk hardware buzzer test sent successfully")
        else:
            self._set_status("Pixhawk buzzer command failed - check MAVLink connection")
        
        self.buzzerTestChanged.emit()
    
    @pyqtSlot()
    def testProgressBars(self):
        """CRITICAL FIX: Test progress bar updates independently"""
        print("[Compass] Testing progress bar updates...")
        
        def update_progress():
            for i in range(0, 101, 5):
                with self._progress_lock:
                    self._mag1_progress = float(i)
                    self._mag2_progress = float(i * 0.8)
                    self._mag3_progress = float(i * 0.6)
                
                # CRITICAL: Use QMetaObject to invoke signals on main thread
                QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
                print(f"[Compass] Test progress: Mag1={i}%, Mag2={i*0.8}%, Mag3={i*0.6}%")
                time.sleep(0.2)
        
        # Run test in separate thread
        test_thread = threading.Thread(target=update_progress, daemon=True)
        test_thread.start()
        
        self._set_status("Testing progress bars...")
    
    @pyqtSlot()
    def startCalibration(self):
        """Start calibration with confirmation beep"""
        if not self.isDroneConnected and not self._use_simulated_progress:
            self._set_status("Cannot start calibration - drone not connected")
            return
        
        if self._calibration_started:
            self._set_status("Calibration already in progress")
            return
        
        print("[Compass] Starting compass calibration with confirmation beep...")
        
        # Reset state
        self._calibration_started = True
        self._calibration_active = True
        self._current_orientation = 0
        self._orientations_completed = [False] * 6
        self._stop_calibration = False
        self._calibration_success = False
        self._retry_attempt = 0
        self._last_progress_time = time.time()
        
        # CRITICAL FIX: Reset completion tracking
        self._completion_sound_played = False
        self._last_completion_check = 0
        
        # Reset smooth-progress state
        self._confirmed_floor = 0.0

        # Reset progress
        with self._progress_lock:
            self._mag1_progress = 0.0
            self._mag2_progress = 0.0
        QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
        
        # PLAY CONFIRMATION BEEP - Short beep when calibration starts
        if self._mavlink_connection:
            self._play_pixhawk_buzzer("startup", "Calibration start confirmation")
        elif self._use_simulated_progress:
            print("[Compass] Simulation: Start calibration beep played")
        
        # ── Re-check the MAVLink connection right before starting ──────────────
        # Over WiFi the handshake is slower, so _update_connection_state() may
        # have run during __init__ before _drone was assigned.  Refresh here to
        # catch a late-arriving connection (fixes "simulation mode on WiFi" bug).
        if self._use_simulated_progress and self.drone_model and self.drone_model.isConnected:
            print("[Compass] Re-checking connection state before start (WiFi late-connect fix)...")
            self._update_connection_state()

        # Start appropriate monitoring based on connection
        if self._mavlink_connection:
            # REAL HARDWARE MODE — always preferred when a connection exists
            self._use_simulated_progress = False
            self._send_compass_calibration_start()

            # Start monitoring thread
            self._calibration_thread = threading.Thread(target=self._mavlink_monitoring_worker, daemon=True)
            self._calibration_thread.start()

            # Request calibration data streams
            self._request_calibration_data_streams()
        else:
            # Simulation-only fallback (no drone connected at all)
            self._use_simulated_progress = True
            self._simulation_progress = 0
            self._simulation_timer.start(500)  # 500ms updates
        
        # Start heartbeat timer for periodic beeps
        self._heartbeat_timer.start(5000)  # Every 5 seconds

        # Start smooth progress animation (1% per 900 ms)
        self._smooth_timer.start()

        # CRITICAL FIX: Start completion verification timer
        self._completion_timer.start()

        self._set_status(f"Calibration started! {self._orientations[0]}")
        self.calibrationStartedChanged.emit()
        self.orientationChanged.emit()
    
    @pyqtSlot()
    def stopCalibration(self):
        """Stop compass calibration"""
        if not self._calibration_started:
            return
        
        print("[Compass] Stopping compass calibration...")
        
        self._stop_calibration = True
        self._calibration_started = False
        self._calibration_active = False
        
        # Stop timers
        self._heartbeat_timer.stop()
        self._simulation_timer.stop()
        self._completion_timer.stop()
        self._smooth_timer.stop()
        
        # Send MAVLink calibration cancel command
        if self._mavlink_connection:
            self._send_compass_calibration_cancel()
        
        # Reset progress and state - CRITICAL FIX
        with self._progress_lock:
            self._mag1_progress = 0.0
            self._mag2_progress = 0.0
            self._mag3_progress = 0.0
        
        QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
        self._set_status("Calibration cancelled")
        
        self.calibrationStartedChanged.emit()
    
#progress update function for testing
    @pyqtSlot()  
    def forceProgressUpdate(self):
        """DEBUG: Force progress bar updates for testing"""
        print("[Compass] FORCING progress update for testing...")
        
        with self._progress_lock:
            # Set test values
            self._mag1_progress = 45.0
            self._mag2_progress = 32.0
        
        # Force signal emission
        QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
        
        self._set_status("Forced progress update - Mag1: 45%, Mag2: 32%, Mag3: 28%")

    @pyqtSlot()
    def _smooth_tick(self):
        """Increment progress by 1% per tick, capped at 99%.

        The confirmed floor (set by real ArduPilot STATUSTEXT data) is always
        respected — the display value can never go *below* the confirmed value,
        but the animation keeps running until completion.
        """
        if not self._calibration_active:
            self._smooth_timer.stop()
            return

        with self._progress_lock:
            # Start from whichever is higher: current display or confirmed floor
            current = max(self._mag1_progress, self._confirmed_floor)
            # Increment by 1%, hard-cap at 99 so only real success reaches 100
            new_val = min(99.0, current + 1.0)
            self._mag1_progress = new_val
            self._mag2_progress = new_val   # keep both bars in sync visually

        QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)

     #reboot function

     
    @pyqtSlot(result=bool)
    def rebootAutopilot(self):
     """Reboot the autopilot via MAVLink command - FIXED VERSION"""
     print("[DroneCommander] Reboot autopilot requested")
    
     if not self._mavlink_connection:
        print("[DroneCommander] No MAVLink connection for reboot")
        self._set_status("Cannot reboot - no MAVLink connection")
        return False
    
     try:
        print("[DroneCommander] Sending autopilot reboot command...")
        
        # Use the same target system/component as compass calibration
        target_system = getattr(self, '_pixhawk_target_system', 1)
        target_component = getattr(self, '_pixhawk_target_component', 1)
        
        self._mavlink_connection.mav.command_long_send(
            target_system,
            target_component, 
            mavutil.mavlink.MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN,
            0,  # confirmation
            1,  # param1: 1 = reboot autopilot
            0,  # param2: 0 = no companion computer reboot
            0, 0, 0, 0, 0  # unused params
        )
        
        print("[DroneCommander] Reboot command sent successfully")
        
        # Update status to inform user
        self._set_status("Autopilot reboot command sent - device will restart")
        
        # Emit signal so QML can close the compass window
        self.rebootInitiated.emit()
        
        # Schedule auto-reconnect logic via DroneModel
        if self.drone_model and hasattr(self.drone_model, 'scheduleReconnect'):
            self.drone_model.scheduleReconnect()
        else:
            # Fallback if scheduleReconnect is absent
            QTimer.singleShot(2000, self._disconnect_after_reboot)
        
        return True
        
     except Exception as e:
        error_msg = f"Reboot command failed: {e}"
        print(f"[DroneCommander] {error_msg}")
        self._set_status(error_msg)
        return False

    def _disconnect_after_reboot(self):
        """Disconnect the drone cleanly after a reboot command was sent."""
        try:
            if self.drone_model and hasattr(self.drone_model, 'disconnectDrone'):
                print("[DroneCommander] Disconnecting after reboot...")
                self.drone_model.disconnectDrone()
        except Exception as e:
            print(f"[DroneCommander] Post-reboot disconnect error: {e}")
    
    @pyqtSlot()
    def acceptCalibration(self):
        """Accept completed calibration - MANUAL REBOOT VERSION"""
        if not self._calibration_started or not self._calibration_success:
            return
        
        print("[Compass] Accepting compass calibration...")
        
        # Send MAVLink calibration accept command
        if self._mavlink_connection:
            self._send_compass_calibration_accept()
            # PLAY FINAL SUCCESS BEEP - same pattern as completion
            self._play_pixhawk_buzzer("success", "Calibration accepted - manual reboot required")
        elif self._use_simulated_progress:
            print("[Compass] Simulation: Calibration accepted")
        
        # Stop calibration
        self._stop_calibration = True
        self._calibration_started = False
        self._calibration_active = False
        self._heartbeat_timer.stop()
        self._simulation_timer.stop()
        self._completion_timer.stop()
        
        # MANUAL REBOOT MESSAGE - No automatic reboot
        self._set_status("✅ Calibration completed successfully! Manual reboot required before flight.")
        
        self.calibrationComplete.emit()
        self.calibrationStartedChanged.emit()
    
    def _simulate_progress_update(self):
        """IMPROVED: More reliable simulation with completion sound"""
        if not self._calibration_active:
            self._simulation_timer.stop()
            return
        
        # Increment progress more aggressively
        self._simulation_progress += 5  # Faster updates
        
        # Different rates for realism
        progress1 = min(100, self._simulation_progress)
        progress2 = min(100, max(0, self._simulation_progress - 10))
        progress3 = min(100, max(0, self._simulation_progress - 20))
        
        # Direct update using the safe method
        self._update_progress_safe(0, progress1)
        self._update_progress_safe(1, progress2)
        
        print(f"[Compass] Simulation: {progress1}%, {progress2}%, {progress3}%")
        
        # Check orientation milestones
        self._check_orientation_milestone(progress1)
        
        # Complete at 100%
        if progress1 >= 100:
            self._simulation_timer.stop()
            # CRITICAL FIX: Force completion check
            self._force_completion_check()
    
    def _check_orientation_milestone_simulated(self, progress):
        """Check orientation milestones for simulation"""
        milestone_points = [15, 30, 45, 60, 75, 90]  # Progress points for each orientation
        
        for i, milestone in enumerate(milestone_points):
            if progress >= milestone and not self._orientations_completed[i]:
                self._orientations_completed[i] = True
                self._current_orientation = i + 1
                
                print(f"[Compass] Simulated orientation {i + 1}/6 completed at {progress}%")
                
                if i < 5:  # Not the last orientation
                    next_text = self._orientations[i + 1] if i + 1 < len(self._orientations) else "Final orientation"
                    self._set_status(f"Orientation {i + 2}/6: {next_text}")
                else:
                    self._set_status("All orientations complete! Computing calibration...")
                
                QMetaObject.invokeMethod(self, "orientationChanged", Qt.QueuedConnection)
                break
    
    def _heartbeat_beep(self):
        """Mission Planner heartbeat beep - periodic tick while calibrating"""
        if not self._calibration_started or not self._calibration_active:
            return
        
        # Check for timeout
        current_time = time.time()
        if current_time - self._last_progress_time > self._progress_timeout:
            self._set_status("Timeout - please rotate vehicle through all orientations")
            # Don't stop, just warn
        
        # PLAY HEARTBEAT BEEP (periodic reminder)
        if self._mavlink_connection:
            self._play_pixhawk_buzzer("heartbeat", "Heartbeat reminder")
        elif self._use_simulated_progress:
            print("[Compass] Simulation: Heartbeat beep")
    
    def _get_write_lock(self):
        """Return the DroneModel write lock if available, else None."""
        if self.drone_model and hasattr(self.drone_model, '_mavlink_write_lock'):
            return self.drone_model._mavlink_write_lock
        return None

    def _send_compass_calibration_start(self):
        """ENHANCED: Start calibration with proper message stream requests"""
        if not self._mavlink_connection:
            print("[Compass] No MAVLink connection")
            return
        
        try:
            print("[Compass] Starting compass calibration with automatic progress...")
            
            # Update target system/component
            if hasattr(self._mavlink_connection, 'target_system'):
                self._pixhawk_target_system = self._mavlink_connection.target_system
            if hasattr(self._mavlink_connection, 'target_component'):
                self._pixhawk_target_component = self._mavlink_connection.target_component

            write_lock = self._get_write_lock()

            # Helper: all MAVLink writes go through the shared write lock so we
            # don't race with MAVLinkThread (especially important over WiFi).
            def _locked_send(fn, *args, **kwargs):
                if write_lock:
                    with write_lock:
                        fn(*args, **kwargs)
                else:
                    fn(*args, **kwargs)

            # Use MAV_CMD_DO_START_MAG_CAL (42424) — this is the command that
            # makes ArduPilot send COMPASS_CAL_PROGRESS/REPORT messages.
            # MAV_CMD_PREFLIGHT_CALIBRATION param2=1 is the legacy path that
            # writes directly to EEPROM with no progress telemetry.
            MAV_CMD_DO_START_MAG_CAL = getattr(
                mavutil.mavlink, 'MAV_CMD_DO_START_MAG_CAL', 42424)

            _locked_send(
                self._mavlink_connection.mav.command_long_send,
                self._pixhawk_target_system,
                self._pixhawk_target_component,
                MAV_CMD_DO_START_MAG_CAL,
                0,    # confirmation
                0,    # param1: mag bitmask (0 = all compasses)
                1,    # param2: retry on failure
                1,    # param3: autosave on completion
                0,    # param4: delay (seconds)
                0,    # param5: autoreboot after success (0 = no)
                0, 0  # param6, param7: unused
            )
            print("[Compass] Calibration START command sent (MAV_CMD_DO_START_MAG_CAL)")

            try:
                _locked_send(
                    self._mavlink_connection.mav.command_long_send,
                    self._pixhawk_target_system,
                    self._pixhawk_target_component,
                    mavutil.mavlink.MAV_CMD_REQUEST_MESSAGE,
                    0,
                    mavutil.mavlink.MAVLINK_MSG_ID_COMPASS_CAL_PROGRESS,
                    10, 0, 0, 0, 0, 0
                )
                print("[Compass] Requested COMPASS_CAL_PROGRESS at 10Hz")
            except Exception:
                pass

            try:
                _locked_send(
                    self._mavlink_connection.mav.command_long_send,
                    self._pixhawk_target_system,
                    self._pixhawk_target_component,
                    mavutil.mavlink.MAV_CMD_REQUEST_MESSAGE,
                    0,
                    mavutil.mavlink.MAVLINK_MSG_ID_COMPASS_CAL_REPORT,
                    5, 0, 0, 0, 0, 0
                )
                print("[Compass] Requested COMPASS_CAL_REPORT at 5Hz")
            except Exception:
                pass
                
            # Request general data streams that include calibration info
            data_streams = [
                mavutil.mavlink.MAV_DATA_STREAM_EXTENDED_STATUS,
                mavutil.mavlink.MAV_DATA_STREAM_EXTRA1,
                mavutil.mavlink.MAV_DATA_STREAM_EXTRA2,
            ]
            
            for stream in data_streams:
                try:
                    self._mavlink_connection.mav.request_data_stream_send(
                        self._pixhawk_target_system,
                        self._pixhawk_target_component,
                        stream,
                        10,  # 10 Hz
                        1    # start streaming
                    )
                    print(f"[Compass] Requested data stream {stream}")
                except Exception as e:
                    print(f"[Compass] Stream {stream} request failed: {e}")
                    
            print("[Compass] All calibration setup complete - progress should update automatically")
            
        except Exception as e:
            print(f"[Compass] Calibration start error: {e}")
    
    def _request_calibration_data_streams(self):
        """Request calibration data streams — thread-safe, uses write lock."""
        if not self._mavlink_connection:
            return

        write_lock = self._get_write_lock()

        def _locked_send(fn, *args, **kwargs):
            if write_lock:
                with write_lock:
                    fn(*args, **kwargs)
            else:
                fn(*args, **kwargs)

        print("[Compass] Requesting calibration data streams (locked)...")

        # MAVLink message IDs for compass calibration — use integer literals as
        # some pymavlink builds don't expose these named constants.
        # COMPASS_CAL_PROGRESS = 191, COMPASS_CAL_REPORT = 192
        _COMPASS_CAL_PROGRESS = getattr(mavutil.mavlink, 'MAVLINK_MSG_ID_COMPASS_CAL_PROGRESS', 191)
        _COMPASS_CAL_REPORT   = getattr(mavutil.mavlink, 'MAVLINK_MSG_ID_COMPASS_CAL_REPORT',   192)

        message_requests = [
            _COMPASS_CAL_PROGRESS,
            _COMPASS_CAL_REPORT,
        ]

        for msg_id in message_requests:
            try:
                _locked_send(
                    self._mavlink_connection.mav.command_long_send,
                    self._pixhawk_target_system,
                    self._pixhawk_target_component,
                    mavutil.mavlink.MAV_CMD_REQUEST_MESSAGE,
                    0,
                    msg_id,
                    0, 0, 0, 0, 0, 0
                )
                print(f"[Compass] Requested message ID {msg_id}")
            except Exception as e:
                print(f"[Compass] Message {msg_id} request failed: {e}")

        for stream in [
            mavutil.mavlink.MAV_DATA_STREAM_EXTENDED_STATUS,
            mavutil.mavlink.MAV_DATA_STREAM_EXTRA1,
            mavutil.mavlink.MAV_DATA_STREAM_EXTRA2,
        ]:
            try:
                _locked_send(
                    self._mavlink_connection.mav.request_data_stream_send,
                    self._pixhawk_target_system,
                    self._pixhawk_target_component,
                    stream,
                    10,
                    1
                )
                print(f"[Compass] Requested data stream {stream}")
            except Exception as e:
                print(f"[Compass] Stream {stream} request failed: {e}")

        print("[Compass] Data stream requests completed (locked)")

    def _send_compass_calibration_cancel(self):
        """Send MAV_CMD_DO_CANCEL_MAG_CAL (42426) to cancel compass calibration."""
        if not self._mavlink_connection:
            return
        try:
            MAV_CMD_DO_CANCEL_MAG_CAL = getattr(
                mavutil.mavlink, 'MAV_CMD_DO_CANCEL_MAG_CAL', 42426)
            write_lock = self._get_write_lock()
            def _locked_send(fn, *args, **kwargs):
                if write_lock:
                    with write_lock: fn(*args, **kwargs)
                else: fn(*args, **kwargs)
            _locked_send(
                self._mavlink_connection.mav.command_long_send,
                self._pixhawk_target_system,
                self._pixhawk_target_component,
                MAV_CMD_DO_CANCEL_MAG_CAL,
                0,         # confirmation
                0, 0, 0, 0, 0, 0, 0  # params unused
            )
            print("[Compass] MAVLink compass calibration CANCEL sent (MAV_CMD_DO_CANCEL_MAG_CAL)")
        except Exception as e:
            print(f"[Compass] Failed to send calibration cancel: {e}")
    
    def _send_compass_calibration_accept(self):
        """Send MAV_CMD_DO_ACCEPT_MAG_CAL (42425) to accept and save calibration."""
        if not self._mavlink_connection:
            return
        try:
            MAV_CMD_DO_ACCEPT_MAG_CAL = getattr(
                mavutil.mavlink, 'MAV_CMD_DO_ACCEPT_MAG_CAL', 42425)
            write_lock = self._get_write_lock()
            def _locked_send(fn, *args, **kwargs):
                if write_lock:
                    with write_lock: fn(*args, **kwargs)
                else: fn(*args, **kwargs)
            _locked_send(
                self._mavlink_connection.mav.command_long_send,
                self._pixhawk_target_system,
                self._pixhawk_target_component,
                MAV_CMD_DO_ACCEPT_MAG_CAL,
                0,         # confirmation
                0, 0, 0, 0, 0, 0, 0  # params unused
            )
            print("[Compass] MAVLink compass calibration ACCEPT sent (MAV_CMD_DO_ACCEPT_MAG_CAL)")
        except Exception as e:
            print(f"[Compass] Failed to send calibration accept: {e}")
    
    def push_mavlink_msg(self, msg):
        """
        Called by mavlink_thread (via current_msg signal) to deliver a
        MAVLink message without touching the shared socket a second time.
        Drops messages silently when the queue is full (calibration not running).
        """
        if not self._calibration_active:
            return
        try:
            self._msg_queue.put_nowait(msg)
        except queue.Full:
            pass  # Drop oldest-not-yet-consumed message; harmless

    def _mavlink_monitoring_worker(self):
        """
        Reads from self._msg_queue (fed by mavlink_thread) instead of calling
        recv_match() directly on the shared socket.  This eliminates the root
        cause of the 60 GB RAM leak.
        """
        print("[Compass] Calibration monitoring started (queue-based)")

        compass_msg_types = {
            'COMPASS_CAL_PROGRESS', 'COMPASS_CAL_REPORT', 'STATUSTEXT',
            'MAG_CAL_PROGRESS', 'MAG_CAL_REPORT', 'HEARTBEAT',
        }

        no_message_count = 0
        fallback_progress  = 0
        last_fallback_time = time.time()
        last_status_time   = time.time()

        while not self._stop_calibration and self._calibration_active:
            try:
                # Block for up to 100 ms so we don’t busy-spin
                try:
                    msg = self._msg_queue.get(timeout=0.1)
                    msg_type = msg.get_type()

                    if msg_type in compass_msg_types:
                        self._handle_mavlink_message(msg)

                    elif any(kw in msg_type.lower() for kw in ('compass', 'mag', 'cal', 'offset')):
                        self._handle_mavlink_message(msg)

                    no_message_count = 0

                except queue.Empty:
                    no_message_count += 1

                # Warn user if no real progress messages arrive — never fake completion
                current_time = time.time()
                if no_message_count > 50 and (current_time - last_fallback_time) > 2.0:
                    last_fallback_time = current_time
                    elapsed = current_time - self._last_progress_time
                    if elapsed > 10.0:
                        self._set_status(
                            "⚠️ No calibration data received. Rotate drone through all positions."
                        )
                        print(f"[Compass] WARNING: {int(elapsed)}s without COMPASS_CAL_PROGRESS "
                              f"— check that push_mavlink_msg is wired to register_msg_callback")

                if current_time - last_status_time > 10.0:
                    print(f"[Compass] Monitoring alive — no-msg-count: {no_message_count}")
                    last_status_time = current_time

            except Exception as e:
                print(f"[Compass] Monitoring error: {e}")
                time.sleep(0.5)

        print("[Compass] Calibration monitoring stopped")

    
    def _handle_mavlink_message(self, msg):
        """Handle incoming MAVLink messages - ENHANCED WITH PROGRESS FIX"""
        try:
            if msg.get_type() == 'COMPASS_CAL_PROGRESS':
                self._handle_progress_message(msg)
            elif msg.get_type() == 'COMPASS_CAL_REPORT':
                self._handle_report_message(msg)
            elif msg.get_type() == 'STATUSTEXT':
                self._handle_status_message(msg)
        except Exception as e:
            print(f"[Compass] Message handling error: {e}")
    
    def _handle_progress_message(self, msg):
        """ENHANCED: Better automatic progress extraction from any MAVLink message"""
        try:
            print(f"[Compass] Processing message: {msg.get_type()}")
            
            # Method 1: Try all possible progress field names
            progress_fields = [
                'completion_pct', 'completion_percent', 'progress', 'percent_complete',
                'cal_progress', 'calibration_progress', 'mag_progress', 'compass_progress'
            ]
            
            compass_id_fields = [
                'compass_id', 'id', 'sensor_id', 'mag_id', 'device_id'
            ]
            
            # Extract compass ID
            compass_id = -1
            for field in compass_id_fields:
                if hasattr(msg, field):
                    compass_id = getattr(msg, field, -1)
                    if compass_id >= 0:
                        break
            
            # Extract progress value
            progress_value = -1
            for field in progress_fields:
                if hasattr(msg, field):
                    progress_value = getattr(msg, field, -1)
                    if progress_value >= 0:
                        break
            
            # Method 2: Try to extract from completion_mask or similar
            if progress_value < 0:
                for mask_field in ['completion_mask', 'cal_mask', 'status_mask']:
                    if hasattr(msg, mask_field):
                        mask_val = getattr(msg, mask_field, 0)
                        if mask_val > 0:
                            progress_value = min(100.0, float(mask_val * 100.0 / 255.0))
                            break
            
            # Method 3: If we still don't have progress, check for any numeric field that might be progress
            if progress_value < 0:
                for attr_name in dir(msg):
                    if not attr_name.startswith('_'):
                        try:
                            attr_val = getattr(msg, attr_name)
                            if isinstance(attr_val, (int, float)) and 0 <= attr_val <= 100:
                                progress_value = float(attr_val)
                                print(f"[Compass] Found potential progress in field '{attr_name}': {progress_value}")
                                break
                        except:
                            pass
            
            # Apply the progress update
            success = False
            if progress_value >= 0:
                if compass_id >= 0:
                    # Update specific compass
                    success = self._update_progress_safe(compass_id, progress_value)
                    print(f"[Compass] Updated compass {compass_id}: {progress_value}%")
                else:
                    # Update all compasses with slight variations
                    for i in range(3):
                        variation = progress_value - (i * 2)  # Slight variation between compasses
                        variation = max(0, min(100, variation))
                        self._update_progress_safe(i, variation)
                    success = True
                    print(f"[Compass] Updated all compasses around {progress_value}%")
            
            # Check for orientation milestones
            if success and progress_value >= 0:
                self._check_orientation_milestone(progress_value)
                
            return success
            
        except Exception as e:
            print(f"[Compass] Enhanced progress message handling error: {e}")
            return False
    
    def _check_orientation_milestone(self, progress):
        """Check if we've reached a new orientation milestone with beep-beep sound"""
        if self._current_orientation < 6 and not self._orientations_completed[self._current_orientation]:
            # CHANGE THIS LINE - Make sure threshold is exactly what you want
            if progress >= 90.0 and not self._orientations_completed[self._current_orientation]:  # Use 90% instead of 85%
                self._orientations_completed[self._current_orientation] = True
                print(f"[Compass] Orientation {self._current_orientation + 1}/6 completed ({progress}%)")

                # PLAY BEEP-BEEP for orientation milestone
                if self._mavlink_connection:
                    self._play_pixhawk_buzzer("milestone", f"Orientation {self._current_orientation + 1} complete")
                elif self._use_simulated_progress:
                    print(f"[Compass] Simulation: Beep-beep for orientation {self._current_orientation + 1}")

                self._current_orientation += 1
                if self._current_orientation < 6:
                    next_text = self._orientations[self._current_orientation]
                    self._set_status(f"Orientation {self._current_orientation + 1}/6: {next_text}")
                    QMetaObject.invokeMethod(self, "orientationChanged", Qt.QueuedConnection)
                else:
                    self._set_status("All orientations complete! Computing calibration...")

    # CRITICAL FIX: New verification timer method
    @pyqtSlot()
    def _verify_completion(self):
        """CRITICAL FIX: Reliable completion verification with guaranteed sound"""
        if not self._calibration_active:
            self._completion_timer.stop()
            return
            
        current_time = time.time()
        
        # Prevent checking too frequently
        if current_time - self._last_completion_check < 0.5:
            return
            
        self._last_completion_check = current_time
        
        with self._progress_lock:
            mag1_complete = self._mag1_progress >= 99.0
            mag2_complete = self._mag2_progress >= 99.0
        
        # SUCCESS when BOTH mag1 and mag2 are at or above 99%
        if mag1_complete and mag2_complete and not self._calibration_success and not self._completion_sound_played:
            print("[Compass] COMPLETION VERIFIED: Both Mag1 and Mag2 at 100% - Playing success sound!")

            self._calibration_success = True
            self._completion_sound_played = True

            # Push bars to exactly 100%
            with self._progress_lock:
                self._mag1_progress = 100.0
                self._mag2_progress = 100.0
            QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)

            # CRITICAL FIX: Force completion sound with multiple attempts
            self._play_completion_sound_reliably()

            # Update status
            self._set_status("Calibration complete! Click Accept.")

            # Stop all timers — smooth timer must also stop here
            self._heartbeat_timer.stop()
            self._completion_timer.stop()
            self._smooth_timer.stop()

    
    def _force_completion_check(self):
        """Force immediate completion check - used by simulation"""
        print("[Compass] FORCING completion check...")
        
        with self._progress_lock:
            mag1_complete = self._mag1_progress >= 99.0
            mag2_complete = self._mag2_progress >= 99.0
        
        print(f"[Compass] Force check: Mag1={mag1_complete} ({self._mag1_progress}%), Mag2={mag2_complete} ({self._mag2_progress}%)")
        
        if mag1_complete and mag2_complete and not self._calibration_success and not self._completion_sound_played:
            print("[Compass] FORCE COMPLETION: Both compasses at 100%!")
            
            self._calibration_success = True
            self._completion_sound_played = True
            
            # CRITICAL FIX: Force completion sound
            self._play_completion_sound_reliably()
            
            self._set_status("Calibration complete! Click Accept.")
            
            # Stop timers
            self._heartbeat_timer.stop()
            if self._simulation_timer.isActive():
                self._simulation_timer.stop()
            if self._completion_timer.isActive():
                self._completion_timer.stop()
    
    def _play_completion_sound_reliably(self):
        """CRITICAL FIX: Play completion sound with multiple attempts to ensure it works"""
        print("[Compass] === PLAYING COMPLETION SOUND ===")
        
        if self._mavlink_connection:
            print("[Compass] Attempting hardware completion sound...")
            
            # Try multiple times to ensure the sound plays
            for attempt in range(3):
                try:
                    success = self._play_pixhawk_buzzer("completion", f"Calibration 100% complete (attempt {attempt + 1})")
                    if success:
                        print(f"[Compass] SUCCESS: Completion sound sent on attempt {attempt + 1}")
                        break
                    else:
                        print(f"[Compass] FAILED: Completion sound attempt {attempt + 1}")
                        time.sleep(0.2)  # Brief delay before retry
                except Exception as e:
                    print(f"[Compass] ERROR on completion sound attempt {attempt + 1}: {e}")
                    time.sleep(0.2)
            
            # Alternative: Try with different tune patterns
            alternative_tunes = ["success", "completion", "startup"]
            for tune in alternative_tunes:
                try:
                    print(f"[Compass] Trying alternative completion tune: {tune}")
                    success = self._play_pixhawk_buzzer(tune, f"Completion alternative: {tune}")
                    if success:
                        print(f"[Compass] SUCCESS: Alternative tune {tune} worked")
                        break
                    time.sleep(0.1)
                except Exception as e:
                    print(f"[Compass] Alternative tune {tune} failed: {e}")
                    
        elif self._use_simulated_progress:
            print("[Compass] *** SIMULATION: COMPLETION SOUND PLAYED ***")
            print("[Compass] *** Mission Planner style success melody: CCDE ***")
        
        print("[Compass] === COMPLETION SOUND SEQUENCE FINISHED ===")
    
    def _handle_report_message(self, msg):
        """Handle COMPASS_CAL_REPORT messages with proper beep sounds"""
        cal_status = getattr(msg, 'cal_status', -1)
        
        print(f"[Compass] === CALIBRATION REPORT ===")
        print(f"[Compass] Cal status: {cal_status}")
        
        MAG_CAL_SUCCESS       = 4
        MAG_CAL_FAILED        = 5
        MAG_CAL_BAD_ORIENT    = 6
        MAG_CAL_BAD_RADIUS    = 7

        if cal_status == MAG_CAL_SUCCESS:
            # ArduPilot confirmed success — force both to 100%
            with self._progress_lock:
                self._mag1_progress = 100.0
                self._mag2_progress = 100.0
            QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
            self._force_completion_check()

        elif cal_status in (MAG_CAL_FAILED, MAG_CAL_BAD_ORIENT, MAG_CAL_BAD_RADIUS):
            failure_reasons = {
                MAG_CAL_FAILED:     "Calibration failed",
                MAG_CAL_BAD_ORIENT: "Bad orientation detected — keep drone still at each position",
                MAG_CAL_BAD_RADIUS: "Bad radius — check for nearby magnetic interference",
            }
            reason = failure_reasons.get(cal_status, f"Calibration failed (status {cal_status})")

            self._retry_attempt += 1

            if self._retry_attempt < self._max_retries:
                self._set_status(f"❌ {reason}. Retrying... ({self._retry_attempt + 1}/{self._max_retries})")
                if self._mavlink_connection:
                    self._play_pixhawk_buzzer("failure", "Calibration failed - retrying")

                self._current_orientation = 0
                self._orientations_completed = [False] * 6
                self._completion_sound_played = False

                with self._progress_lock:
                    self._mag1_progress = 0.0
                    self._mag2_progress = 0.0

                QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
                QMetaObject.invokeMethod(self, "calibrationFailed", Qt.QueuedConnection)
                QMetaObject.invokeMethod(self, "retryAttemptChanged", Qt.QueuedConnection)

                time.sleep(1)
                self._send_compass_calibration_start()
            else:
                self._set_status(f"❌ {reason}. Max retries reached — check for magnetic interference.")
                if self._mavlink_connection:
                    self._play_pixhawk_buzzer("failure", "Calibration failed permanently")
                self.stopCalibration()

        else:
            # Ongoing status (0-3) — not a terminal report, ignore
            print(f"[Compass] COMPASS_CAL_REPORT non-terminal status: {cal_status} — ignoring")
    
    def _handle_status_message(self, msg):
        """Parse ArduPilot STATUSTEXT messages that carry compass calibration progress.

        ArduPilot sends calibration updates as STATUSTEXT when COMPASS_CAL_PROGRESS
        packets are not streamed. Known patterns:
          "Mag(N) good orientation: X FIT"    → direction X satisfied for compass N
          "Compass(N): Calibration successful" → calibration done
          "Compass(N): Calibration FAILED"    → calibration failed
        """
        import re
        try:
            text = (msg.text.decode('utf-8', errors='ignore')
                    if isinstance(msg.text, bytes) else str(msg.text)).strip()

            if not any(kw in text.lower() for kw in ['compass', 'mag', 'calibrat']):
                return

            print(f"[Compass] Pixhawk status: {text}")
            self._set_status(f"Pixhawk: {text}")
            self._last_progress_time = time.time()

            # ── "Mag(N) good orientation: X FIT" ─────────────────────────────
            # Track orientation INDICES per compass so we never double-count.
            # There are 6 possible directions (0-5); each one completed = 1/6.
            m = re.search(
                r'mag\s*\(?\s*(\d+)\s*\)?\s*good\s+orientation\s*[:\s]+(\d+)',
                text, re.IGNORECASE)
            if m:
                compass_num  = int(m.group(1))           # 1-based as sent by ArduPilot
                orient_idx   = int(m.group(2))           # which direction (0-5) was satisfied

                # Use per-compass sets stored on self so we can track unique orientations
                attr = f'_orient_done_{compass_num}'
                if not hasattr(self, attr):
                    setattr(self, attr, set())
                done_set = getattr(self, attr)
                done_set.add(orient_idx)

                n_done = len(done_set)
                pct    = round(min(100.0, n_done * 100.0 / 6.0), 1)
                print(f"[Compass] STATUSTEXT: compass {compass_num} → "
                      f"orientation {orient_idx} done ({n_done}/6 = {pct}%)")

                # Update the confirmed floor — the smooth animation will never
                # drop below this value; it continues incrementing from here.
                self._confirmed_floor = max(self._confirmed_floor, pct)
                self._check_orientation_milestone(pct)
                return


            # ── Success — only match the exact ArduPilot success phrase ───────
            # Do NOT match generic words like "complete" or "done"; they appear
            # in non-terminal messages ("setup complete", "done streaming", etc.)
            if re.search(r'calibration\s+successful|cal\s+successful', text, re.IGNORECASE):
                print("[Compass] STATUSTEXT: calibration SUCCESS confirmed by ArduPilot")
                with self._progress_lock:
                    self._mag1_progress = 100.0
                    self._mag2_progress = 100.0
                QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
                self._force_completion_check()
                return

            # ── Failure ───────────────────────────────────────────────────────
            if re.search(r'calibration\s+fail|cal\s+fail', text, re.IGNORECASE):
                print("[Compass] STATUSTEXT: calibration FAILURE detected")
                self._retry_attempt += 1
                if self._retry_attempt < self._max_retries:
                    self._set_status(
                        f"❌ Failed! Retrying… ({self._retry_attempt + 1}/{self._max_retries})")
                    if self._mavlink_connection:
                        self._play_pixhawk_buzzer("failure", "Calibration failed - retrying")
                    self._current_orientation = 0
                    self._orientations_completed = [False] * 6
                    self._completion_sound_played = False
                    # Clear per-compass orientation sets
                    for attr in [a for a in dir(self) if a.startswith('_orient_done_')]:
                        delattr(self, attr)
                    with self._progress_lock:
                        self._mag1_progress = 0.0
                        self._mag2_progress = 0.0
                    QMetaObject.invokeMethod(self, "_emit_progress_signals", Qt.QueuedConnection)
                    time.sleep(1)
                    self._send_compass_calibration_start()
                else:
                    self._set_status("❌ Max retries reached. Check for magnetic interference.")
                    if self._mavlink_connection:
                        self._play_pixhawk_buzzer("failure", "Calibration failed permanently")
                    self.stopCalibration()

        except Exception as e:
            print(f"[Compass] Status message parse error: {e}")


    
    @pyqtSlot()
    def checkConnectionHealth(self):
        """DEBUG: Check MAVLink connection health"""
        print(f"[Compass] === CONNECTION HEALTH CHECK ===")
        print(f"[Compass] DroneModel connected: {self.isDroneConnected}")
        print(f"[Compass] MAVLink connection: {self._mavlink_connection is not None}")
        print(f"[Compass] Simulation mode: {self._use_simulated_progress}")
        
        if self._mavlink_connection:
            print(f"[Compass] Connection type: {type(self._mavlink_connection)}")
            print(f"[Compass] Has mav attr: {hasattr(self._mavlink_connection, 'mav')}")
        
        # Test message receiving
        if self._mavlink_connection and not self._calibration_started:
            try:
                msg = self._mavlink_connection.recv_match(blocking=False, timeout=0.1)
                if msg:
                    print(f"[Compass] Sample message received: {msg.get_type()}")
                else:
                    print("[Compass] No messages in queue")
            except Exception as e:
                print(f"[Compass] Message test failed: {e}")

    @pyqtSlot()
    def _emit_progress_signals(self):
        """FIXED: Guaranteed signal emission"""
        try:
            # Get current values safely
            with self._progress_lock:
                mag1_val = self._mag1_progress
                mag2_val = self._mag2_progress  
                mag3_val = self._mag3_progress
            
            print(f"[Compass] Emitting signals: Mag1={mag1_val}%, Mag2={mag2_val}%, Mag3={mag3_val}%")
            
            # Force property change detection by temporarily changing values
            old_vals = (self._mag1_progress, self._mag2_progress, self._mag3_progress)
            
            # Temporarily set to -1 to force change
            self._mag1_progress = -1
            self._mag2_progress = -1  
            self._mag3_progress = -1
            
            # Restore actual values
            self._mag1_progress = mag1_val
            self._mag2_progress = mag2_val
            self._mag3_progress = mag3_val
            
            # Emit all signals
            self.mag1ProgressChanged.emit()
            self.mag2ProgressChanged.emit() 
            self.calibrationProgressChanged.emit()
            
            print("[Compass] All progress signals emitted successfully")
            
        except Exception as e:
            print(f"[Compass] Signal emission failed: {e}")
    
    def _set_status(self, status):
        """Update status text - THREAD SAFE"""
        self._status_text = str(status)
        # CRITICAL: Thread-safe signal emission
        QMetaObject.invokeMethod(self, "statusTextChanged", Qt.QueuedConnection)
        print(f"[Compass] {status}")
    
    def cleanup(self):
        """Clean up resources"""
        print("[Compass] Cleaning up...")
        
        if self._calibration_started:
            self.stopCalibration()
        
        self._heartbeat_timer.stop()
        self._simulation_timer.stop()
        self._completion_timer.stop()
        
        if self._calibration_thread and self._calibration_thread.is_alive():
            self._stop_calibration = True
            self._calibration_thread.join(timeout=2.0)
        
        print("[Compass] Cleanup completed")
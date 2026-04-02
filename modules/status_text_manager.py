from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, QTimer
from datetime import datetime
from collections import deque

class StatusTextManager(QObject):
    """Manages status text messages for drone system"""
    
    statusMessageAdded = pyqtSignal(str, str, str)  # timestamp, message, severity
    statusTextReceived = pyqtSignal(str, str)  # (text, severity)

    def __init__(self, drone_model, parent=None):
        super().__init__(parent)
        self.drone_model = drone_model
        self.message_history = deque(maxlen=100)  # Keep last 100 messages
        
        # Track previous states
        self.last_mode = None
        self.last_armed_state = None
        self.last_gps_status = None
        self.last_safety_switch = None
        
        # Setup monitoring timer
        self.monitor_timer = QTimer()
        self.monitor_timer.timeout.connect(self._check_drone_status)
        self.monitor_timer.setInterval(500)  # Check every 500ms
        
        # Connect to drone model signals
        self._connect_signals()
    
    def _connect_signals(self):
        """Connect to drone model signals"""
        if self.drone_model:
            self.drone_model.droneConnectedChanged.connect(self._on_connection_changed)
    
    def start_monitoring(self):
        """Start monitoring drone status"""
        if self.drone_model and self.drone_model.isConnected:
            self.monitor_timer.start()
            self.add_status_message("Status monitoring started", "info")
    
    def stop_monitoring(self):
        """Stop monitoring"""
        self.monitor_timer.stop()
    
    def _on_connection_changed(self):
        """Handle drone connection changes"""
        if self.drone_model.isConnected:
            self.add_status_message("✅ Drone connected", "success")
            self.start_monitoring()
        else:
            self.add_status_message("⚠️ Drone disconnected", "warning")
            self.stop_monitoring()
            # Reset tracked states
            self.last_mode = None
            self.last_armed_state = None
            self.last_gps_status = None
            self.last_safety_switch = None
    
    def _check_drone_status(self):
        """Check drone status and generate messages"""
        if not self.drone_model or not self.drone_model.isConnected:
            return
        
        try:
            # Check mode changes
            self._check_mode_change()
            
            # Check arm/disarm status
            self._check_arm_status()
            
            # Check GPS status
            self._check_gps_status()
            
            # Check safety switch
            self._check_safety_switch()
            
        except Exception as e:
            print(f"❌ Error checking drone status: {e}")
    
    def _check_mode_change(self):
        """Check for flight mode changes"""
        try:
            current_mode = self.drone_model.flightMode
            
            if self.last_mode is not None and current_mode != self.last_mode:
                self.add_status_message(f"🔄 Mode changed: {self.last_mode} → {current_mode}", "info")
            
            self.last_mode = current_mode
        except Exception as e:
            pass
    
    def _check_arm_status(self):
        """Check for arming/disarming"""
        try:
            current_armed = self.drone_model.armed
            
            if self.last_armed_state is not None and current_armed != self.last_armed_state:
                if current_armed:
                    self.add_status_message("🚁 ARMED - Motors enabled", "warning")
                else:
                    self.add_status_message("🛑 DISARMED - Motors disabled", "info")
            
            self.last_armed_state = current_armed
        except Exception as e:
            pass
    
    def _check_gps_status(self):
        """Check GPS status"""
        try:
            telemetry = self.drone_model.telemetry
            
            if 'gps_fix_type' in telemetry and 'satellites_visible' in telemetry:
                gps_fix = telemetry['gps_fix_type']
                sats = telemetry['satellites_visible']
                
                current_status = f"{gps_fix}_{sats}"
                
                if self.last_gps_status != current_status:
                    if gps_fix < 3:
                        self.add_status_message(f"⚠️ GPS: No 3D fix (Sats: {sats})", "warning")
                    elif sats < 10:
                        self.add_status_message(f"⚠️ GPS: Low satellites ({sats})", "warning")
                    elif self.last_gps_status is not None:
                        self.add_status_message(f"✅ GPS: Good fix ({sats} sats)", "success")
                    
                    self.last_gps_status = current_status
        except Exception as e:
            pass
    
    def _check_safety_switch(self):
        """Check safety switch status"""
        try:
            # This depends on your MAVLink implementation
            # You may need to check specific MAVLink messages
            # Example assuming you have safety switch status in telemetry
            if hasattr(self.drone_model, 'safety_switch_enabled'):
                safety_on = self.drone_model.safety_switch_enabled
                
                if self.last_safety_switch is not None and safety_on != self.last_safety_switch:
                    if not safety_on and self.drone_model.armed:
                        self.add_status_message("🚨 SAFETY SWITCH NOT PRESSED!", "error")
                
                self.last_safety_switch = safety_on
        except Exception as e:
            pass
    
    def add_status_message(self, message, severity="info"):
        """Add a status message"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # Store in history
        self.message_history.append({
            'timestamp': timestamp,
            'message': message,
            'severity': severity
        })
        
        # Emit signal
        self.statusMessageAdded.emit(timestamp, message, severity)
        
        # Also log to console
        print(f"[{timestamp}] {message}")
    
    @pyqtSlot(str, str)
    def addCustomMessage(self, message, severity):
        """Slot to add custom message from QML"""
        self.add_status_message(message, severity)
    
    @pyqtSlot(result=str)
    def getMessageHistory(self):
        """Get message history as JSON"""
        import json
        return json.dumps(list(self.message_history))
    
    def cleanup(self):
        """Cleanup resources"""
        self.stop_monitoring()
        self.message_history.clear()
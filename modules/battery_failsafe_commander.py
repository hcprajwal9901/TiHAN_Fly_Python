"""
DroneCommander Battery FailSafe Extension
Production-ready implementation for TiHANFly GCS
Handles ArduPilot battery and RC failsafe parameter configuration via MAVLink

Author: TiHAN Team
Version: 2.0
Last Updated: February 2025

This module provides a mixin class that extends DroneCommander with comprehensive
failsafe functionality for autonomous drone operations.
"""

import time
from PyQt5.QtCore import pyqtSlot
from pymavlink import mavutil


class BatteryFailSafeExtension:
    """
    Mixin class for DroneCommander to add battery and RC failsafe functionality.
    
    This class is designed to be inherited by DroneCommander and provides methods
    for configuring and monitoring various failsafe mechanisms on ArduPilot-based drones.
    
    Required attributes from parent class (DroneCommander):
        - self._drone: MAVLink connection object (pymavlink.mavutil)
        - self._param_lock: Threading lock for parameter access (threading.Lock)
        - self._parameters: Dictionary of cached parameters (dict)
        - self.commandFeedback: PyQt signal for user feedback (pyqtSignal(str))
        - self.parametersUpdated: PyQt signal for parameter updates (pyqtSignal())
        - self.parameterReceived: PyQt signal for single parameter (pyqtSignal(str, float))
        - self._is_drone_ready(): Method to check drone connection status (returns bool)
        - self._send_param_set(): Method to send parameter to drone (returns bool)
    
    Supported Failsafe Types:
        1. Battery Failsafe - Triggered on low/critical battery voltage
        2. RC Failsafe - Triggered on radio control signal loss
        3. GCS Failsafe - Triggered on ground station connection loss
        4. EKF Failsafe - Triggered on Extended Kalman Filter failure
    """
    
    # ═══════════════════════════════════════════════════════════════════════
    # BATTERY FAILSAFE CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════
    
    @pyqtSlot(str, result=bool)
    def setBatteryFailSafe(self, action):
        """
        Configure battery failsafe action when battery is critically low.
        
        This method sets both BATT_FS_LOW_ACT and BATT_FS_CRT_ACT parameters
        on the drone to control what happens when battery voltage drops below
        configured thresholds (BATT_LOW_VOLT and BATT_CRT_VOLT).
        
        Args:
            action (str): One of "None", "RTL", "Land", "Hold"
                - None: Disable battery failsafe (no action taken)
                - RTL: Return to launch point when triggered
                - Land: Land immediately at current position
                - Hold: Maintain current position (same as None for this parameter)
            
        Returns:
            bool: True if both parameters were set successfully, False otherwise
            
        ArduPilot Parameter Mapping:
            BATT_FS_LOW_ACT (triggered at BATT_LOW_VOLT):
                0 = None (disabled)
                1 = Land
                2 = RTL (Return to Launch)
                3 = SmartRTL (intelligent return)
                4 = Terminate (emergency motor stop - USE WITH CAUTION!)
            
            BATT_FS_CRT_ACT (triggered at BATT_CRT_VOLT):
                Same values as BATT_FS_LOW_ACT
        
        Example:
            >>> droneCommander.setBatteryFailSafe("RTL")
            True  # Both parameters set successfully
            
        Side Effects:
            - Sends PARAM_SET MAVLink messages to drone
            - Updates local parameter cache
            - Emits commandFeedback signal with status message
            - Emits parameterReceived signal for each parameter updated
        
        Typical Usage:
            Low battery (10.5V): RTL (go home)
            Critical battery (10.0V): Land (land immediately)
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot set battery failsafe: Drone not connected")
            return False
        
        action = action.strip().upper()
        print(f"[DroneCommander] ⚡ Setting Battery FailSafe to: {action}")
        
        # Map UI action to ArduPilot parameter values
        action_map = {
            "NONE": (0, 0),      # BATT_FS_LOW_ACT=0, BATT_FS_CRT_ACT=0
            "LAND": (1, 1),      # Land on both low and critical
            "RTL": (2, 2),       # RTL on both low and critical
            "HOLD": (0, 0),      # Disable failsafe (stay in place)
        }
        
        if action not in action_map:
            error_msg = f"❌ Invalid battery failsafe action: '{action}'. Use: None, Land, RTL, or Hold"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False
        
        low_action, crit_action = action_map[action]
        
        # Send both parameters in sequence
        success = True
        
        # Set BATT_FS_LOW_ACT (low battery action)
        if not self._send_param_set(b'BATT_FS_LOW_ACT', low_action, 
                                    mavutil.mavlink.MAV_PARAM_TYPE_INT8):
            success = False
            self.commandFeedback.emit(f"⚠️ Failed to set BATT_FS_LOW_ACT")
        else:
            print(f"[DroneCommander] ✅ BATT_FS_LOW_ACT set to {low_action}")
        
        time.sleep(0.2)  # Small delay between parameter sets to avoid overwhelming flight controller
        
        # Set BATT_FS_CRT_ACT (critical battery action)
        if not self._send_param_set(b'BATT_FS_CRT_ACT', crit_action,
                                    mavutil.mavlink.MAV_PARAM_TYPE_INT8):
            success = False
            self.commandFeedback.emit(f"⚠️ Failed to set BATT_FS_CRT_ACT")
        else:
            print(f"[DroneCommander] ✅ BATT_FS_CRT_ACT set to {crit_action}")
        
        if success:
            feedback_msg = f"✅ Battery FailSafe set to: {action}"
            self.commandFeedback.emit(feedback_msg)
            print(f"[DroneCommander] {feedback_msg}")
        
        return success

    # ═══════════════════════════════════════════════════════════════════════
    # RC FAILSAFE CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════
    
    @pyqtSlot(str, result=bool)
    def setRCFailSafe(self, action):
        """
        Configure RC (radio control) failsafe action when RC signal is lost.
        
        This method sets the FS_THR_ENABLE parameter on the drone to control
        what happens when the radio control signal is lost or throttle input
        goes below the configured failsafe threshold.
        
        Args:
            action (str): One of "None", "RTL", "Land", "Hold"
                - None: Disable RC failsafe
                - RTL: Return to launch point
                - Land: Land immediately at current position
                - Hold: Maintain current position (same as None)
            
        Returns:
            bool: True if parameter was set successfully, False otherwise
            
        ArduPilot Parameter Mapping:
            FS_THR_ENABLE (throttle/RC failsafe):
                0 = Disabled (no action on RC loss)
                1 = Always RTL
                2 = Continue with mission in AUTO mode
                3 = Always SmartRTL or RTL
                4 = Always Land
        
        Example:
            >>> droneCommander.setRCFailSafe("RTL")
            True  # Parameter set successfully
            
        Side Effects:
            - Sends PARAM_SET MAVLink message to drone
            - Updates local parameter cache
            - Emits commandFeedback signal with status message
            - Emits parameterReceived signal when updated
        
        Note:
            RC failsafe is typically triggered when:
            - Radio transmitter is turned off
            - Radio signal is out of range
            - Radio battery dies
            - Interference blocks the signal
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot set RC failsafe: Drone not connected")
            return False
        
        action = action.strip().upper()
        print(f"[DroneCommander] 📡 Setting RC FailSafe to: {action}")
        
        # Map UI action to ArduPilot FS_THR_ENABLE values
        action_map = {
            "NONE": 0,    # Disabled
            "RTL": 1,     # Always RTL
            "LAND": 3,    # Always Land
            "HOLD": 0,    # Disabled (drone will hold last mode)
        }
        
        if action not in action_map:
            error_msg = f"❌ Invalid RC failsafe action: '{action}'. Use: None, Land, RTL, or Hold"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False
        
        fs_value = action_map[action]
        
        # Send FS_THR_ENABLE parameter
        success = self._send_param_set(b'FS_THR_ENABLE', fs_value,
                                       mavutil.mavlink.MAV_PARAM_TYPE_INT8)
        
        if success:
            feedback_msg = f"✅ RC FailSafe set to: {action}"
            self.commandFeedback.emit(feedback_msg)
            print(f"[DroneCommander] {feedback_msg}")
        else:
            self.commandFeedback.emit(f"⚠️ Failed to set RC failsafe")
        
        return success

    # ═══════════════════════════════════════════════════════════════════════
    # PARAMETER READING (for UI display)
    # ═══════════════════════════════════════════════════════════════════════
    
    @pyqtSlot(str, result='QVariant')
    def getParameterValue(self, param_name):
        """
        Get current value of a parameter from local cache.
        
        This method reads from the locally cached parameter values that were
        received from the drone. It does not query the drone directly.
        
        Args:
            param_name (str): Parameter name (e.g., 'BATT_FS_LOW_ACT', 'FS_THR_ENABLE')
            
        Returns:
            QVariant: Parameter value as float, or None if not found
            
        Example:
            >>> value = droneCommander.getParameterValue('BATT_FS_LOW_ACT')
            >>> print(value)
            2.0  # RTL action
            
        Note:
            Parameters must be loaded first using requestAllParameters().
            This method is thread-safe and uses parameter lock.
        """
        with self._param_lock:
            if param_name in self._parameters:
                try:
                    return float(self._parameters[param_name]['value'])
                except (ValueError, KeyError):
                    print(f"[DroneCommander] ⚠️ Error getting value for {param_name}")
                    return None
            return None
    
    @pyqtSlot(result=str)
    def getBatteryFailSafeStatus(self):
        """
        Get human-readable battery failsafe status for UI display.
        
        This method reads BATT_FS_LOW_ACT and BATT_FS_CRT_ACT from the parameter
        cache and converts them to a user-friendly status string.
        
        Returns:
            str: Status message describing current battery failsafe configuration
            
        Possible Return Values:
            - "RTL on low, RTL on critical"
            - "Land on low, Land on critical"
            - "None on low, None on critical"
            - "RTL on low, Land on critical" (mixed configuration)
            - "Parameters not loaded" (if cache is empty)
            - "Error reading values" (if parameters exist but can't be parsed)
            
        Example:
            >>> status = droneCommander.getBatteryFailSafeStatus()
            >>> print(status)
            "RTL on low, Land on critical"
            
        Used By:
            QML UI for displaying current failsafe status in FailSafeCard.qml
        """
        try:
            print("[DroneCommander] getBatteryFailSafeStatus() called")
            
            with self._param_lock:
                # Check if parameters exist in cache
                if 'BATT_FS_LOW_ACT' not in self._parameters or 'BATT_FS_CRT_ACT' not in self._parameters:
                    print(f"[DroneCommander] Parameters not found. Available: {list(self._parameters.keys())[:10]}")
                    return "Parameters not loaded"
                
                try:
                    # Read parameter values from cache
                    low_act = int(float(self._parameters['BATT_FS_LOW_ACT']['value']))
                    crt_act = int(float(self._parameters['BATT_FS_CRT_ACT']['value']))
                except (KeyError, ValueError) as e:
                    print(f"[DroneCommander] Error parsing values: {e}")
                    return "Error reading values"
                
                # Map numeric values to human-readable names
                action_names = {
                    0: "None", 
                    1: "Land", 
                    2: "RTL", 
                    3: "SmartRTL", 
                    4: "Terminate"
                }
                
                low_name = action_names.get(low_act, "Unknown")
                crt_name = action_names.get(crt_act, "Unknown")
                
                result = f"{low_name} on low, {crt_name} on critical"
                print(f"[DroneCommander] Battery FS: {result}")
                return result
                
        except Exception as e:
            print(f"[DroneCommander] ❌ Error getting battery FS status: {e}")
            import traceback
            traceback.print_exc()
            return "Error reading status"
    
    @pyqtSlot(result=str)
    def getRCFailSafeStatus(self):
        """
        Get human-readable RC failsafe status for UI display.
        
        This method reads FS_THR_ENABLE from the parameter cache and converts
        it to a user-friendly status string.
        
        Returns:
            str: Status message describing current RC failsafe configuration
            
        Possible Return Values:
            - "Disabled"
            - "RTL on RC loss"
            - "Land on RC loss"
            - "Continue AUTO on RC loss"
            - "SmartRTL on RC loss"
            - "Parameters not loaded" (if cache is empty)
            - "Error reading value" (if parameter exists but can't be parsed)
            
        Example:
            >>> status = droneCommander.getRCFailSafeStatus()
            >>> print(status)
            "RTL on RC loss"
            
        Used By:
            QML UI for displaying current RC failsafe status in FailSafeCard.qml
        """
        try:
            print("[DroneCommander] getRCFailSafeStatus() called")
            
            with self._param_lock:
                # Check if parameter exists in cache
                if 'FS_THR_ENABLE' not in self._parameters:
                    print(f"[DroneCommander] FS_THR_ENABLE not found. Available: {list(self._parameters.keys())[:10]}")
                    return "Parameters not loaded"
                
                try:
                    # Read parameter value from cache
                    fs_thr = int(float(self._parameters['FS_THR_ENABLE']['value']))
                except (KeyError, ValueError) as e:
                    print(f"[DroneCommander] Error parsing value: {e}")
                    return "Error reading value"
                
                # Map numeric values to human-readable names
                status_names = {
                    0: "Disabled",
                    1: "RTL on RC loss",
                    2: "Continue AUTO on RC loss",
                    3: "Land on RC loss",
                    4: "SmartRTL on RC loss",
                    5: "SmartRTL or Land on RC loss"
                }
                
                result = status_names.get(fs_thr, "Unknown")
                print(f"[DroneCommander] RC FS: {result}")
                return result
                
        except Exception as e:
            print(f"[DroneCommander] ❌ Error getting RC FS status: {e}")
            import traceback
            traceback.print_exc()
            return "Error reading status"

    # ═══════════════════════════════════════════════════════════════════════
    # ADVANCED FAILSAFE CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════
    
    @pyqtSlot(result=bool)
    def configureAllFailSafes(self):
        """
        Configure all failsafe parameters to safe recommended defaults.
        
        This is a convenience method that sets multiple failsafe parameters
        at once with sensible defaults for safe drone operation. This is useful
        for initial setup or resetting failsafes to known-good values.
        
        Parameters Configured:
            Battery Failsafe:
                - BATT_FS_LOW_ACT = 2 (RTL on low battery)
                - BATT_FS_CRT_ACT = 1 (Land on critical battery)
                - BATT_LOW_VOLT = 10.5V (low battery threshold for 3S LiPo)
                - BATT_CRT_VOLT = 10.0V (critical battery threshold for 3S LiPo)
            
            RC Failsafe:
                - FS_THR_ENABLE = 1 (RTL on RC signal loss)
            
            GCS Failsafe:
                - FS_GCS_ENABLE = 0 (Disabled - don't trigger on ground station loss)
            
            EKF Failsafe:
                - FS_EKF_ACTION = 1 (Land on Extended Kalman Filter failure)
                - FS_EKF_THRESH = 0.8 (EKF variance threshold)
        
        Returns:
            bool: True if all parameters set successfully, False if any failed
            
        Example:
            >>> success = droneCommander.configureAllFailSafes()
            >>> if success:
            ...     print("All failsafes configured!")
            All failsafes configured!
            
        Side Effects:
            - Sends multiple PARAM_SET MAVLink messages
            - Updates local parameter cache
            - Emits commandFeedback signal with progress messages
            - Takes approximately 3-4 seconds to complete (8 parameters × 0.3s delay)
        
        Note:
            Battery voltage thresholds (10.5V/10.0V) are suitable for 3S LiPo.
            For 4S LiPo, you may want to set: low=14.0V, critical=13.2V
            For 6S LiPo, you may want to set: low=21.0V, critical=19.8V
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Drone not connected")
            return False
        
        self.commandFeedback.emit("⚙️ Configuring failsafe parameters...")
        print("[DroneCommander] 🔧 Setting recommended failsafe configuration...")
        print("=" * 60)
        
        # Define safe parameter configuration
        failsafe_params = {
            # Battery Failsafe
            b'BATT_FS_LOW_ACT': (2, mavutil.mavlink.MAV_PARAM_TYPE_INT8),     # RTL on low
            b'BATT_FS_CRT_ACT': (1, mavutil.mavlink.MAV_PARAM_TYPE_INT8),     # Land on critical
            b'BATT_LOW_VOLT': (10.5, mavutil.mavlink.MAV_PARAM_TYPE_REAL32),  # 10.5V threshold
            b'BATT_CRT_VOLT': (10.0, mavutil.mavlink.MAV_PARAM_TYPE_REAL32),  # 10.0V critical
            
            # RC Failsafe
            b'FS_THR_ENABLE': (1, mavutil.mavlink.MAV_PARAM_TYPE_INT8),       # RTL on RC loss
            
            # GCS Failsafe
            b'FS_GCS_ENABLE': (0, mavutil.mavlink.MAV_PARAM_TYPE_INT8),       # Disabled
            
            # EKF Failsafe
            b'FS_EKF_ACTION': (1, mavutil.mavlink.MAV_PARAM_TYPE_INT8),       # Land on EKF failure
            b'FS_EKF_THRESH': (0.8, mavutil.mavlink.MAV_PARAM_TYPE_REAL32),   # Threshold
        }
        
        success_count = 0
        total_params = len(failsafe_params)
        
        for param_id, (value, param_type) in failsafe_params.items():
            param_name = param_id.decode('utf-8')
            
            if self._send_param_set(param_id, value, param_type, timeout=5.0):
                success_count += 1
                print(f"[DroneCommander]   ✓ {param_name:20s} = {value}")
            else:
                print(f"[DroneCommander]   ✗ {param_name:20s} FAILED")
            
            time.sleep(0.3)  # Delay between parameters to avoid overwhelming flight controller
        
        print("=" * 60)
        
        # Report results
        if success_count == total_params:
            msg = f"✅ All {total_params} failsafe parameters configured successfully"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return True
        elif success_count > 0:
            msg = f"⚠️ Partial success: {success_count}/{total_params} parameters set"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return False
        else:
            msg = "❌ Failed to configure failsafe parameters"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return False
    
    @pyqtSlot(float, float, result=bool)
    def setBatteryVoltageThresholds(self, low_voltage, critical_voltage):
        """
        Set custom battery voltage thresholds for failsafe activation.
        
        This method allows you to customize when battery failsafes are triggered
        based on your specific battery configuration (3S, 4S, 6S LiPo, etc.).
        
        Args:
            low_voltage (float): Voltage threshold for low battery action (e.g., 10.5)
                When battery drops below this, BATT_FS_LOW_ACT is triggered
            critical_voltage (float): Voltage threshold for critical battery action (e.g., 10.0)
                When battery drops below this, BATT_FS_CRT_ACT is triggered
            
        Returns:
            bool: True if both thresholds were set successfully, False otherwise
            
        Example:
            >>> # For 3S LiPo (11.1V nominal)
            >>> droneCommander.setBatteryVoltageThresholds(10.5, 10.0)
            True
            
            >>> # For 4S LiPo (14.8V nominal)
            >>> droneCommander.setBatteryVoltageThresholds(14.0, 13.2)
            True
            
            >>> # For 6S LiPo (22.2V nominal)
            >>> droneCommander.setBatteryVoltageThresholds(21.0, 19.8)
            True
            
        Validation:
            - Critical voltage must be lower than low voltage
            - Both values should be positive
            
        LiPo Voltage Guide:
            3S (11.1V): low=10.5V (3.5V/cell), critical=10.0V (3.33V/cell)
            4S (14.8V): low=14.0V (3.5V/cell), critical=13.2V (3.3V/cell)
            6S (22.2V): low=21.0V (3.5V/cell), critical=19.8V (3.3V/cell)
            
        Note:
            Never discharge LiPo below 3.0V per cell to avoid permanent damage.
            Typical safe minimums: 3.3V/cell (critical), 3.5V/cell (low warning)
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Drone not connected")
            return False
        
        # Validation
        if critical_voltage >= low_voltage:
            error_msg = "❌ Critical voltage must be lower than low voltage"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False
        
        if low_voltage <= 0 or critical_voltage <= 0:
            error_msg = "❌ Voltage values must be positive"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False
        
        print(f"[DroneCommander] 🔋 Setting battery thresholds: Low={low_voltage}V, Critical={critical_voltage}V")
        
        success = True
        
        # Set low voltage threshold
        if not self._send_param_set(b'BATT_LOW_VOLT', low_voltage,
                                    mavutil.mavlink.MAV_PARAM_TYPE_REAL32):
            success = False
            self.commandFeedback.emit("⚠️ Failed to set BATT_LOW_VOLT")
            print("[DroneCommander]   ✗ BATT_LOW_VOLT failed")
        else:
            print(f"[DroneCommander]   ✓ BATT_LOW_VOLT = {low_voltage}V")
        
        time.sleep(0.2)
        
        # Set critical voltage threshold
        if not self._send_param_set(b'BATT_CRT_VOLT', critical_voltage,
                                    mavutil.mavlink.MAV_PARAM_TYPE_REAL32):
            success = False
            self.commandFeedback.emit("⚠️ Failed to set BATT_CRT_VOLT")
            print("[DroneCommander]   ✗ BATT_CRT_VOLT failed")
        else:
            print(f"[DroneCommander]   ✓ BATT_CRT_VOLT = {critical_voltage}V")
        
        if success:
            msg = f"✅ Battery thresholds set: Low={low_voltage}V, Critical={critical_voltage}V"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
        
        return success
    
    @pyqtSlot(result='QVariantMap')
    def getAllFailSafeSettings(self):
        """
        Get all current failsafe settings as a dictionary.
        
        This method retrieves all failsafe-related parameters from the local
        cache and returns them in a structured format suitable for QML display.
        
        Returns:
            QVariantMap: Dictionary containing all failsafe parameter values
            
        Dictionary Keys:
            - battery_low_action: BATT_FS_LOW_ACT value (0-4)
            - battery_crit_action: BATT_FS_CRT_ACT value (0-4)
            - battery_low_volt: BATT_LOW_VOLT value (volts)
            - battery_crit_volt: BATT_CRT_VOLT value (volts)
            - rc_failsafe: FS_THR_ENABLE value (0-4)
            - gcs_failsafe: FS_GCS_ENABLE value (0-1)
            - ekf_action: FS_EKF_ACTION value (0-2)
            - ekf_threshold: FS_EKF_THRESH value (0.0-1.0)
            
        Example Return Value:
            {
                'battery_low_action': 2.0,      # RTL
                'battery_crit_action': 1.0,     # Land
                'battery_low_volt': 10.5,       # 10.5V
                'battery_crit_volt': 10.0,      # 10.0V
                'rc_failsafe': 1.0,             # RTL on RC loss
                'gcs_failsafe': 0.0,            # Disabled
                'ekf_action': 1.0,              # Land on EKF failure
                'ekf_threshold': 0.8            # 0.8 threshold
            }
            
        Example Usage in QML:
```qml
            var settings = droneCommander.getAllFailSafeSettings()
            if (settings.battery_low_action === 2) {
                console.log("Battery failsafe: RTL")
            }
```
            
        Note:
            Values will be None/null if parameters haven't been loaded yet.
            Use requestAllParameters() first to populate the cache.
        """
        settings = {}
        
        with self._param_lock:
            # Define parameter mapping
            param_map = {
                'battery_low_action': 'BATT_FS_LOW_ACT',
                'battery_crit_action': 'BATT_FS_CRT_ACT',
                'battery_low_volt': 'BATT_LOW_VOLT',
                'battery_crit_volt': 'BATT_CRT_VOLT',
                'rc_failsafe': 'FS_THR_ENABLE',
                'gcs_failsafe': 'FS_GCS_ENABLE',
                'ekf_action': 'FS_EKF_ACTION',
                'ekf_threshold': 'FS_EKF_THRESH'
            }
            
            # Read each parameter from cache
            for key, param_name in param_map.items():
                if param_name in self._parameters:
                    try:
                        settings[key] = float(self._parameters[param_name]['value'])
                    except (ValueError, KeyError):
                        settings[key] = None
                        print(f"[DroneCommander] ⚠️ Error reading {param_name}")
                else:
                    settings[key] = None
        
        print(f"[DroneCommander] All failsafe settings retrieved: {len([v for v in settings.values() if v is not None])}/{len(settings)} parameters available")
        return settings
    
    # ═══════════════════════════════════════════════════════════════════════
    # GCS FAILSAFE CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════
    
    @pyqtSlot(bool, result=bool)
    def setGCSFailSafe(self, enabled):
        """
        Enable or disable Ground Control Station (GCS) failsafe.
        
        GCS failsafe triggers when the drone loses connection with the ground
        control station (this software). This is typically disabled to avoid
        triggering during normal operations.
        
        Args:
            enabled (bool): True to enable GCS failsafe, False to disable
            
        Returns:
            bool: True if parameter was set successfully
            
        ArduPilot Parameter:
            FS_GCS_ENABLE:
                0 = Disabled
                1 = Enabled (RTL on GCS connection loss)
                
        Example:
            >>> droneCommander.setGCSFailSafe(False)  # Disable GCS failsafe
            True
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Drone not connected")
            return False
        
        value = 1 if enabled else 0
        action_text = "Enabled" if enabled else "Disabled"
        
        print(f"[DroneCommander] 🖥️ Setting GCS FailSafe to: {action_text}")
        
        success = self._send_param_set(b'FS_GCS_ENABLE', value,
                                       mavutil.mavlink.MAV_PARAM_TYPE_INT8)
        
        if success:
            msg = f"✅ GCS FailSafe {action_text}"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
        else:
            self.commandFeedback.emit("⚠️ Failed to set GCS failsafe")
        
        return success
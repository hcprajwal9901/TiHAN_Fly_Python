from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer
from pymavlink import mavutil
import time
import math


class RadioCalibrationModel(QObject):
    calibrationStatusChanged = pyqtSignal()
    calibrationProgressChanged = pyqtSignal()
    radioChannelsChanged = pyqtSignal()
    statusMessageChanged = pyqtSignal()

    def __init__(self, drone_model):
        super().__init__()
        self._drone_model = drone_model
        self._calibration_active = False
        self._calibration_step = 0  # 0: not started, 1: move to extremes, 2: center sticks, 3: complete
        self._calibration_progress = 0
        self._status_message = "Ready for radio calibration"

        # Radio channel data (PWM values) - support up to 18 channels
        # Initialize with standard RC values (1500 center, except throttle at 1000)
        self._radio_channels = [1500] * 18
        self._radio_channels[2] = 1000  # Throttle starts at minimum

        # Calibration values
        self._channel_min = [1500] * 18      # Start with center values
        self._channel_max = [1500] * 18      # Start with center values
        self._channel_trim = [1500] * 18     # Center/trim values

        # Initialize throttle properly
        self._channel_min[2] = 1000          # Throttle minimum
        self._channel_trim[2] = 1000         # Throttle trim at minimum

        # Calibration parameters
        self._calibration_timeout = 60       # 60 seconds timeout for each step
        self._samples_collected = 0
        self._required_samples = 50          # Samples needed for each step
        self._step1_samples = 0              # Samples for extreme positions
        self._step2_samples = 0              # Samples for center positions

        # Min/max tracking for step 1 (extreme positions)
        self._step1_min = [2000] * 18        # Track minimum values seen
        self._step1_max = [1000] * 18        # Track maximum values seen

        # Channel mapping - ArduPilot standard:
        # Ch1: Roll (Aileron)  Ch2: Pitch (Elevator)
        # Ch3: Throttle        Ch4: Yaw (Rudder)
        self._channel_names = [
            "Roll (Ch1)", "Pitch (Ch2)", "Throttle (Ch3)", "Yaw (Ch4)",
            "Channel 5", "Channel 6", "Channel 7", "Channel 8",
            "Channel 9", "Channel 10", "Channel 11", "Channel 12",
            "Channel 13", "Channel 14", "Channel 15", "Channel 16",
            "Channel 17", "Channel 18"
        ]

        # ── timers ────────────────────────────────────────────────────────
        # _update_timer is kept as a fallback polling mechanism.
        # Primary data path: RC_CHANNELS are pushed via on_rc_channels_message()
        # by MAVLinkThread so we don't compete for serial data.
        self._update_timer = QTimer()
        self._update_timer.timeout.connect(self._update_radio_channels)

        self._calibration_timer = QTimer()
        self._calibration_timer.timeout.connect(self._calibration_timeout_handler)

        self._step_timer = QTimer()
        self._step_timer.timeout.connect(self._check_step_completion)

        print("[RadioCalibrationModel] Initialized with proper channel mapping")

    # ── properties ────────────────────────────────────────────────────────

    @pyqtProperty(bool, notify=calibrationStatusChanged)
    def calibrationActive(self):
        return self._calibration_active

    @pyqtProperty(int, notify=calibrationProgressChanged)
    def calibrationProgress(self):
        return self._calibration_progress

    @pyqtProperty(int, notify=calibrationStatusChanged)
    def calibrationStep(self):
        return self._calibration_step

    @pyqtProperty(str, notify=statusMessageChanged)
    def statusMessage(self):
        return self._status_message

    @pyqtProperty('QVariantList', notify=radioChannelsChanged)
    def radioChannels(self):
        return self._radio_channels[:12]  # Return first 12 channels for UI

    @pyqtProperty(bool, notify=calibrationStatusChanged)
    def isDroneConnected(self):
        return self._drone_model.isConnected if self._drone_model else False

    # ── internal helpers ──────────────────────────────────────────────────

    def _set_status_message(self, message):
        if self._status_message != message:
            self._status_message = message
            print(f"[RadioCalibration] {message}")
            self.statusMessageChanged.emit()

    def _set_calibration_progress(self, progress):
        clamped = max(0, min(100, progress))
        if self._calibration_progress != clamped:
            self._calibration_progress = clamped
            self.calibrationProgressChanged.emit()

    # ── PUBLIC SLOTS called by MAVLinkThread ──────────────────────────────

    @pyqtSlot(object)
    def on_rc_channels_message(self, msg):
        """
        Called by MAVLinkThread whenever an RC_CHANNELS message arrives.
        This is the primary data path and replaces the old recv_match() polling
        loop so we never compete with MAVLinkThread for serial data.
        Also updates display values even when calibration is not active.
        """
        new_channels = self._extract_channels(msg)

        if not self._calibration_active:
            # Keep display values live even outside of calibration
            if any(v > 0 for v in new_channels[:4]):
                self._radio_channels = new_channels
                self.radioChannelsChanged.emit()
            return

        channels_updated = 0
        for i, value in enumerate(new_channels):
            if 900 < value < 2200:          # valid PWM range
                self._radio_channels[i] = value
                channels_updated += 1

                if self._calibration_step == 1:
                    if value < self._step1_min[i]:
                        self._step1_min[i] = value
                        print(f"[RadioCalibration] {self._channel_names[i]} new minimum: {value}")
                    if value > self._step1_max[i]:
                        self._step1_max[i] = value
                        print(f"[RadioCalibration] {self._channel_names[i]} new maximum: {value}")

        if channels_updated >= 4:
            self._samples_collected += 1
            if self._calibration_step == 1:
                self._step1_samples += 1
            elif self._calibration_step == 2:
                self._step2_samples += 1
            self.radioChannelsChanged.emit()

    @pyqtSlot(object)
    def on_rc_channels_raw_message(self, msg):
        """
        Fallback for older RC_CHANNELS_RAW message format (8 channels only).
        Synthesises a fake RC_CHANNELS-style object so on_rc_channels_message
        can process it uniformly.
        """
        class FakeMsg:
            pass

        fake = FakeMsg()
        attrs = [
            'chan1_raw', 'chan2_raw', 'chan3_raw', 'chan4_raw',
            'chan5_raw', 'chan6_raw', 'chan7_raw', 'chan8_raw',
        ]
        for attr in attrs:
            setattr(fake, attr, getattr(msg, attr, 0))

        # Fill channels 9-18 with 0 (not present in RC_CHANNELS_RAW)
        for i in range(9, 19):
            setattr(fake, f'chan{i}_raw', 0)

        self.on_rc_channels_message(fake)

    @staticmethod
    def _extract_channels(msg):
        """Pull all 18 channel raw values from an RC_CHANNELS message."""
        return [
            msg.chan1_raw, msg.chan2_raw, msg.chan3_raw, msg.chan4_raw,
            msg.chan5_raw, msg.chan6_raw, msg.chan7_raw, msg.chan8_raw,
            msg.chan9_raw, msg.chan10_raw, msg.chan11_raw, msg.chan12_raw,
            msg.chan13_raw, msg.chan14_raw, msg.chan15_raw, msg.chan16_raw,
            msg.chan17_raw, msg.chan18_raw,
        ]

    # ── calibration flow ──────────────────────────────────────────────────

    @pyqtSlot()
    def startCalibration(self):
        """Start radio calibration process following Mission Planner workflow"""
        if not self.isDroneConnected:
            self._set_status_message("Cannot start calibration - drone not connected")
            return False

        if self._calibration_active:
            self._set_status_message("Calibration already in progress")
            return False

        print("[RadioCalibration] Starting Mission Planner style radio calibration...")

        self._calibration_active = True
        self._calibration_step = 1
        self._calibration_progress = 0
        self._samples_collected = 0
        self._step1_samples = 0
        self._step2_samples = 0

        # Seed calibration bounds from current live channel readings.
        # Fall back to _get_current_radio_values() if _radio_channels are stale.
        current_values = self._get_current_radio_values()
        for i in range(18):
            v = self._radio_channels[i] if self._radio_channels[i] > 0 else current_values[i]
            if v <= 0:
                v = 1000 if i == 2 else 1500
            self._channel_min[i] = v
            self._channel_max[i] = v
            self._channel_trim[i] = v
            self._step1_min[i] = v
            self._step1_max[i] = v

        # Special handling for throttle (channel 3, index 2)
        self._channel_min[2] = min(self._channel_min[2], 1000)
        self._channel_trim[2] = self._channel_min[2]

        self._set_status_message("Step 1: Move all sticks, knobs and switches to their extreme positions")

        # Request 50 Hz RC_CHANNELS during calibration for responsive capture
        self._request_rc_rate(50)

        # _update_timer kept as polling fallback (lower priority than push path)
        self._update_timer.start(20)
        self._calibration_timer.start(self._calibration_timeout * 1000)
        self._step_timer.start(100)

        self.calibrationStatusChanged.emit()
        return True

    @pyqtSlot()
    def stopCalibration(self):
        """Stop radio calibration process"""
        print("[RadioCalibration] Stopping radio calibration...")

        if self._calibration_active:
            # Restore normal 5 Hz RC_CHANNELS stream
            self._request_rc_rate(5)

        self._calibration_active = False
        self._calibration_step = 0
        self._calibration_progress = 0

        self._update_timer.stop()
        self._calibration_timer.stop()
        self._step_timer.stop()

        self._set_status_message("Radio calibration stopped")
        self.calibrationStatusChanged.emit()

    @pyqtSlot()
    def nextCalibrationStep(self):
        """Advance to next calibration step - called from UI dialogs"""
        if not self._calibration_active:
            return

        if self._calibration_step == 1:
            print("[RadioCalibration] Step 1 complete - captured extreme positions")

            # Commit extreme values captured in step 1
            for i in range(18):
                self._channel_min[i] = self._step1_min[i]
                self._channel_max[i] = self._step1_max[i]
                rng = abs(self._channel_max[i] - self._channel_min[i])
                if rng < 100:
                    print(f"[RadioCalibration WARNING] {self._channel_names[i]} small range: {rng}us")

            self._calibration_step = 2
            self._step2_samples = 0
            self._set_calibration_progress(66)
            self._set_status_message("Step 2: Center all sticks and set throttle to minimum")

            self._calibration_timer.stop()
            self._calibration_timer.start(self._calibration_timeout * 1000)

        elif self._calibration_step == 2:
            print("[RadioCalibration] Step 2 complete - captured center positions")

            for i in range(18):
                if i == 2:  # Throttle: trim at minimum
                    self._channel_trim[i] = self._channel_min[i]
                    print(f"[RadioCalibration] Throttle trim set to minimum: {self._channel_trim[i]}")
                else:
                    self._channel_trim[i] = self._radio_channels[i]
                    print(f"[RadioCalibration] {self._channel_names[i]} trim: {self._channel_trim[i]}")

            self._calibration_step = 3
            self._set_calibration_progress(100)
            self._set_status_message("Calibration complete - Review values and save settings")
            self._complete_calibration()

        self.calibrationStatusChanged.emit()

    @pyqtSlot()
    def saveCalibration(self):
        """Save radio calibration parameters to drone"""
        if not self.isDroneConnected:
            self._set_status_message("Cannot save - drone not connected")
            return False

        if self._calibration_step != 3:
            self._set_status_message("Complete calibration process first")
            return False

        print("[RadioCalibration] Saving radio calibration parameters...")
        self._set_status_message("Saving radio calibration parameters...")

        try:
            if not self._validate_calibration_data():
                self._set_status_message("Invalid calibration data - please recalibrate")
                return False

            self._save_rc_parameters()
            self._display_calibration_summary()
            self.stopCalibration()
            self._set_status_message("Radio calibration saved successfully")
            return True

        except Exception as e:
            print(f"[RadioCalibration ERROR] Failed to save calibration: {e}")
            self._set_status_message(f"Failed to save calibration: {e}")
            return False

    # ── MAVLink helpers ───────────────────────────────────────────────────

    def _request_rc_rate(self, hz):
        """
        Ask the autopilot to stream RC_CHANNELS at the given rate.
        Replaces the old _start_rc_calibration_mavlink / _stop_rc_calibration_mavlink pair.
        """
        conn = self._drone_model.drone_connection
        if not conn:
            return
        interval_us = int(1_000_000 / hz)
        try:
            conn.mav.command_long_send(
                conn.target_system,
                conn.target_component,
                mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
                0,
                mavutil.mavlink.MAVLINK_MSG_ID_RC_CHANNELS,
                interval_us,
                0, 0, 0, 0, 0,
            )
            print(f"[RadioCalibration] Requested RC_CHANNELS at {hz} Hz (interval {interval_us} µs)")
        except Exception as e:
            print(f"[RadioCalibration ERROR] Failed to set RC rate: {e}")

    # Kept for backward compatibility / direct polling fallback
    def _start_rc_calibration_mavlink(self):
        self._request_rc_rate(50)

    def _stop_rc_calibration_mavlink(self):
        self._request_rc_rate(5)

    def _get_current_radio_values(self):
        """
        Get current radio channel values directly from drone via recv_match().
        Used as seed values at calibration start; normal data path is push-based.
        """
        current_values = [0] * 18

        if not self._drone_model.drone_connection:
            return current_values

        try:
            connection = self._drone_model.drone_connection
            msg = connection.recv_match(type='RC_CHANNELS', blocking=False, timeout=0.1)

            if msg:
                current_values = self._extract_channels(msg)
                print(
                    f"[RadioCalibration] Seed values - "
                    f"Ch1:{current_values[0]}, Ch2:{current_values[1]}, "
                    f"Ch3:{current_values[2]}, Ch4:{current_values[3]}"
                )

        except Exception as e:
            print(f"[RadioCalibration] Could not get current radio values: {e}")

        return current_values

    def _update_radio_channels(self):
        """
        Polling fallback: called by _update_timer every 20 ms.
        The primary path is on_rc_channels_message() pushed by MAVLinkThread.
        This only fires if the push path hasn't delivered data recently.
        """
        if not self._calibration_active or not self._drone_model.drone_connection:
            return

        try:
            connection = self._drone_model.drone_connection
            msg = connection.recv_match(type='RC_CHANNELS', blocking=False, timeout=0.01)
            if msg:
                self.on_rc_channels_message(msg)
        except Exception as e:
            print(f"[RadioCalibration ERROR] Failed to update radio channels: {e}")

    def _save_rc_parameters(self):
        """Save RC calibration parameters to drone using MAVLink parameter protocol"""
        conn = self._drone_model.drone_connection
        if not conn:
            raise Exception("No drone connection available")

        saved = 0
        for i in range(8):
            ch = i + 1
            for suffix, val in [("MIN", self._channel_min[i]),
                                  ("MAX", self._channel_max[i]),
                                  ("TRIM", self._channel_trim[i])]:
                param_name = f"RC{ch}_{suffix}"
                if val > 0:
                    try:
                        conn.mav.param_set_send(
                            conn.target_system,
                            conn.target_component,
                            param_name.encode()[:16],
                            float(val),
                            mavutil.mavlink.MAV_PARAM_TYPE_INT16,
                        )
                        print(f"[RadioCalibration] Set {param_name} = {val}")
                        saved += 1
                        time.sleep(0.05)
                    except Exception as e:
                        print(f"[RadioCalibration ERROR] Failed to set {param_name}: {e}")

        print(f"[RadioCalibration] Saved {saved} RC parameters to drone")

        # Write to EEPROM
        try:
            conn.mav.command_long_send(
                conn.target_system, conn.target_component,
                mavutil.mavlink.MAV_CMD_PREFLIGHT_STORAGE,
                0, 1, 0, 0, 0, 0, 0, 0,
            )
            print("[RadioCalibration] Sent PREFLIGHT_STORAGE (write to EEPROM)")
        except Exception as e:
            print(f"[RadioCalibration ERROR] PREFLIGHT_STORAGE failed: {e}")

    # ── step helpers ──────────────────────────────────────────────────────

    def _check_step_completion(self):
        """Check if current calibration step has enough samples"""
        if not self._calibration_active:
            return

        if self._calibration_step == 1:
            ranges_detected = 0
            for i in range(4):  # Check first 4 main channels
                rng = abs(self._step1_max[i] - self._step1_min[i])
                if rng > 300:   # Good range (>300 µs)
                    ranges_detected += 1

            progress = min(60, (ranges_detected / 4.0) * 60)
            self._set_calibration_progress(int(progress))

            if ranges_detected > 0:
                self._set_status_message(
                    f"Step 1: {ranges_detected}/4 channels have good range - Continue moving sticks!"
                )

        elif self._calibration_step == 2:
            self._step2_samples += 1
            if self._step2_samples >= self._required_samples:
                progress = 66 + min(33, (self._step2_samples / self._required_samples) * 33)
                self._set_calibration_progress(int(progress))

    def _complete_calibration(self):
        """Complete the calibration process"""
        print("[RadioCalibration] Completing calibration...")

        self._step_timer.stop()
        self._calibration_timer.stop()

        for i in range(18):
            # Ensure min < max
            if self._channel_min[i] > self._channel_max[i]:
                self._channel_min[i], self._channel_max[i] = \
                    self._channel_max[i], self._channel_min[i]

            # Clamp trim within [min, max]
            self._channel_trim[i] = max(
                self._channel_min[i],
                min(self._channel_max[i], self._channel_trim[i])
            )

            # Throttle trim always at minimum
            if i == 2:
                self._channel_trim[i] = self._channel_min[i]

        self._display_calibration_summary()

    def _validate_calibration_data(self):
        """Validate calibration data similar to Mission Planner checks"""
        valid = True

        for i in range(8):
            mn, mx, tr = self._channel_min[i], self._channel_max[i], self._channel_trim[i]
            rng = abs(mx - mn)
            name = self._channel_names[i]

            # Range check (warn at <200 µs, fail at <100 µs)
            if rng < 200:
                print(f"[RadioCalibration WARNING] {name} has insufficient range: {rng}us")
            if rng < 100:
                valid = False

            # Absolute PWM bounds (warn at 800-2200, fail outside 700-2300)
            if mn < 800 or mx > 2200:
                print(f"[RadioCalibration WARNING] {name} near limits: min={mn}, max={mx}")
            if mn < 700 or mx > 2300:
                valid = False
                print(f"[RadioCalibration WARNING] {name} out of range: min={mn}, max={mx}")

            # Trim must be within [min, max]
            if tr < mn or tr > mx:
                print(f"[RadioCalibration WARNING] {name} trim {tr} out of [{mn},{mx}], fixing")
                self._channel_trim[i] = mn if i == 2 else (mn + mx) // 2

        return valid

    def _display_calibration_summary(self):
        """Display calibration summary like Mission Planner"""
        print("\n[RadioCalibration] ===== CALIBRATION SUMMARY =====")
        for i in range(8):
            mn, mx, tr = self._channel_min[i], self._channel_max[i], self._channel_trim[i]
            print(f"  {self._channel_names[i]:15}: Min={mn:4d}  Max={mx:4d}  Trim={tr:4d}  Range={mx-mn:3d}us")
        print("=============================================\n")

    def _calibration_timeout_handler(self):
        """Handle calibration timeout"""
        print(f"[RadioCalibration] Step {self._calibration_step} timeout reached")
        self._set_status_message(f"Step {self._calibration_step} timeout - please try again")
        # Don't auto-stop; let user decide
        self._calibration_timer.stop()

    # ── channel info for QML ──────────────────────────────────────────────

    @pyqtSlot(result='QVariantList')
    def getChannelInfo(self):
        """Get detailed channel information for UI with proper channel mapping"""
        channel_info = []

        for i in range(12):
            if self._calibration_step >= 1 and self._calibration_active:
                mn = self._step1_min[i] if self._step1_min[i] < 1900 else self._channel_min[i]
                mx = self._step1_max[i] if self._step1_max[i] > 1100 else self._channel_max[i]
            else:
                mn, mx = self._channel_min[i], self._channel_max[i]

            channel_info.append({
                'name': self._channel_names[i],
                'current': self._radio_channels[i],
                'min': mn,
                'max': mx,
                'trim': self._channel_trim[i],
                'active': 900 < self._radio_channels[i] < 2200,
            })

        return channel_info

    # ── Spektrum bind ─────────────────────────────────────────────────────

    @pyqtSlot(str)
    def bindSpectrum(self, bind_type):
        """Initiate Spektrum receiver binding"""
        if not self.isDroneConnected:
            self._set_status_message("Cannot bind - drone not connected")
            return

        if self._calibration_active:
            self._set_status_message("Cannot bind during calibration - stop calibration first")
            return

        print(f"[RadioCalibration] Starting Spektrum {bind_type} bind process")
        self._set_status_message(f"Binding {bind_type} - Put receiver in bind mode now")

        bind_map = {'DSM2': 0, 'DSMX': 1, 'DSME': 2}
        bind_value = bind_map.get(bind_type, 1)

        try:
            conn = self._drone_model.drone_connection
            conn.mav.command_long_send(
                conn.target_system, conn.target_component,
                mavutil.mavlink.MAV_CMD_START_RX_PAIR,
                0, bind_value, 0, 0, 0, 0, 0, 0,
            )
            print(f"[RadioCalibration] {bind_type} bind command sent")
            QTimer.singleShot(
                8000,
                lambda: self._set_status_message(f"{bind_type} bind complete - Check receiver LED status")
            )
        except Exception as e:
            print(f"[RadioCalibration ERROR] {bind_type} bind failed: {e}")
            self._set_status_message(f"Failed to initiate {bind_type} bind: {e}")

    # ── cleanup ───────────────────────────────────────────────────────────

    def cleanup(self):
        """Clean up resources"""
        print("[RadioCalibrationModel] Cleaning up resources...")

        if self._calibration_active:
            self.stopCalibration()

        for t in [self._update_timer, self._calibration_timer, self._step_timer]:
            if t:
                t.stop()

        print("[RadioCalibrationModel] Cleanup completed")
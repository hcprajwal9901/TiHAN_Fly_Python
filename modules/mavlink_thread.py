import math
import time
from PyQt5.QtCore import pyqtSignal, QThread
from pymavlink import mavutil


class MAVLinkThread(QThread):
    telemetryUpdated = pyqtSignal(dict)
    statusTextChanged = pyqtSignal(str)

    def __init__(self, drone, drone_commander=None):
        super().__init__()
        self.drone = drone
        self.drone_commander = drone_commander
        self.running = True
        self._msg_callbacks = []

        self.current_telemetry_components = {
            'mode': "UNKNOWN",
            'armed': False,
            'lat': 0.0,
            'lon': 0.0,
            'alt': 0.0,
            'rel_alt': 0.0,
            'roll': 0.0,
            'pitch': 0.0,
            'yaw': 0.0,
            'heading': 0.0,
            'groundspeed': 0.0,
            'airspeed': 0.0,
            'battery_remaining': 0.0,
            'voltage_battery': 0.0,
            'current_battery': 0.0,
            'battery_remaining_mah': 0.0,
            'vibration_x': 0.0,
            'vibration_y': 0.0,
            'vibration_z': 0.0,
            'gps_fix_type': 0,
            'satellites_visible': 0,
            'gps_vel': 0.0,
            'gps_cog': 0.0,
            'gps_eph': 0.0,
            'gps_epv': 0.0,
            'hdop': 0.0,
            'rc_channel5': 0,
        }

        print("[MAVLinkThread] Initialized.")

    def run(self):
        print("[MAVLinkThread] Thread started.")

        while self.running:
            try:
                msg = self.drone.recv_match(blocking=False, timeout=1)

                if not msg:
                    continue

                if self.drone_commander:
                    self.drone_commander._process_message(msg)

                for cb in self._msg_callbacks:
                    try:
                        cb(msg)
                    except Exception:
                        pass

                msg_type = msg.get_type()
                msg_dict = msg.to_dict()
                changed = False

                # ================= HEARTBEAT =================
                if msg_type == "HEARTBEAT":

                    autopilot_type = msg_dict.get('autopilot', 0)
                    if autopilot_type not in (3, 12, 4) and msg.get_srcComponent() != 1:
                        continue

                    mode_map = self.drone.mode_mapping()
                    inv_map = {v: k for k, v in mode_map.items()}

                    reported_mode = self.drone.flightmode or inv_map.get(
                        msg_dict['custom_mode'], "UNKNOWN")

                    new_armed = bool(
                        msg_dict['base_mode'] &
                        mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
                    )

                    if self.current_telemetry_components['mode'] != reported_mode:
                        self.current_telemetry_components['mode'] = reported_mode
                        changed = True

                    if self.current_telemetry_components['armed'] != new_armed:
                        self.current_telemetry_components['armed'] = new_armed
                        changed = True

                # ================= GLOBAL_POSITION_INT =================
                elif msg_type == "GLOBAL_POSITION_INT":

                    new_lat     = msg_dict['lat'] / 1e7
                    new_lon     = msg_dict['lon'] / 1e7
                    new_alt     = msg_dict['alt'] / 1000.0
                    new_rel_alt = msg_dict['relative_alt'] / 1000.0

                    self.current_telemetry_components.update({
                        'lat':     new_lat,
                        'lon':     new_lon,
                        'alt':     new_alt,
                        'rel_alt': new_rel_alt
                    })
                    changed = True

                # ================= ATTITUDE =================
                elif msg_type == "ATTITUDE":

                    self.current_telemetry_components.update({
                        'roll':  math.degrees(msg_dict['roll']),
                        'pitch': math.degrees(msg_dict['pitch']),
                        'yaw':   math.degrees(msg_dict['yaw'])
                    })
                    changed = True

                # ================= VFR_HUD =================
                elif msg_type == "VFR_HUD":

                    self.current_telemetry_components.update({
                        'heading':     msg_dict['heading'],
                        'groundspeed': msg_dict['groundspeed'],
                        'airspeed':    msg_dict['airspeed']
                    })
                    changed = True

                # ================= SYS_STATUS =================
                elif msg_type == "SYS_STATUS":

                    voltage = msg_dict.get('voltage_battery', 0)
                    current = msg_dict.get('current_battery', 0)
                    percent = msg_dict.get('battery_remaining', 0)

                    voltage = voltage / 1000.0 if voltage not in (None, 65535) else 0.0
                    current = current / 100.0  if current not in (None, -1)    else 0.0
                    percent = percent          if percent not in (None, -1)    else 0.0

                    self.current_telemetry_components.update({
                        'battery_remaining': percent,
                        'voltage_battery':   voltage,
                        'current_battery':   current
                    })
                    changed = True

                # ================= BATTERY_STATUS =================
                elif msg_type == "BATTERY_STATUS":

                    voltages = msg_dict.get('voltages', [])
                    if voltages and len(voltages) > 0 and voltages[0] not in (65535, 65535.0, 0):
                        total_v = 0.0
                        if len(voltages) > 1 and voltages[1] not in (65535, 0):
                            for v in voltages:
                                if v != 65535:
                                    total_v += v
                        else:
                            total_v = voltages[0]

                        if self.current_telemetry_components.get('voltage_battery', 0) <= 0.1:
                            self.current_telemetry_components['voltage_battery'] = total_v / 1000.0
                            changed = True

                    current_consumed = msg_dict.get('current_consumed', 0)
                    if current_consumed >= 0:
                        self.current_telemetry_components['battery_remaining_mah'] = current_consumed
                        changed = True

                    current_battery = msg_dict.get('current_battery', -1)
                    if current_battery not in (65535, -1):
                        self.current_telemetry_components['current_battery'] = current_battery / 100.0
                        changed = True

                    remaining_pct = msg_dict.get('battery_remaining', -1)
                    if remaining_pct not in (None, -1):
                        self.current_telemetry_components['battery_remaining'] = remaining_pct
                        changed = True

                # ================= VIBRATION =================
                elif msg_type == "VIBRATION":

                    self.current_telemetry_components.update({
                        'vibration_x': msg_dict.get('vibration_x', 0),
                        'vibration_y': msg_dict.get('vibration_y', 0),
                        'vibration_z': msg_dict.get('vibration_z', 0)
                    })
                    changed = True

                # ================= GPS_RAW_INT =================
                elif msg_type == "GPS_RAW_INT":

                    self.current_telemetry_components.update({
                        'gps_fix_type':      msg_dict.get('fix_type', 0),
                        'satellites_visible': msg_dict.get('satellites_visible', 0),
                        'gps_vel':           msg_dict.get('vel', 0),
                        'gps_cog':           msg_dict.get('cog', 0),
                        'gps_eph':           msg_dict.get('eph', 0),
                        'gps_epv':           msg_dict.get('epv', 0),
                        'hdop':              msg_dict.get('eph', 0)
                    })
                    changed = True

                # ================= RC_CHANNELS =================
                elif msg_type == "RC_CHANNELS":
                    ch5 = msg_dict.get('chan5_raw', 0)
                    if ch5 and ch5 > 800:
                        if self.current_telemetry_components.get('rc_channel5', 0) != ch5:
                            self.current_telemetry_components['rc_channel5'] = ch5
                            changed = True

                # ================= RC_CHANNELS_RAW (older firmware fallback) =====
                elif msg_type == "RC_CHANNELS_RAW":
                    ch5 = msg_dict.get('chan5_raw', 0)
                    if ch5 and ch5 > 800:
                        if self.current_telemetry_components.get('rc_channel5', 0) != ch5:
                            self.current_telemetry_components['rc_channel5'] = ch5
                            changed = True

                # ================= STATUSTEXT =================
                elif msg_type == "STATUSTEXT":
                    self.statusTextChanged.emit(msg.text)

                # ================= EMIT UPDATE =================
                if changed:
                    self.telemetryUpdated.emit(
                        self.current_telemetry_components.copy()
                    )

            except Exception as e:
                print(f"[MAVLinkThread ERROR] {e}")
                time.sleep(0.1)

            time.sleep(0.001)

    def register_msg_callback(self, callback):
        self._msg_callbacks.append(callback)

    def stop(self):
        print("[MAVLinkThread] Stopping...")
        self.running = False
        self.quit()
        self.wait()
        print("[MAVLinkThread] Stopped.")
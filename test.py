from pymavlink import mavutil
import time

# -------------------------------------------------------------------
# CONNECTION
# -------------------------------------------------------------------
# Change this if needed:
# USB  : '/dev/ttyUSB0', baud=57600
# UDP  : 'udp:127.0.0.1:14550'
# TCP  : 'tcp:127.0.0.1:5760'

CONNECTION_STRING = 'COM3'

print("Connecting to vehicle...")
master = mavutil.mavlink_connection(CONNECTION_STRING,baud=57600)

# -------------------------------------------------------------------
# WAIT FOR HEARTBEAT
# -------------------------------------------------------------------
master.wait_heartbeat()
print(f"Heartbeat received from system {master.target_system}, component {master.target_component}")

# -------------------------------------------------------------------
# MAIN LOOP
# -------------------------------------------------------------------
last_mode = None
last_armed = None

while True:
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=2)

    if not msg:
        continue
    if msg.autopilot == mavutil.mavlink.MAV_AUTOPILOT_INVALID:
        continue

    # OR stricter (recommended)
    if msg.type == mavutil.mavlink.MAV_TYPE_GCS:
        continue
    # -------------------------------
    # Decode flight mode
    # -------------------------------
    mode = mavutil.mode_string_v10(msg)

    # -------------------------------
    # Decode armed status
    # -------------------------------
    armed = bool(msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)

    # -------------------------------
    # Print only if changed
    # -------------------------------
    if mode != last_mode or armed != last_armed:
        print("----------------------------------")
        print(f"Autopilot : {msg.autopilot}")
        print(f"Vehicle   : {msg.type}")
        print(f"Mode      : {mode}")
        print(f"Armed     : {'YES' if armed else 'NO'}")
        print(f"Base mode : {msg.base_mode}")
        print(f"Custom    : {msg.custom_mode}")

        last_mode = mode
        last_armed = armed

    time.sleep(0.1)

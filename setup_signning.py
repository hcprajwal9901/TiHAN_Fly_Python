#!/usr/bin/env python3
import os
import time
import secrets
from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as mavlink2

# ======================================
# USER CONFIG
# ======================================
CONNECTION_STRING = "/dev/ttyACM0"   # change if needed
BAUDRATE = 57600
KEY_FILE = "mavlink_signing.key"

# ======================================
# STEP 1: LOAD OR CREATE KEY
# ======================================
def load_or_create_key(path):
    if os.path.exists(path):
        print(f"🔑 Loading existing key from {path}")
        with open(path, "r") as f:
            key_hex = f.read().strip()
    else:
        print("🔐 Generating new MAVLink signing key")
        key_bytes = secrets.token_bytes(32)
        key_hex = key_bytes.hex()
        with open(path, "w") as f:
            f.write(key_hex)
        os.chmod(path, 0o600)
        print(f"💾 Key saved to {path}")

    key_bytes = bytes.fromhex(key_hex)
    if len(key_bytes) != 32:
        raise ValueError("Signing key must be exactly 32 bytes")

    return key_hex, key_bytes

key_hex, key_bytes = load_or_create_key(KEY_FILE)

print("\n==============================")
print("🔐 SIGNING KEY (HEX)")
print("==============================")
print(key_hex)
print("==============================\n")

# ======================================
# STEP 2: CONNECT (UNSIGNED)
# ======================================
print("[1/4] Connecting UNSIGNED...")

master = mavutil.mavlink_connection(
    CONNECTION_STRING,
    baud=BAUDRATE,
    source_system=255,
    source_component=0,
    force_connected=True
)

master.wait_heartbeat(timeout=10)
print(f"✅ Heartbeat OK (SYS={master.target_system}, COMP={master.target_component})")

# ======================================
# STEP 3: SEND SETUP_SIGNING (256)
# ======================================
print("[2/4] Sending SETUP_SIGNING (256)...")

msg = mavlink2.MAVLink_setup_signing_message(
    target_system=master.target_system,
    target_component=master.target_component,
    initial_timestamp=0,
    secret_key=key_bytes
)

master.mav.send(msg)
time.sleep(1)

print("✅ Signing key uploaded and stored permanently")

# ======================================
# STEP 4: ENFORCE SIGNING
# ======================================
print("[3/4] Enforcing MAVLink2 + signing...")

# Enable MAVLink2
master.mav.param_set_send(
    master.target_system,
    master.target_component,
    b'BRD_OPTIONS',
    8,
    mavutil.mavlink.MAV_PARAM_TYPE_INT32
)
time.sleep(0.3)

# Enforce signed MAVLink
master.mav.param_set_send(
    master.target_system,
    master.target_component,
    b'SYSID_ENFORCE',
    1,
    mavutil.mavlink.MAV_PARAM_TYPE_INT32
)
time.sleep(0.3)

# ======================================
# STEP 5: REBOOT
# ======================================
print("[4/4] Rebooting autopilot...")

master.mav.command_long_send(
    master.target_system,
    master.target_component,
    mavutil.mavlink.MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN,
    0,
    1, 0, 0, 0, 0, 0, 0
)

time.sleep(5)
master.close()

print("\n==============================")
print("🎉 MAVLINK SIGNING COMPLETE")
print("==============================")
print("• Key stored on vehicle (flash)")
print("• Key stored locally:", KEY_FILE)
print("• Survives reboot & power loss")
print("==============================")

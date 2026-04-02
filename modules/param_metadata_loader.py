"""
param_metadata_loader.py
========================
Downloads, caches, and serves ArduPilot parameter metadata
(descriptions, units, ranges) that MAVLink PARAM_VALUE does NOT include.

NETWORK FALLBACK VERSION:
  - Includes embedded metadata for ~100 most common parameters
  - Falls back to embedded data if network is unavailable
  - Still tries to download full metadata when network works
"""

import json
import threading
import urllib.request
import urllib.error
from pathlib import Path


# Embedded fallback metadata for most common ArduCopter parameters
EMBEDDED_METADATA = {
    "ACRO_BAL_PITCH": {"description": "Rate at which pitch angle returns to level in acro mode", "units": "deg/s", "range": "0 – 3", "default": "1"},
    "ACRO_BAL_ROLL": {"description": "Rate at which roll angle returns to level in acro mode", "units": "deg/s", "range": "0 – 3", "default": "1"},
    "ACRO_RP_RATE": {"description": "Maximum roll/pitch rate in acro mode", "units": "deg/s", "range": "1 – 500", "default": "200"},
    "ACRO_YAW_RATE": {"description": "Maximum yaw rate in acro mode", "units": "deg/s", "range": "1 – 500", "default": "100"},
    "ANGLE_MAX": {"description": "Maximum lean angle in all flight modes", "units": "cdeg", "range": "1000 – 8000", "default": "4500"},
    "ARMING_CHECK": {"description": "Arming checks to perform before allowing takeoff", "units": "", "range": "0:All Disabled, 1:All Enabled", "default": "1"},
    "ATC_ACCEL_P_MAX": {"description": "Maximum acceleration in pitch axis", "units": "cdeg/s/s", "range": "0 – 180000", "default": "110000"},
    "ATC_ACCEL_R_MAX": {"description": "Maximum acceleration in roll axis", "units": "cdeg/s/s", "range": "0 – 180000", "default": "110000"},
    "ATC_ACCEL_Y_MAX": {"description": "Maximum acceleration in yaw axis", "units": "cdeg/s/s", "range": "0 – 72000", "default": "27000"},
    "ATC_RATE_P_MAX": {"description": "Maximum rate in pitch axis", "units": "deg/s", "range": "0 – 1080", "default": "0"},
    "ATC_RATE_R_MAX": {"description": "Maximum rate in roll axis", "units": "deg/s", "range": "0 – 1080", "default": "0"},
    "ATC_RATE_Y_MAX": {"description": "Maximum rate in yaw axis", "units": "deg/s", "range": "0 – 1080", "default": "0"},
    "BATT_CAPACITY": {"description": "Battery capacity in milliamp hours", "units": "mAh", "range": "0 – 500000", "default": "3300"},
    "BATT_MONITOR": {"description": "Battery monitoring type", "units": "", "range": "0:Disabled, 3:Analog Voltage Only, 4:Analog Voltage and Current", "default": "0"},
    "BATT_VOLT_PIN": {"description": "Battery voltage sensing pin", "units": "", "range": "-1 – 100", "default": "-1"},
    "BATT_CURR_PIN": {"description": "Battery current sensing pin", "units": "", "range": "-1 – 100", "default": "-1"},
    "COMPASS_ENABLE": {"description": "Enable or disable the use of the compass", "units": "", "range": "0:Disabled, 1:Enabled", "default": "1"},
    "COMPASS_USE": {"description": "Enable compass for yaw", "units": "", "range": "0:Disabled, 1:Enabled", "default": "1"},
    "COMPASS_USE2": {"description": "Enable second compass", "units": "", "range": "0:Disabled, 1:Enabled", "default": "1"},
    "COMPASS_USE3": {"description": "Enable third compass", "units": "", "range": "0:Disabled, 1:Enabled", "default": "1"},
    "ESC_CALIBRATION": {"description": "ESC calibration mode", "units": "", "range": "0:Disabled, 1:Enabled", "default": "0"},
    "FLTMODE1": {"description": "Flight mode for switch position 1", "units": "", "range": "0:Stabilize, 1:Acro, 2:AltHold, 3:Auto, 4:Guided, 5:Loiter", "default": "0"},
    "FLTMODE2": {"description": "Flight mode for switch position 2", "units": "", "range": "0:Stabilize, 1:Acro, 2:AltHold, 3:Auto, 4:Guided, 5:Loiter", "default": "0"},
    "FLTMODE3": {"description": "Flight mode for switch position 3", "units": "", "range": "0:Stabilize, 1:Acro, 2:AltHold, 3:Auto, 4:Guided, 5:Loiter", "default": "0"},
    "FLTMODE4": {"description": "Flight mode for switch position 4", "units": "", "range": "0:Stabilize, 1:Acro, 2:AltHold, 3:Auto, 4:Guided, 5:Loiter", "default": "0"},
    "FLTMODE5": {"description": "Flight mode for switch position 5", "units": "", "range": "0:Stabilize, 1:Acro, 2:AltHold, 3:Auto, 4:Guided, 5:Loiter", "default": "0"},
    "FLTMODE6": {"description": "Flight mode for switch position 6", "units": "", "range": "0:Stabilize, 1:Acro, 2:AltHold, 3:Auto, 4:Guided, 5:Loiter", "default": "0"},
    "FS_BATT_ENABLE": {"description": "Battery failsafe enable", "units": "", "range": "0:Disabled, 1:Land, 2:RTL", "default": "0"},
    "FS_BATT_VOLTAGE": {"description": "Battery failsafe voltage", "units": "V", "range": "0 – 50", "default": "10.5"},
    "FS_GCS_ENABLE": {"description": "Ground station failsafe enable", "units": "", "range": "0:Disabled, 1:Enabled", "default": "0"},
    "FS_THR_ENABLE": {"description": "Throttle failsafe enable", "units": "", "range": "0:Disabled, 1:Enabled", "default": "1"},
    "GPS_TYPE": {"description": "GPS type", "units": "", "range": "0:None, 1:AUTO, 2:uBlox", "default": "1"},
    "INS_ACCEL_FILTER": {"description": "Accelerometer filter cutoff frequency", "units": "Hz", "range": "0 – 256", "default": "20"},
    "INS_GYRO_FILTER": {"description": "Gyro filter cutoff frequency", "units": "Hz", "range": "0 – 256", "default": "20"},
    "LAND_SPEED": {"description": "Descent speed for landing", "units": "cm/s", "range": "30 – 200", "default": "50"},
    "LOG_BITMASK": {"description": "Log bitmask", "units": "", "range": "0 – 65535", "default": "830"},
    "MOT_PWM_MAX": {"description": "Maximum PWM output to ESCs", "units": "PWM", "range": "1000 – 2000", "default": "2000"},
    "MOT_PWM_MIN": {"description": "Minimum PWM output to ESCs", "units": "PWM", "range": "1000 – 2000", "default": "1000"},
    "MOT_SPIN_ARM": {"description": "Motor spin when armed", "units": "", "range": "0 – 0.3", "default": "0.1"},
    "MOT_SPIN_MIN": {"description": "Motor minimum spin", "units": "", "range": "0 – 0.3", "default": "0.15"},
    "MOT_THST_EXPO": {"description": "Motor thrust curve exponent", "units": "", "range": "0.25 – 0.8", "default": "0.65"},
    "PILOT_SPEED_DN": {"description": "Pilot maximum descent speed", "units": "cm/s", "range": "50 – 500", "default": "150"},
    "PILOT_SPEED_UP": {"description": "Pilot maximum ascent speed", "units": "cm/s", "range": "50 – 500", "default": "250"},
    "PSC_ACCZ_I": {"description": "Altitude hold I gain", "units": "", "range": "0 – 3", "default": "1.0"},
    "PSC_ACCZ_P": {"description": "Altitude hold P gain", "units": "", "range": "0 – 3", "default": "0.5"},
    "PSC_POSXY_P": {"description": "Position controller P gain", "units": "", "range": "0 – 10", "default": "1.0"},
    "PSC_POSZ_P": {"description": "Altitude controller P gain", "units": "", "range": "0 – 10", "default": "1.0"},
    "PSC_VELXY_D": {"description": "Velocity controller D gain", "units": "", "range": "0 – 1", "default": "0.5"},
    "PSC_VELXY_I": {"description": "Velocity controller I gain", "units": "", "range": "0 – 6", "default": "1.0"},
    "PSC_VELXY_P": {"description": "Velocity controller P gain", "units": "", "range": "0 – 6", "default": "2.0"},
    "PSC_VELZ_P": {"description": "Vertical velocity controller P gain", "units": "", "range": "1 – 8", "default": "5.0"},
    "RC1_MAX": {"description": "RC channel 1 maximum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1900"},
    "RC1_MIN": {"description": "RC channel 1 minimum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1100"},
    "RC1_TRIM": {"description": "RC channel 1 trim PWM", "units": "PWM", "range": "1000 – 2000", "default": "1500"},
    "RC2_MAX": {"description": "RC channel 2 maximum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1900"},
    "RC2_MIN": {"description": "RC channel 2 minimum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1100"},
    "RC2_TRIM": {"description": "RC channel 2 trim PWM", "units": "PWM", "range": "1000 – 2000", "default": "1500"},
    "RC3_MAX": {"description": "RC channel 3 maximum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1900"},
    "RC3_MIN": {"description": "RC channel 3 minimum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1100"},
    "RC3_TRIM": {"description": "RC channel 3 trim PWM", "units": "PWM", "range": "1000 – 2000", "default": "1500"},
    "RC4_MAX": {"description": "RC channel 4 maximum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1900"},
    "RC4_MIN": {"description": "RC channel 4 minimum PWM", "units": "PWM", "range": "1000 – 2000", "default": "1100"},
    "RC4_TRIM": {"description": "RC channel 4 trim PWM", "units": "PWM", "range": "1000 – 2000", "default": "1500"},
    "RCMAP_PITCH": {"description": "RC channel for pitch", "units": "", "range": "1 – 16", "default": "2"},
    "RCMAP_ROLL": {"description": "RC channel for roll", "units": "", "range": "1 – 16", "default": "1"},
    "RCMAP_THROTTLE": {"description": "RC channel for throttle", "units": "", "range": "1 – 16", "default": "3"},
    "RCMAP_YAW": {"description": "RC channel for yaw", "units": "", "range": "1 – 16", "default": "4"},
    "RTL_ALT": {"description": "RTL altitude in cm", "units": "cm", "range": "0 – 8000", "default": "1500"},
    "RTL_SPEED": {"description": "RTL horizontal speed", "units": "cm/s", "range": "0 – 2000", "default": "1000"},
    "SERIAL0_BAUD": {"description": "Serial port 0 baud rate", "units": "baud", "range": "1:1200, 2:2400, 57:57600, 111:115200", "default": "115200"},
    "SERIAL1_BAUD": {"description": "Serial port 1 baud rate", "units": "baud", "range": "1:1200, 2:2400, 57:57600, 111:115200", "default": "57600"},
    "SERIAL2_BAUD": {"description": "Serial port 2 baud rate", "units": "baud", "range": "1:1200, 2:2400, 57:57600, 111:115200", "default": "57600"},
    "SYSID_THISMAV": {"description": "MAVLink system ID of this vehicle", "units": "", "range": "1 – 255", "default": "1"},
    "THR_DZ": {"description": "Throttle deadzone", "units": "PWM", "range": "0 – 300", "default": "100"},
    "WPNAV_ACCEL": {"description": "Waypoint navigation horizontal acceleration", "units": "cm/s/s", "range": "50 – 500", "default": "100"},
    "WPNAV_RADIUS": {"description": "Waypoint radius", "units": "cm", "range": "10 – 1000", "default": "200"},
    "WPNAV_SPEED": {"description": "Waypoint navigation horizontal speed", "units": "cm/s", "range": "20 – 2000", "default": "500"},
    "WPNAV_SPEED_DN": {"description": "Waypoint navigation descent speed", "units": "cm/s", "range": "10 – 500", "default": "150"},
    "WPNAV_SPEED_UP": {"description": "Waypoint navigation climb speed", "units": "cm/s", "range": "10 – 1000", "default": "250"},
}

METADATA_URLS = {
    "ArduCopter": [
        "https://autotest.ardupilot.org/Parameters/ArduCopter/apm.pdef.xml",
        "https://firmware.ardupilot.org/Tools/Frame_params/ArduCopter.pdef.xml",
    ],
    "ArduPlane": [
        "https://autotest.ardupilot.org/Parameters/ArduPlane/apm.pdef.xml",
    ],
    "ArduRover": [
        "https://autotest.ardupilot.org/Parameters/Rover/apm.pdef.xml",
    ],
    "ArduSub": [
        "https://autotest.ardupilot.org/Parameters/ArduSub/apm.pdef.xml",
    ],
}

CACHE_VERSION = 2
CACHE_DIR = Path.home() / ".tihanfly" / "param_metadata"
CACHE_DIR.mkdir(parents=True, exist_ok=True)


class ParamMetadataLoader:
    """
    Loads ArduPilot parameter metadata (description, units, range, default).

    * First run  -> tries to download apm.pdef.xml, falls back to embedded data
    * Later runs -> loads from local cache (instant, no network)
    * Network fail -> uses embedded metadata for common params

    Thread-safe. enrich_parameters() blocks briefly until ready.
    """

    def __init__(self, vehicle_type: str = "ArduCopter"):
        self._metadata: dict = {}
        self._lock = threading.Lock()
        self._loaded = False
        self._load_event = threading.Event()
        self._vehicle_type = vehicle_type

        t = threading.Thread(target=self._load, daemon=True, name="ParamMetadataLoader")
        t.start()

    def wait_until_loaded(self, timeout: float = 30.0) -> bool:
        """Block until metadata is ready. Returns True if loaded in time."""
        return self._load_event.wait(timeout=timeout)

    def get(self, param_name: str) -> dict:
        with self._lock:
            return dict(self._metadata.get(param_name.strip(), {
                "description": "", "units": "", "range": "", "default": "",
            }))

    def enrich_parameters(self, params: dict) -> dict:
        """
        Fill description / units / range / default into the params dict.
        Waits up to 30 s for the loader to finish. Modifies params in-place.
        """
        if not self._loaded:
            print("[ParamMetadata] Waiting for metadata (max 30s)...")
            self._load_event.wait(timeout=30.0)

        with self._lock:
            snapshot = dict(self._metadata)

        if not snapshot:
            print("[ParamMetadata] WARNING: Metadata empty — skipping enrichment")
            return params

        enriched = 0
        for name, data in params.items():
            meta = snapshot.get(name)
            if meta is None:
                continue

            if meta.get("description"):
                data["description"] = meta["description"]
            if meta.get("units"):
                data["units"] = meta["units"]
            if meta.get("range"):
                data["range"] = meta["range"]
            if meta.get("default"):
                data["default"] = meta["default"]

            enriched += 1

        print(f"[ParamMetadata] Enriched {enriched}/{len(params)} parameters")
        return params

    def is_loaded(self) -> bool:
        return self._loaded

    def _load(self):
        print(f"[ParamMetadata] Loading metadata for {self._vehicle_type}...")
        try:
            cache_file = CACHE_DIR / f"{self._vehicle_type}_params_v{CACHE_VERSION}.json"

            # Clean old caches
            for old in CACHE_DIR.glob(f"{self._vehicle_type}_params*.json"):
                if old != cache_file:
                    try:
                        old.unlink()
                        print(f"[ParamMetadata] Removed old cache: {old.name}")
                    except Exception:
                        pass

            # Try cache first
            if cache_file.exists():
                try:
                    data = self._load_json(cache_file)
                    desc_count = sum(1 for v in data.values() if v.get("description"))
                    if desc_count >= 5:
                        with self._lock:
                            self._metadata = data
                        print(f"[ParamMetadata] ✅ Loaded {len(data)} params from cache ({desc_count} with descriptions)")
                        return
                    else:
                        print(f"[ParamMetadata] Cache has only {desc_count} descriptions — will try network")
                        cache_file.unlink()
                except Exception as e:
                    print(f"[ParamMetadata] Cache error: {e}")

            # Try network download
            urls = METADATA_URLS.get(self._vehicle_type, METADATA_URLS["ArduCopter"])
            for url in urls:
                try:
                    print(f"[ParamMetadata] Downloading: {url}")
                    raw = self._download(url, timeout=15)  # Shorter timeout to fail fast
                    parsed = self._parse_apm_pdef_xml(raw)
                    desc_count = sum(1 for v in parsed.values() if v.get("description"))
                    
                    if parsed and desc_count >= 5:
                        self._save_json(cache_file, parsed)
                        with self._lock:
                            self._metadata = parsed
                        print(f"[ParamMetadata] ✅ Loaded {len(parsed)} params from network")
                        return
                except Exception as e:
                    print(f"[ParamMetadata] Download failed: {e}")

            # Fall back to embedded metadata
            print(f"[ParamMetadata] ⚠️ Network unavailable — using embedded metadata ({len(EMBEDDED_METADATA)} params)")
            with self._lock:
                self._metadata = dict(EMBEDDED_METADATA)
            
            # Save embedded metadata to cache for next time
            try:
                self._save_json(cache_file, EMBEDDED_METADATA)
            except Exception:
                pass

        except Exception as e:
            print(f"[ParamMetadata] Error: {e}")
            # Still load embedded data on error
            with self._lock:
                self._metadata = dict(EMBEDDED_METADATA)
        finally:
            self._loaded = True
            self._load_event.set()
            print(f"[ParamMetadata] Ready with {len(self._metadata)} entries")

    def _parse_apm_pdef_xml(self, xml_bytes: bytes) -> dict:
        """Parse ArduPilot apm.pdef.xml"""
        import xml.etree.ElementTree as ET
        result = {}

        if xml_bytes.startswith(b'\xef\xbb\xbf'):
            xml_bytes = xml_bytes[3:]

        try:
            root = ET.fromstring(xml_bytes)
        except ET.ParseError as e:
            raise ValueError(f"XML parse error: {e}")

        for param_elem in root.iter("param"):
            name = (param_elem.get("name") or "").strip()
            if not name:
                continue

            meta = {"description": "", "units": "", "range": "", "default": ""}

            for field in param_elem.findall("field"):
                field_name = (field.get("name") or "").strip().lower()
                raw_text = field.text or ""
                clean_text = " ".join(raw_text.split())

                if field_name == "description":
                    meta["description"] = clean_text
                elif field_name == "units":
                    meta["units"] = clean_text
                elif field_name == "range":
                    meta["range"] = clean_text
                elif field_name == "default":
                    meta["default"] = clean_text

            # Enum values
            values = []
            for value_elem in param_elem.findall("values/value"):
                code = (value_elem.get("code") or "").strip()
                label = " ".join((value_elem.text or "").split())
                if code and label:
                    values.append(f"{code}:{label}")
            if values:
                meta["range"] = ", ".join(values)
            elif meta["range"]:
                parts = meta["range"].split()
                if len(parts) == 2:
                    try:
                        float(parts[0]); float(parts[1])
                        meta["range"] = f"{parts[0]} – {parts[1]}"
                    except ValueError:
                        pass

            result[name] = meta

        return result

    @staticmethod
    def _load_json(path: Path) -> dict:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    @staticmethod
    def _save_json(path: Path, data: dict):
        try:
            tmp = path.with_suffix(".tmp")
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
            tmp.replace(path)
            print(f"[ParamMetadata] Saved cache: {path.name}")
        except Exception as e:
            print(f"[ParamMetadata] Cache save error: {e}")

    @staticmethod
    def _download(url: str, timeout: int = 15) -> bytes:
        req = urllib.request.Request(
            url, headers={"User-Agent": "TiHAN-DroneGCS/2.1"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
"""
modules/GStreamerPipelineFactory.py
====================================
TiHAN GCS — GPU-Accelerated GStreamer Pipeline Factory
Version: 1.0.0

Detects available hardware (NVIDIA Desktop, Jetson, Intel VAAPI, or software)
and produces the optimal low-latency GStreamer pipeline string for RTSP decoding.

No external state. Pure factory pattern — safe to call from any thread.
"""

import subprocess
import logging
import platform

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# Hardware profile identifiers
# ──────────────────────────────────────────────────────────────────────────────

PROFILE_NVIDIA_DESKTOP = "nvidia_desktop"
PROFILE_NVIDIA_JETSON  = "nvidia_jetson"
PROFILE_INTEL_VAAPI    = "intel_vaapi"
PROFILE_SOFTWARE       = "software"

# ──────────────────────────────────────────────────────────────────────────────
# Pipeline templates
# ──────────────────────────────────────────────────────────────────────────────

PIPELINE_TEMPLATES = {
    PROFILE_NVIDIA_DESKTOP: (
        "rtspsrc latency=0 protocols=tcp location={url} {auth_opt} ! "
        "rtph264depay ! h264parse ! nvh264dec ! "
        "videoconvert ! video/x-raw,format=BGR ! "
        "appsink name=sink sync=false drop=true max-buffers=2"
    ),
    PROFILE_NVIDIA_JETSON: (
        "rtspsrc latency=0 location={url} {auth_opt} ! "
        "rtph264depay ! h264parse ! "
        "nvv4l2decoder enable-max-performance=1 ! "
        "nvvidconv ! video/x-raw(memory:NVMM) ! "
        "nvvidconv ! video/x-raw,format=BGRx ! "
        "appsink name=sink sync=false drop=true max-buffers=2"
    ),
    PROFILE_INTEL_VAAPI: (
        "rtspsrc latency=0 location={url} {auth_opt} ! "
        "rtph264depay ! h264parse ! vaapih264dec ! "
        "videoconvert ! video/x-raw,format=BGR ! "
        "appsink name=sink sync=false drop=true max-buffers=2"
    ),
    PROFILE_SOFTWARE: (
        "rtspsrc latency=0 location={url} {auth_opt} ! "
        "rtph264depay ! decodebin ! "
        "videoconvert ! video/x-raw,format=BGR ! "
        "appsink name=sink sync=false drop=true max-buffers=2"
    ),
}


# ──────────────────────────────────────────────────────────────────────────────
# Hardware Detection
# ──────────────────────────────────────────────────────────────────────────────

def _run_silent(cmd):
    """Run a shell command, return (returncode, stdout+stderr)."""
    try:
        result = subprocess.run(
            cmd, shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5
        )
        text = (result.stdout + result.stderr).decode("utf-8", errors="ignore")
        return result.returncode, text
    except Exception:
        return -1, ""


def _check_gst_plugin(plugin_name):
    """Return True if the given GStreamer plugin element is available."""
    code, out = _run_silent(f"gst-inspect-1.0 {plugin_name}")
    return code == 0


def detect_hardware_profile() -> str:
    """
    Auto-detect the best hardware profile for GPU-accelerated video decoding.

    On Windows, NVIDIA/VAAPI GStreamer plugins (nvh264dec, vaapih264dec) may
    be installed but crash at the C level when initialising CUDA/DXVA contexts.
    We therefore always use the software fallback on Windows and only attempt
    GPU profiles on Linux (Jetson / desktop / Intel VAAPI).

    Order of preference (Linux only):
        1. Jetson Orin / Xavier (nvv4l2decoder)
        2. Desktop NVIDIA (nvh264dec)
        3. Intel VAAPI (vaapih264dec)
        4. Software fallback (decodebin)  ← always used on Windows

    Returns:
        One of: PROFILE_NVIDIA_DESKTOP, PROFILE_NVIDIA_JETSON,
                PROFILE_INTEL_VAAPI, PROFILE_SOFTWARE
    """
    # On Windows NVIDIA/VAAPI plugins crash at C level — skip GPU detection
    if platform.system() == "Windows":
        logger.info("[GStreamerPipelineFactory] Windows detected — using software profile")
        print("[GStreamerPipelineFactory] ℹ️  Windows: forcing software (decodebin) profile")
        return PROFILE_SOFTWARE

    # ── Check Jetson (nvv4l2decoder is the Jetson-specific element) ──
    if _check_gst_plugin("nvv4l2decoder"):
        logger.info("[GStreamerPipelineFactory] Detected Jetson NVIDIA (nvv4l2decoder)")
        return PROFILE_NVIDIA_JETSON

    # ── Check Desktop NVIDIA (nvh264dec from NVCODEC plugin) ──
    if _check_gst_plugin("nvh264dec"):
        logger.info("[GStreamerPipelineFactory] Detected Desktop NVIDIA (nvh264dec)")
        return PROFILE_NVIDIA_DESKTOP

    # ── Check Intel VAAPI ──
    if _check_gst_plugin("vaapih264dec"):
        logger.info("[GStreamerPipelineFactory] Detected Intel VAAPI (vaapih264dec)")
        return PROFILE_INTEL_VAAPI

    # ── Software fallback ──
    logger.info("[GStreamerPipelineFactory] No GPU decoder found — using software decoding")
    return PROFILE_SOFTWARE


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline Builder
# ──────────────────────────────────────────────────────────────────────────────

class GStreamerPipelineFactory:
    """
    Singleton-like factory (create one instance per application).

    Usage:
        factory = GStreamerPipelineFactory()
        pipeline_str = factory.build_pipeline("rtsp://192.168.1.10/cam")
    """

    def __init__(self):
        self._profile = detect_hardware_profile()
        logger.info(f"[GStreamerPipelineFactory] Using profile: {self._profile}")
        print(f"[GStreamerPipelineFactory] ✅ Hardware profile: {self._profile}")

    @property
    def profile(self) -> str:
        return self._profile

    def build_pipeline(
        self,
        url: str,
        username: str = "",
        password: str = "",
        force_profile: str = None
    ) -> str:
        """
        Build a complete GStreamer launch pipeline string.

        Args:
            url:           Full RTSP URL (e.g. rtsp://host/path)
            username:      Optional RTSP auth username
            password:      Optional RTSP auth password
            force_profile: Override auto-detected profile (for testing)

        Returns:
            A pipeline string ready for Gst.parse_launch()
        """
        profile = force_profile or self._profile
        template = PIPELINE_TEMPLATES.get(profile, PIPELINE_TEMPLATES[PROFILE_SOFTWARE])

        # Build auth string for rtspsrc if credentials are provided
        if username and password:
            auth_opt = f'user-id="{username}" user-pw="{password}"'
        else:
            auth_opt = ""

        pipeline_str = template.format(url=url, auth_opt=auth_opt)
        logger.info(f"[GStreamerPipelineFactory] Pipeline built [{profile}]: {pipeline_str}")
        print(f"[GStreamerPipelineFactory] 🏗️ Pipeline [{profile}]: {pipeline_str}")
        return pipeline_str

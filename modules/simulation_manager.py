"""
simulation_manager.py — TihanFly GCS Automatic Simulation Module
=================================================================
Drop-in mixin / standalone class for automatic ArduPilot SITL management.

Design goals
------------
• Cross-platform: Linux runs sim_vehicle.py directly;
  Windows runs it inside WSL transparently.
• Non-blocking: SITL launch + MAVLink connection run on QThreads so
  the QML UI never freezes.
• Safe: subprocess is always cleaned up, even on crash or early exit.
• Isolated: zero changes to existing serial-connection code paths.

Usage in DroneModel (or DroneCommander)
----------------------------------------
  from simulation_manager import SimulationMixin

  class DroneModel(QObject, SimulationMixin):
      def __init__(self):
          super().__init__()
          SimulationMixin.__init__(self)   # <-- add this line

  Then expose droneModel.startSimulation / stopSimulation to QML.
"""

from __future__ import annotations

import os
import platform
import shutil
import signal
import subprocess
import sys
import time

from PyQt5.QtCore import (
    QObject,
    QThread,
    pyqtProperty,
    pyqtSignal,
    pyqtSlot,
)
from pymavlink import mavutil


# ─────────────────────────────────────────────────────────────────────────────
# Internal worker: launches SITL then connects MAVLink (background thread)
# ─────────────────────────────────────────────────────────────────────────────

class _SimWorker(QThread):
    """
    Runs entirely off the main thread.

    Emitted signals
    ---------------
    success(drone_connection)   – heartbeat received, drone object ready
    failure(error_message)      – something went wrong
    statusUpdate(text)          – progress messages for the UI log
    """

    success = pyqtSignal(object)
    failure = pyqtSignal(str)
    statusUpdate = pyqtSignal(str)

    # How long (seconds) to keep retrying the UDP connect + heartbeat
    CONNECT_TIMEOUT = 20
    # Pause between MAVLink connection retries
    RETRY_INTERVAL = 2
    # UDP endpoint ArduPilot SITL listens on by default
    SITL_UDP_URI = "udp:127.0.0.1:14550"

    def __init__(self, sitl_args: list[str], parent=None):
        super().__init__(parent)
        self._sitl_args = sitl_args
        self._sitl_process: subprocess.Popen | None = None
        self._should_stop = False

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_process(self) -> subprocess.Popen | None:
        """Return the SITL subprocess so the owner can kill it later."""
        return self._sitl_process

    def stop(self):
        self._should_stop = True

    # ------------------------------------------------------------------
    # Thread entry point
    # ------------------------------------------------------------------

    def run(self):
        try:
            self._launch_sitl()
            if self._should_stop:
                return
            self._connect_mavlink()
        except Exception as exc:
            if not self._should_stop:
                self.failure.emit(f"Simulation worker error: {exc}")

    # ------------------------------------------------------------------
    # Step 1 — launch SITL subprocess
    # ------------------------------------------------------------------

    def _launch_sitl(self):
        self.statusUpdate.emit("🚀 Launching ArduPilot SITL...")
        self.statusUpdate.emit(f"   Command: {' '.join(self._sitl_args)}")

        # Prevent a visible console window on Windows
        kwargs: dict = {}
        if sys.platform == "win32":
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW

        self._sitl_process = subprocess.Popen(
            self._sitl_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            **kwargs,
        )
        self.statusUpdate.emit(
            f"✅ SITL process started (PID {self._sitl_process.pid})"
        )
        # Give SITL a moment to bind its UDP port before we hammer it
        time.sleep(3)

    # ------------------------------------------------------------------
    # Step 2 — connect MAVLink with retry
    # ------------------------------------------------------------------

    def _connect_mavlink(self):
        self.statusUpdate.emit(
            f"🔌 Connecting to SITL at {self.SITL_UDP_URI} …"
        )

        deadline = time.time() + self.CONNECT_TIMEOUT
        attempt = 0

        while time.time() < deadline:
            if self._should_stop:
                return

            attempt += 1
            self.statusUpdate.emit(f"   Attempt {attempt}…")

            try:
                drone = mavutil.mavlink_connection(
                    self.SITL_UDP_URI,
                    source_system=255,
                    source_component=0,
                    force_connected=True,
                )

                remaining = deadline - time.time()
                heartbeat_timeout = min(remaining, 5)

                self.statusUpdate.emit(
                    f"   Waiting for heartbeat (timeout {heartbeat_timeout:.0f}s)…"
                )
                drone.wait_heartbeat(timeout=heartbeat_timeout)

                # ✅ Got heartbeat
                self.statusUpdate.emit(
                    f"💚 Heartbeat received! SysID={drone.target_system}"
                )
                self.success.emit(drone)
                return

            except Exception as exc:
                self.statusUpdate.emit(f"   ⚠️  {exc}")
                if self._sitl_process and self._sitl_process.poll() is not None:
                    self.failure.emit(
                        "SITL process exited unexpectedly before heartbeat."
                    )
                    return
                time.sleep(self.RETRY_INTERVAL)

        self.failure.emit(
            f"Timed out after {self.CONNECT_TIMEOUT}s — "
            "no heartbeat received from SITL."
        )


# ─────────────────────────────────────────────────────────────────────────────
# SimulationMixin — add to DroneModel (or any QObject subclass)
# ─────────────────────────────────────────────────────────────────────────────

class SimulationMixin:
    """
    Mixin that adds startSimulation() / stopSimulation() slots plus an
    isSimulation property to any QObject subclass.

    Requirements on the host class
    --------------------------------
    The host class must provide these attributes/methods that already exist
    in DroneModel:

        self.addStatusText(str)           – status log
        self._on_sim_connection_success() – already in DroneModel
        self.commandFeedback              – pyqtSignal(str)

    No other DroneModel internals are touched.
    """

    # ------------------------------------------------------------------
    # Signals that SimulationMixin adds
    # (declare them in the *host* class body if you want them in QML;
    #  they are redeclared here for documentation only)
    # ------------------------------------------------------------------
    # simulationStateChanged = pyqtSignal(bool)   # host must add this

    # ------------------------------------------------------------------
    # Init — call from host __init__
    # ------------------------------------------------------------------

    def _sim_init(self):
        """Call this inside __init__ of the host class."""
        self._sitl_process: subprocess.Popen | None = None
        self._sim_worker: _SimWorker | None = None
        self._is_simulation: bool = False

    # ------------------------------------------------------------------
    # Cross-platform SITL command builder
    # ------------------------------------------------------------------

    @staticmethod
    def _build_sitl_command() -> list[str]:
        """
        Return the command list to launch ArduPilot SITL.

        Search order:
          1. ``SIM_VEHICLE_PATH`` environment variable (advanced users)
          2. PATH lookup for ``sim_vehicle.py``
          3. Common install locations under $HOME / %USERPROFILE%
          4. Windows → prepend ``wsl`` so it runs inside WSL
        """
        script_name = "sim_vehicle.py"
        sitl_args_suffix = ["-v", "ArduCopter", "--out=udp:127.0.0.1:14550"]

        # --- Honour explicit override ---
        env_path = os.environ.get("SIM_VEHICLE_PATH")
        if env_path:
            return [env_path] + sitl_args_suffix

        # --- Native Linux / macOS ---
        if sys.platform != "win32":
            # 1. On PATH?
            found = shutil.which(script_name)
            if found:
                return [found] + sitl_args_suffix

            # 2. Common install paths
            candidates = [
                os.path.expanduser("~/ardupilot/Tools/autotest/sim_vehicle.py"),
                "/usr/local/bin/sim_vehicle.py",
                "/opt/ardupilot/Tools/autotest/sim_vehicle.py",
            ]
            for c in candidates:
                if os.path.isfile(c):
                    return [c] + sitl_args_suffix

            raise FileNotFoundError(
                "sim_vehicle.py not found. Install ArduPilot or set "
                "SIM_VEHICLE_PATH=/path/to/sim_vehicle.py"
            )

        # --- Windows: try WSL ---
        wsl = shutil.which("wsl")
        if not wsl:
            raise EnvironmentError(
                "WSL not found on this Windows machine. "
                "Please install WSL and ArduPilot inside it, "
                "or set SIM_VEHICLE_PATH to a native sim_vehicle.py."
            )

        # Default WSL path; user can override with SIM_VEHICLE_PATH
        wsl_script = "~/ardupilot/Tools/autotest/sim_vehicle.py"
        return [wsl, wsl_script] + sitl_args_suffix

    # ------------------------------------------------------------------
    # Slots
    # ------------------------------------------------------------------

    @pyqtSlot()
    def startSimulation(self):
        """
        QML slot — launch SITL and connect MAVLink.
        Safe to call even if a simulation is already running (stops it first).
        """
        if self._is_simulation:
            self.addStatusText("⚠️  Simulation already running — stopping first…")
            self.stopSimulation()
            time.sleep(1)

        self.addStatusText("🎮 Starting Simulation Mode…")

        try:
            sitl_cmd = self._build_sitl_command()
        except (FileNotFoundError, EnvironmentError) as exc:
            msg = f"❌ Cannot start SITL: {exc}"
            self.addStatusText(msg)
            self.commandFeedback.emit(msg)
            return

        # Spin up worker thread
        self._sim_worker = _SimWorker(sitl_cmd)
        self._sim_worker.statusUpdate.connect(self.addStatusText)
        self._sim_worker.success.connect(self._on_sim_mavlink_ready)
        self._sim_worker.failure.connect(self._on_sim_failed)
        self._sim_worker.start()

    @pyqtSlot()
    def stopSimulation(self):
        """QML slot — cleanly shut down SITL and reset state."""
        self.addStatusText("🛑 Stopping Simulation…")

        # Stop worker thread first
        if self._sim_worker and self._sim_worker.isRunning():
            self._sim_worker.stop()
            self._sim_worker.wait(3000)
            self._sim_worker = None

        # Retrieve and kill SITL process
        process = getattr(self, "_sitl_process", None)
        if process and process.poll() is None:
            self.addStatusText(
                f"   Terminating SITL process (PID {process.pid})…"
            )
            try:
                if sys.platform == "win32":
                    # On Windows, subprocess tree must be killed explicitly
                    subprocess.call(
                        ["taskkill", "/F", "/T", "/PID", str(process.pid)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                else:
                    # Send SIGTERM to the process group so child processes die too
                    try:
                        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
                    except ProcessLookupError:
                        process.terminate()
                process.wait(timeout=5)
            except Exception as exc:
                self.addStatusText(f"   ⚠️  Cleanup warning: {exc}")
                try:
                    process.kill()
                except Exception:
                    pass

        self._sitl_process = None

        # Disconnect MAVLink (reuse existing disconnect path)
        if self._is_simulation:
            self._is_simulation = False
            self.disconnectDrone()       # already exists on DroneModel
            self._emit_simulation_state(False)

        self.addStatusText("✅ Simulation stopped.")

    # ------------------------------------------------------------------
    # Property exposed to QML
    # ------------------------------------------------------------------

    @pyqtProperty(bool, notify=None)   # host must wire up notify signal
    def isSimulation(self) -> bool:
        return self._is_simulation

    # ------------------------------------------------------------------
    # Internal callbacks
    # ------------------------------------------------------------------

    def _on_sim_mavlink_ready(self, drone_connection):
        """Called by _SimWorker when heartbeat is confirmed."""
        # Store the subprocess reference before the worker might be GC'd
        if self._sim_worker:
            self._sitl_process = self._sim_worker.get_process()

        self._is_simulation = True
        self._emit_simulation_state(True)

        # Hand the drone connection to DroneModel's existing path
        self._on_sim_connection_success()   # sets isConnected, starts telemetry

        # Patch in the real drone object so MAVLinkThread can use it
        self._drone = drone_connection

        self.commandFeedback.emit("🎮 Simulation Connected")
        self.addStatusText("🟢 [SIM] SITL live — telemetry active")

    def _on_sim_failed(self, error_message: str):
        """Called by _SimWorker on any error."""
        self._is_simulation = False
        self._emit_simulation_state(False)

        full_msg = f"❌ Simulation failed: {error_message}"
        self.addStatusText(full_msg)
        self.commandFeedback.emit(full_msg)

        # Kill SITL if it was started before the failure
        if self._sim_worker:
            proc = self._sim_worker.get_process()
            if proc and proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=3)
                except Exception:
                    pass
        self._sitl_process = None

    def _emit_simulation_state(self, state: bool):
        """Emit simulationStateChanged if the host class has it."""
        if hasattr(self, "simulationStateChanged"):
            self.simulationStateChanged.emit(state)


# ─────────────────────────────────────────────────────────────────────────────
# Convenience standalone class (if you prefer composition over inheritance)
# ─────────────────────────────────────────────────────────────────────────────

class SimulationManager(QObject, SimulationMixin):
    """
    Standalone QObject you can inject into DroneModel as a property
    if you prefer composition:

        self._sim_manager = SimulationManager(drone_model=self)
        # then expose it to QML
    """

    simulationStateChanged = pyqtSignal(bool)
    commandFeedback = pyqtSignal(str)

    def __init__(self, drone_model=None, parent=None):
        super().__init__(parent)
        SimulationMixin._sim_init(self)
        self._drone_model = drone_model

    # Delegate to drone_model so the mixin's internals work
    def addStatusText(self, text: str):
        if self._drone_model:
            self._drone_model.addStatusText(text)
        else:
            print(f"[SimulationManager] {text}")

    def disconnectDrone(self):
        if self._drone_model:
            self._drone_model.disconnectDrone()

    def _on_sim_connection_success(self):
        if self._drone_model:
            self._drone_model._on_sim_connection_success()

    @property
    def _drone(self):
        return self._drone_model._drone if self._drone_model else None

    @_drone.setter
    def _drone(self, value):
        if self._drone_model:
            self._drone_model._drone = value
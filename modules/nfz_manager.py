"""
NFZManager.py  –  No-Fly Zone manager for TiHAN Fly-Drone Control Station
==========================================================================
Loads GeoJSON NFZ data, exposes zones to QML, and provides both
Python-side and QML-side breach detection.

Key fixes:
  • Every zone dict always contains `radius_m` so QML circle checks work.
  • MultiPolygon: each polygon's outer ring is stored as a separate ring
    so QML ray-casting correctly tests all sub-polygons.
  • Added `waypointBlockedByNFZ` signal for UI feedback when a waypoint
    placement is rejected.
  • Default fallback radius is 500 m if the GeoJSON has no radius field.
"""

import json
import math
import os
from typing import Optional

from PyQt5.QtCore import (
    QObject, pyqtProperty, pyqtSignal, pyqtSlot, QVariant
)


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return the great-circle distance in metres between two points."""
    R = 6_371_000
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (math.sin(d_lat / 2) ** 2
         + math.cos(math.radians(lat1))
         * math.cos(math.radians(lat2))
         * math.sin(d_lon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _ray_cast_inside(lat: float, lon: float, ring: list) -> bool:
    """Standard ray-casting point-in-polygon test for one ring."""
    n = len(ring)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]["lon"], ring[i]["lat"]
        xj, yj = ring[j]["lon"], ring[j]["lat"]
        if ((yi > lat) != (yj > lat)) and (
            lon < (xj - xi) * (lat - yi) / (yj - yi) + xi
        ):
            inside = not inside
        j = i
    return inside


def _centroid_of_ring(ring: list) -> tuple:
    """Return (lat, lon) centroid of a polygon ring."""
    if not ring:
        return 0.0, 0.0
    lat = sum(p["lat"] for p in ring) / len(ring)
    lon = sum(p["lon"] for p in ring) / len(ring)
    return lat, lon


def _radius_of_ring(ring: list, c_lat: float, c_lon: float) -> float:
    """Approximate bounding radius of a polygon ring (metres)."""
    if not ring:
        return .0
    return max(
        _haversine_m(c_lat, c_lon, p["lat"], p["lon"])
        for p in ring
    )


# ──────────────────────────────────────────────────────────────────────────────
# NFZManager
# ──────────────────────────────────────────────────────────────────────────────

class NFZManager(QObject):
    """
    Loads No-Fly Zone data from a GeoJSON file and exposes it to QML.

    QML-facing properties
    ---------------------
    nfzZones    – list of zone dicts (see _build_zone_dict for schema)
    nfzCount    – number of loaded zones

    QML-facing signals
    ------------------
    nfzDataChanged()              – emitted after a successful load
    droneInNFZ(zoneName)          – emitted when drone enters an NFZ
    droneExitedNFZ()              – emitted when drone leaves all NFZs
    droneNearNFZ(zoneName, dist)  – emitted when drone comes within
                                    PROXIMITY_WARNING_M metres of an NFZ
                                    boundary (fires once per approach)
    droneExitedProximity()        – emitted when drone moves back outside
                                    the proximity warning radius
    waypointBlockedByNFZ(lat, lon, zoneName)
                                  – emitted when a waypoint placement is
                                    rejected because it falls inside an NFZ

    QML-facing slots
    ----------------
    loadNFZFromFile(path)
    checkDronePosition(lat, lon)
    isDroneInNFZ(lat, lon) -> bool
    isWaypointInNFZ(lat, lon) -> bool   (same check, explicit name)
    """

    nfzDataChanged       = pyqtSignal()
    droneInNFZ           = pyqtSignal(str)              # zoneName
    droneExitedNFZ       = pyqtSignal()
    waypointBlockedByNFZ = pyqtSignal(float, float, str)  # lat, lon, zoneName
    droneNearNFZ         = pyqtSignal(str, float)        # zoneName, distance_m
    droneExitedProximity = pyqtSignal()

    # Distance (metres) from NFZ boundary that triggers the proximity warning
    PROXIMITY_WARNING_M  = 500.0

    # ── internal ──────────────────────────────────────────────────────────────

    def __init__(self, geojson_path: Optional[str] = None, parent: Optional[QObject] = None):
        super().__init__(parent)
        self._zones: list         = []
        self._in_nfz: bool        = False
        self._near_nfz: bool      = False   # proximity warning active
        self._last_near_dist: float = 0.0   # debounce: last emitted distance
        self._nfz_file: str       = ""

        if geojson_path:
            self.loadNFZFromFile(geojson_path)

    # ── private helpers ───────────────────────────────────────────────────────

    def _build_zone_dict(self, feature: dict, index: int) -> dict:
        """
        Convert one GeoJSON Feature into the zone dict consumed by QML.

        Schema of the returned dict
        ---------------------------
        {
          "id"           : str,
          "name"         : str,
          "geometry_type": "Point" | "Polygon" | "MultiPolygon",
          "centroid_lat" : float,
          "centroid_lon" : float,
          "radius_m"     : float,   # always present
          "rings"        : [        # one entry per polygon ring / sub-polygon
              [{"lat": …, "lon": …}, …],
              …
          ],
        }

        For MultiPolygon each polygon's OUTER ring is a separate entry in
        `rings` so QML ray-casting tests every sub-polygon.
        """
        props  = feature.get("properties") or {}
        geom   = feature.get("geometry")   or {}
        g_type = geom.get("type", "")
        coords = geom.get("coordinates", [])

        name = (
            props.get("name")
            or props.get("Name")
            or props.get("NAME")
            or props.get("title")
            or f"NFZ Zone {index + 1}"
        )
        zone_id = props.get("id") or props.get("ID") or f"nfz_{index}"

        # ── extract rings ────────────────────────────────────────────────────
        rings: list = []

        if g_type == "Polygon":
            # coords = [ outer_ring, *inner_holes ]
            # We add ALL rings (outer + holes); ray-casting on the outer ring
            # is what matters for "inside" checks.  Holes would invert the
            # result but that is acceptable for safety-first NFZ blocking.
            for ring_coords in coords:
                if ring_coords:
                    rings.append([{"lat": c[1], "lon": c[0]} for c in ring_coords])

        elif g_type == "MultiPolygon":
            # coords = [ polygon, … ]  where polygon = [ outer_ring, *holes ]
            # Add EVERY polygon's outer ring as a separate entry so every
            # sub-polygon is checked independently.
            for polygon in coords:
                if polygon:
                    outer_ring = polygon[0]   # index 0 = outer boundary
                    if outer_ring:
                        rings.append([{"lat": c[1], "lon": c[0]} for c in outer_ring])
                    # Also add hole rings (optional – keeps safety conservative)
                    for hole in polygon[1:]:
                        if hole:
                            rings.append([{"lat": c[1], "lon": c[0]} for c in hole])

        # ── centroid ─────────────────────────────────────────────────────────
        if g_type == "Point" and len(coords) >= 2:
            c_lat, c_lon = float(coords[1]), float(coords[0])
        elif rings:
            c_lat, c_lon = _centroid_of_ring(rings[0])
        else:
            c_lat, c_lon = 0.0, 0.0

        # ── radius_m ─────────────────────────────────────────────────────────
        # Priority:
        #   1. explicit property  radius_m / radius_km / radius
        #   2. bounding radius of the outer polygon ring
        #   3. fallback 500 m
        radius_m: float = 0.0

        for key in ("radius_m", "Radius_m", "RADIUS_M"):
            if key in props:
                try:
                    radius_m = float(props[key])
                    break
                except (TypeError, ValueError):
                    pass

        if radius_m <= 0:
            for key in ("radius_km", "Radius_km", "RADIUS_KM"):
                if key in props:
                    try:
                        radius_m = float(props[key]) * 1000
                        break
                    except (TypeError, ValueError):
                        pass

        if radius_m <= 0:
            for key in ("radius", "Radius", "RADIUS"):
                if key in props:
                    try:
                        radius_m = float(props[key])
                        break
                    except (TypeError, ValueError):
                        pass

        if radius_m <= 0 and rings:
            radius_m = _radius_of_ring(rings[0], c_lat, c_lon)

        if radius_m <= 0:
            radius_m = 500.0

        return {
            "id":            zone_id,
            "name":          name,
            "geometry_type": g_type,
            "centroid_lat":  c_lat,
            "centroid_lon":  c_lon,
            "radius_m":      radius_m,
            "rings":         rings,
        }

    # ── QML properties ────────────────────────────────────────────────────────

    @pyqtProperty(list, notify=nfzDataChanged)
    def nfzZones(self) -> list:
        return self._zones

    @pyqtProperty(int, notify=nfzDataChanged)
    def nfzCount(self) -> int:
        return len(self._zones)

    # ── QML slots ─────────────────────────────────────────────────────────────

    @pyqtSlot()
    @pyqtSlot(str)
    def loadNFZFromFile(self, file_path: str = "") -> None:
        """Load (or reload) NFZ zones from a GeoJSON file."""
        if not file_path:
            print("[NFZManager] ⚠️  loadNFZFromFile() called with no path — skipping")
            return
        path = file_path.replace("file://", "")
        if not os.path.exists(path):
            print(f"[NFZManager] ❌ File not found: {path}")
            return

        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            print(f"[NFZManager] ❌ Failed to parse GeoJSON: {exc}")
            return

        features = data.get("features", [])
        self._zones = []
        skipped = 0
        for i, feat in enumerate(features):
            try:
                zone = self._build_zone_dict(feat, i)
                self._zones.append(zone)
            except Exception as exc:
                skipped += 1
                print(f"[NFZManager] ⚠️  Skipped feature {i}: {exc}")

        self._nfz_file = path

        print(f"[NFZManager] ✅ Loaded {len(self._zones)} NFZ zone(s) "
              f"(skipped {skipped}) from {os.path.basename(path)}")
        for z in self._zones[:10]:   # print first 10 only
            print(f"  • {z['name']:40s}  type={z['geometry_type']:12s}"
                  f"  rings={len(z['rings']):3d}  r={z['radius_m']:.0f}m")
        if len(self._zones) > 10:
            print(f"  … and {len(self._zones) - 10} more zones")

        self.nfzDataChanged.emit()

    @pyqtSlot(float, float)
    def checkDronePosition(self, lat: float, lon: float) -> None:
        """
        Call from a telemetry timer to detect live NFZ breaches AND proximity.

        State machine:
          • NORMAL  → within PROXIMITY_WARNING_M of an NFZ boundary → NEAR  (droneNearNFZ)
          • NEAR    → inside NFZ                                     → IN    (droneInNFZ)
          • IN      → outside NFZ but still within proximity         → NEAR  (droneInNFZ exits, droneNearNFZ re-fires)
          • NEAR    → outside proximity                              → NORMAL (droneExitedProximity)
          • IN      → outside proximity in one step                  → NORMAL (both exit signals emitted)
        """
        breached, zone_name = self._check_position(lat, lon)
        near_zone, near_dist = self._check_proximity(lat, lon)

        # ── inside NFZ ──────────────────────────────────────────────────────
        if breached:
            if not self._in_nfz:
                self._in_nfz = True
                self._near_nfz = True   # in NFZ implies near NFZ
                self.droneInNFZ.emit(zone_name)
                print(f"[NFZManager] 🚨 Drone ENTERED NFZ: {zone_name}")

        # ── exited NFZ ──────────────────────────────────────────────────────
        elif self._in_nfz:
            self._in_nfz = False
            self.droneExitedNFZ.emit()
            print(f"[NFZManager] ✅ Drone exited NFZ")
            # Check if still in proximity zone
            if near_zone:
                if not self._near_nfz:
                    self._near_nfz = True
                self.droneNearNFZ.emit(near_zone, near_dist)
            else:
                self._near_nfz = False
                self.droneExitedProximity.emit()

        # ── near NFZ (not inside) ────────────────────────────────────────────
        elif near_zone:
            if not self._near_nfz:
                self._near_nfz = True
                self.droneNearNFZ.emit(near_zone, near_dist)
                print(f"[NFZManager] ⚠️  Drone near NFZ: {near_zone}  dist={near_dist:.0f}m")
            else:
                # Still near – only re-emit if distance changed significantly (>10 m)
                if abs(near_dist - self._last_near_dist) > 10.0:
                    self._last_near_dist = near_dist
                    self.droneNearNFZ.emit(near_zone, near_dist)

        # ── clear ────────────────────────────────────────────────────────────
        else:
            if self._near_nfz:
                self._near_nfz = False
                self.droneExitedProximity.emit()
                print(f"[NFZManager] ✅ Drone cleared NFZ proximity")

    def _check_proximity(self, lat: float, lon: float):
        """
        Return (nearest_zone_name, distance_m) if the drone is within
        PROXIMITY_WARNING_M metres of any NFZ boundary, else ("", 0.0).

        Distance is measured from the edge of the bounding circle
        (i.e. radius_m from centroid) – not from the centroid itself –
        so it matches what the user sees as the red circle boundary.
        """
        closest_name = ""
        closest_dist = float("inf")

        for zone in self._zones:
            name     = zone.get("name", "NFZ Zone")
            radius_m = zone.get("radius_m", 0.0)
            c_lat    = zone.get("centroid_lat", 0.0)
            c_lon    = zone.get("centroid_lon", 0.0)

            if radius_m <= 0:
                continue

            dist_to_center = _haversine_m(lat, lon, c_lat, c_lon)
            # Distance from drone to the NFZ boundary edge
            dist_to_edge = dist_to_center - radius_m

            if dist_to_edge < 0:
                # Already inside – let _check_position handle this
                return name, 0.0

            if dist_to_edge <= self.PROXIMITY_WARNING_M:
                if dist_to_edge < closest_dist:
                    closest_dist = dist_to_edge
                    closest_name = name

        if closest_name:
            return closest_name, closest_dist
        return "", 0.0

    @pyqtSlot(float, float, result=bool)
    def isDroneInNFZ(self, lat: float, lon: float) -> bool:
        """Return True if (lat, lon) is inside any NFZ zone."""
        breached, _ = self._check_position(lat, lon)
        return breached

    @pyqtSlot(float, float, result=bool)
    def isWaypointInNFZ(self, lat: float, lon: float) -> bool:
        """
        Explicit slot for checking waypoint placement.
        If blocked, also emits waypointBlockedByNFZ signal.
        Returns True if the point is inside an NFZ.
        """
        breached, zone_name = self._check_position(lat, lon)
        if breached:
            print(f"[NFZManager] 🚫 Waypoint ({lat:.6f}, {lon:.6f}) blocked by: {zone_name}")
            self.waypointBlockedByNFZ.emit(lat, lon, zone_name)
        return breached

    # ── Python-side position check ────────────────────────────────────────────

    def _check_position(self, lat: float, lon: float):
        """
        Return (is_breached: bool, zone_name: str).

        Uses the same two-layer logic as QML isPointInNFZ() so that
        what the user sees (the red circle) exactly matches what is blocked:

          Layer 1 – Bounding-circle check (radius_m):
            Every zone has radius_m = bounding radius of its polygon.
            The QML overlay draws this SAME circle in red.
            If the point is within radius_m of the centroid → blocked.
            If outside → cannot be inside the polygon → skip the zone.

          Layer 2 – Polygon ray-cast fallback:
            Only reached for zones that have no radius_m (malformed data).

          Layer 3 – Explicit Point-geometry circle:
            For zones whose geometry type is "Point" and had no radius_m
            computed in Layer 1.
        """
        for zone in self._zones:
            rings    = zone.get("rings", [])
            name     = zone.get("name", "NFZ Zone")
            g_type   = zone.get("geometry_type", "")
            radius_m = zone.get("radius_m", 0.0)
            c_lat    = zone.get("centroid_lat", 0.0)
            c_lon    = zone.get("centroid_lon", 0.0)

            # ── Layer 1: bounding-circle check (matches QML visual) ──────────
            if radius_m > 0:
                dist = _haversine_m(lat, lon, c_lat, c_lon)
                if dist <= radius_m:
                    return True, name
                # Outside bounding circle → cannot be inside polygon → skip
                continue

            # ── Layer 2: polygon ray-cast fallback ───────────────────────────
            if rings:
                for ring in rings:
                    if _ray_cast_inside(lat, lon, ring):
                        return True, name

            # ── Layer 3: explicit Point/circle ───────────────────────────────
            if g_type == "Point" and radius_m > 0:
                dist = _haversine_m(lat, lon, c_lat, c_lon)
                if dist <= radius_m:
                    return True, name

        return False, ""
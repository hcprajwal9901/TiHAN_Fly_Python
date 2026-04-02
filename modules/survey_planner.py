"""
TiHAN Fly - Survey Planning Module
Generates survey paths inside polygons with camera trigger support
"""

from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty
import math
import json
from typing import List, Tuple, Dict


class SurveyConfig(QObject):
    """Survey configuration parameters"""
    
    configChanged = pyqtSignal()
    
    def __init__(self):
        super().__init__()
        self._altitude = 50.0  # meters
        self._line_spacing = 20.0  # meters
        self._angle = 0.0  # degrees (0 = north-south)
        self._overlap = 70.0  # percent
        self._sidelap = 60.0  # percent
        self._speed = 5.0  # m/s
        self._camera_trigger_distance = 0  # 0 = auto-calculate
        self._entry_point = "bottom_left"  # bottom_left, top_left, etc.
        self._turnaround_distance = 10.0  # meters
    
    @pyqtProperty(float, notify=configChanged)
    def altitude(self):
        return self._altitude
    
    @altitude.setter
    def altitude(self, value):
        if value != self._altitude and value > 0:
            self._altitude = value
            self.configChanged.emit()
    
    @pyqtProperty(float, notify=configChanged)
    def lineSpacing(self):
        return self._line_spacing
    
    @lineSpacing.setter
    def lineSpacing(self, value):
        if value != self._line_spacing and value > 0:
            self._line_spacing = value
            self.configChanged.emit()
    
    @pyqtProperty(float, notify=configChanged)
    def angle(self):
        return self._angle
    
    @angle.setter
    def angle(self, value):
        if value != self._angle:
            self._angle = value % 360
            self.configChanged.emit()
    
    @pyqtProperty(float, notify=configChanged)
    def overlap(self):
        return self._overlap
    
    @overlap.setter
    def overlap(self, value):
        if value != self._overlap and 0 <= value <= 100:
            self._overlap = value
            self.configChanged.emit()
    
    @pyqtProperty(float, notify=configChanged)
    def sidelap(self):
        return self._sidelap
    
    @sidelap.setter
    def sidelap(self, value):
        if value != self._sidelap and 0 <= value <= 100:
            self._sidelap = value
            self.configChanged.emit()
    
    @pyqtProperty(float, notify=configChanged)
    def speed(self):
        return self._speed
    
    @speed.setter
    def speed(self, value):
        if value != self._speed and value > 0:
            self._speed = value
            self.configChanged.emit()
    
    @pyqtProperty(str, notify=configChanged)
    def entryPoint(self):
        return self._entry_point
    
    @entryPoint.setter
    def entryPoint(self, value):
        if value != self._entry_point:
            self._entry_point = value
            self.configChanged.emit()


class SurveyPlanner(QObject):
    """Survey path generator"""
    
    pathGenerated = pyqtSignal('QVariantList')  # List of waypoints
    progressUpdate = pyqtSignal(int, str)  # percentage, status message
    errorOccurred = pyqtSignal(str)
    
    def __init__(self, polygon_planner):
        super().__init__()
        self.polygon_planner = polygon_planner
        self.config = SurveyConfig()
        self._last_generated_path = []
    
    @pyqtSlot(str, result=bool)
    def generateSurvey(self, polygon_id):
        """Generate survey path for given polygon"""
        print(f"\n{'='*60}")
        print(f"[SurveyPlanner] Starting survey generation for {polygon_id}")
        print(f"{'='*60}")
        
        try:
            # Step 1: Get polygon
            self.progressUpdate.emit(10, "Loading polygon...")
            polygon = self.polygon_planner.get_polygon_object(polygon_id)
            
            if not polygon or not polygon.isClosed:
                self.errorOccurred.emit("Polygon must be closed before generating survey")
                return False
            
            points_latlon = polygon.get_raw_points()
            if len(points_latlon) < 3:
                self.errorOccurred.emit("Polygon must have at least 3 points")
                return False
            
            print(f"[SurveyPlanner] Polygon: {len(points_latlon)} vertices")
            
            # Step 2: Convert to local ENU coordinates
            self.progressUpdate.emit(20, "Converting coordinates...")
            centroid = self._calculate_centroid(points_latlon)
            points_enu = [self._latlon_to_enu(p, centroid) for p in points_latlon]
            
            print(f"[SurveyPlanner] Centroid: {centroid}")
            print(f"[SurveyPlanner] ENU conversion complete")
            
            # Step 3: Rotate polygon by -angle
            self.progressUpdate.emit(30, "Rotating polygon...")
            angle_rad = -math.radians(self.config.angle)
            points_rotated = [self._rotate_point(p, angle_rad) for p in points_enu]
            
            print(f"[SurveyPlanner] Rotation angle: {self.config.angle}°")
            
            # Step 4: Generate parallel lines
            self.progressUpdate.emit(40, "Generating scan lines...")
            lines = self._generate_parallel_lines(points_rotated, self.config.lineSpacing)
            
            print(f"[SurveyPlanner] Generated {len(lines)} scan lines")
            
            # Step 5: Clip lines with polygon
            self.progressUpdate.emit(50, "Clipping lines to polygon...")
            clipped_segments = []
            for line_y in lines:
                segments = self._clip_line_to_polygon(line_y, points_rotated)
                clipped_segments.extend(segments)
            
            print(f"[SurveyPlanner] Clipped to {len(clipped_segments)} segments")
            
            if not clipped_segments:
                self.errorOccurred.emit("No valid survey lines generated")
                return False
            
            # Step 6: Order segments (lawn-mower pattern)
            self.progressUpdate.emit(60, "Optimizing path order...")
            ordered_path = self._order_segments_lawnmower(clipped_segments)
            
            print(f"[SurveyPlanner] Path optimized: {len(ordered_path)} waypoints")
            
            # Step 7: Rotate back to original orientation
            self.progressUpdate.emit(70, "Converting back to GPS...")
            path_enu = [self._rotate_point(p, -angle_rad) for p in ordered_path]
            
            # Step 8: Convert back to lat/lon
            path_latlon = [self._enu_to_latlon(p, centroid) for p in path_enu]
            
            print(f"[SurveyPlanner] Converted to GPS coordinates")
            
            # Step 9: Create waypoint objects
            self.progressUpdate.emit(80, "Creating waypoints...")
            waypoints = []
            
            for i, (lat, lon) in enumerate(path_latlon):
                wp = {
                    "seq": i + 1,
                    "lat": lat,
                    "lon": lon,
                    "altitude": self.config.altitude,
                    "speed": self.config.speed,
                    "type": "survey_waypoint",
                    "command": 16,  # MAV_CMD_NAV_WAYPOINT
                    "frame": 3,  # MAV_FRAME_GLOBAL_RELATIVE_ALT
                    "autocontinue": 1
                }
                waypoints.append(wp)
            
            # Step 10: Calculate statistics
            self.progressUpdate.emit(90, "Calculating statistics...")
            total_distance = self._calculate_path_distance(path_latlon)
            flight_time = total_distance / self.config.speed if self.config.speed > 0 else 0
            
            print(f"\n{'='*60}")
            print(f"[SurveyPlanner] ✅ Survey Generation Complete!")
            print(f"{'='*60}")
            print(f"  Waypoints: {len(waypoints)}")
            print(f"  Total distance: {total_distance:.1f} m ({total_distance/1000:.2f} km)")
            print(f"  Estimated flight time: {flight_time/60:.1f} minutes")
            print(f"  Altitude: {self.config.altitude} m")
            print(f"  Line spacing: {self.config.lineSpacing} m")
            print(f"  Survey angle: {self.config.angle}°")
            print(f"{'='*60}\n")
            
            # Store and emit
            self._last_generated_path = waypoints
            self.pathGenerated.emit(waypoints)
            self.progressUpdate.emit(100, f"✅ Complete! {len(waypoints)} waypoints")
            
            return True
            
        except Exception as e:
            print(f"[SurveyPlanner] ❌ ERROR: {e}")
            import traceback
            traceback.print_exc()
            self.errorOccurred.emit(f"Survey generation failed: {str(e)}")
            return False
    
    @pyqtProperty('QVariantList')
    def lastGeneratedPath(self):
        """Get the last generated survey path"""
        return self._last_generated_path
    
    @pyqtSlot(result=str)
    def exportSurveyJSON(self):
        """Export survey path as JSON"""
        if not self._last_generated_path:
            return "{}"
        
        data = {
            "type": "TiHAN_Survey",
            "version": "1.0",
            "config": {
                "altitude": self.config.altitude,
                "line_spacing": self.config.lineSpacing,
                "angle": self.config.angle,
                "speed": self.config.speed,
                "overlap": self.config.overlap,
                "sidelap": self.config.sidelap
            },
            "waypoints": self._last_generated_path,
            "statistics": {
                "waypoint_count": len(self._last_generated_path),
                "total_distance_m": self._calculate_path_distance(
                    [(w["lat"], w["lon"]) for w in self._last_generated_path]
                )
            }
        }
        
        return json.dumps(data, indent=2)
    
    # ============================================================
    # GEOMETRIC ALGORITHMS
    # ============================================================
    
    def _calculate_centroid(self, points):
        """Calculate polygon centroid"""
        lat_sum = sum(p[0] for p in points)
        lon_sum = sum(p[1] for p in points)
        n = len(points)
        return (lat_sum / n, lon_sum / n)
    
    def _latlon_to_enu(self, point, origin):
        """Convert lat/lon to local ENU (East-North-Up) coordinates"""
        lat, lon = point
        lat0, lon0 = origin
        
        # Earth radius
        R = 6371000  # meters
        
        # Convert to radians
        lat_rad = math.radians(lat)
        lon_rad = math.radians(lon)
        lat0_rad = math.radians(lat0)
        lon0_rad = math.radians(lon0)
        
        # ENU conversion (flat-earth approximation for small areas)
        e = R * (lon_rad - lon0_rad) * math.cos(lat0_rad)  # East
        n = R * (lat_rad - lat0_rad)  # North
        
        return (e, n)
    
    def _enu_to_latlon(self, point, origin):
        """Convert local ENU back to lat/lon"""
        e, n = point
        lat0, lon0 = origin
        
        R = 6371000  # meters
        lat0_rad = math.radians(lat0)
        
        # Reverse conversion
        lat = lat0 + math.degrees(n / R)
        lon = lon0 + math.degrees(e / (R * math.cos(lat0_rad)))
        
        return (lat, lon)
    
    def _rotate_point(self, point, angle_rad):
        """Rotate point around origin"""
        x, y = point
        cos_a = math.cos(angle_rad)
        sin_a = math.sin(angle_rad)
        
        x_new = x * cos_a - y * sin_a
        y_new = x * sin_a + y * cos_a
        
        return (x_new, y_new)
    
    def _generate_parallel_lines(self, polygon_points, spacing):
        """Generate horizontal lines with given spacing"""
        # Find bounding box
        y_coords = [p[1] for p in polygon_points]
        min_y = min(y_coords)
        max_y = max(y_coords)
        
        # Generate lines
        lines = []
        current_y = min_y
        
        while current_y <= max_y:
            lines.append(current_y)
            current_y += spacing
        
        return lines
    
    def _clip_line_to_polygon(self, line_y, polygon_points):
        """Find where horizontal line intersects polygon"""
        intersections = []
        n = len(polygon_points)
        
        # Check each edge
        for i in range(n):
            p1 = polygon_points[i]
            p2 = polygon_points[(i + 1) % n]
            
            x1, y1 = p1
            x2, y2 = p2
            
            # Check if edge crosses the horizontal line
            if (y1 <= line_y <= y2) or (y2 <= line_y <= y1):
                if y1 == y2:  # Horizontal edge
                    continue
                
                # Calculate intersection x-coordinate
                t = (line_y - y1) / (y2 - y1)
                x_intersect = x1 + t * (x2 - x1)
                
                intersections.append(x_intersect)
        
        # Sort intersections and create segments
        intersections.sort()
        segments = []
        
        # Pair up intersections (entry/exit points)
        for i in range(0, len(intersections) - 1, 2):
            if i + 1 < len(intersections):
                start = (intersections[i], line_y)
                end = (intersections[i + 1], line_y)
                segments.append((start, end))
        
        return segments
    
    def _order_segments_lawnmower(self, segments):
        """Order segments in lawn-mower (boustrophedon) pattern"""
        if not segments:
            return []
        
        # Group segments by y-coordinate (scan line)
        lines = {}
        for seg in segments:
            y = seg[0][1]  # y-coordinate of segment
            if y not in lines:
                lines[y] = []
            lines[y].append(seg)
        
        # Sort lines by y-coordinate
        sorted_y = sorted(lines.keys())
        
        # Create path
        path = []
        reverse = False
        
        for y in sorted_y:
            line_segments = lines[y]
            
            # Sort segments by x-coordinate
            line_segments.sort(key=lambda s: s[0][0])
            
            # Reverse every other line for lawn-mower pattern
            if reverse:
                line_segments.reverse()
            
            # Add points
            for seg in line_segments:
                if reverse:
                    path.append(seg[1])  # End point
                    path.append(seg[0])  # Start point
                else:
                    path.append(seg[0])  # Start point
                    path.append(seg[1])  # End point
            
            reverse = not reverse
        
        return path
    
    def _calculate_path_distance(self, path_latlon):
        """Calculate total path distance using Haversine formula"""
        if len(path_latlon) < 2:
            return 0.0
        
        total_distance = 0.0
        R = 6371000  # Earth radius in meters
        
        for i in range(len(path_latlon) - 1):
            lat1, lon1 = path_latlon[i]
            lat2, lon2 = path_latlon[i + 1]
            
            # Haversine formula
            dlat = math.radians(lat2 - lat1)
            dlon = math.radians(lon2 - lon1)
            
            a = (math.sin(dlat / 2) ** 2 +
                 math.cos(math.radians(lat1)) *
                 math.cos(math.radians(lat2)) *
                 math.sin(dlon / 2) ** 2)
            
            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
            distance = R * c
            
            total_distance += distance
        
        return total_distance
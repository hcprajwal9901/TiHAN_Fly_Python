"""
TiHAN Fly - Polygon Planning Module
Handles polygon creation, editing, validation, and storage
"""

from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty
import json
import math
from typing import List, Dict, Tuple


class Polygon(QObject):
    """Represents a geographic polygon for survey planning"""
    
    polygonChanged = pyqtSignal()
    
    def __init__(self, name="Polygon", points=None):
        super().__init__()
        self.name = name
        self._points = points if points else []
        self._is_closed = False
    
    @pyqtProperty(str, notify=polygonChanged)
    def polygonName(self):
        return self.name
    
    @pyqtProperty('QVariantList', notify=polygonChanged)
    def points(self):
        """Return list of {lat, lon} dictionaries"""
        return [{"lat": p[0], "lon": p[1]} for p in self._points]
    
    @pyqtSlot(float, float)
    def addPoint(self, lat, lon):
        """Add a point to the polygon"""
        self._points.append((lat, lon))
        self.polygonChanged.emit()
    
    @pyqtSlot(int)
    def removePoint(self, index):
        """Remove a point at given index"""
        if 0 <= index < len(self._points):
            self._points.pop(index)
            self.polygonChanged.emit()
    
    @pyqtSlot(int, float, float)
    def updatePoint(self, index, lat, lon):
        """Update point coordinates"""
        if 0 <= index < len(self._points):
            self._points[index] = (lat, lon)
            self.polygonChanged.emit()
    
    @pyqtSlot()
    def clear(self):
        """Clear all points"""
        self._points = []
        self._is_closed = False
        self.polygonChanged.emit()
    
    @pyqtSlot()
    def closePolygon(self):
        """Mark polygon as closed"""
        if len(self._points) >= 3:
            self._is_closed = True
            self.polygonChanged.emit()
    
    @pyqtProperty(bool, notify=polygonChanged)
    def isClosed(self):
        return self._is_closed and len(self._points) >= 3
    
    @pyqtProperty(int, notify=polygonChanged)
    def pointCount(self):
        return len(self._points)
    
    def get_raw_points(self):
        """Get raw point tuples for internal calculations"""
        return self._points.copy()


class PolygonPlanner(QObject):
    """Main polygon planning manager"""
    
    polygonListChanged = pyqtSignal()
    activePolygonChanged = pyqtSignal()
    calculationComplete = pyqtSignal(str, 'QVariant')  # metric name, value
    
    def __init__(self):
        super().__init__()
        self._polygons = {}  # id -> Polygon
        self._active_polygon_id = None
        self._next_id = 1
    
    @pyqtSlot(str, result='QVariant')
    def createPolygon(self, name="New Polygon"):
        """Create a new polygon and return its ID"""
        polygon_id = f"polygon_{self._next_id}"
        self._next_id += 1
        
        polygon = Polygon(name=name)
        polygon.polygonChanged.connect(self._on_polygon_changed)
        
        self._polygons[polygon_id] = polygon
        self._active_polygon_id = polygon_id
        
        self.polygonListChanged.emit()
        self.activePolygonChanged.emit()
        
        print(f"[PolygonPlanner] Created polygon: {polygon_id} ({name})")
        return polygon_id
    
    @pyqtSlot(str)
    def setActivePolygon(self, polygon_id):
        """Set the active polygon for editing"""
        if polygon_id in self._polygons:
            self._active_polygon_id = polygon_id
            self.activePolygonChanged.emit()
            print(f"[PolygonPlanner] Active polygon: {polygon_id}")
    
    @pyqtSlot(str, result=bool)
    def deletePolygon(self, polygon_id):
        """Delete a polygon"""
        if polygon_id in self._polygons:
            del self._polygons[polygon_id]
            
            if self._active_polygon_id == polygon_id:
                self._active_polygon_id = None
                self.activePolygonChanged.emit()
            
            self.polygonListChanged.emit()
            print(f"[PolygonPlanner] Deleted polygon: {polygon_id}")
            return True
        return False
    
    @pyqtProperty('QVariant', notify=polygonListChanged)
    def polygonList(self):
        """Return list of all polygons with metadata"""
        result = []
        for pid, polygon in self._polygons.items():
            result.append({
                "id": pid,
                "name": polygon.name,
                "points": polygon.pointCount,
                "closed": polygon.isClosed,
                "area": self._calculate_area_sqm(polygon) if polygon.isClosed else 0
            })
        return result
    
    @pyqtProperty('QVariant', notify=activePolygonChanged)
    def activePolygon(self):
        """Return the active polygon object"""
        if self._active_polygon_id and self._active_polygon_id in self._polygons:
            return self._polygons[self._active_polygon_id]
        return None
    
    @pyqtSlot(float, float)
    def addPointToActive(self, lat, lon):
        """Add point to active polygon"""
        if self._active_polygon_id and self._active_polygon_id in self._polygons:
            self._polygons[self._active_polygon_id].addPoint(lat, lon)
            print(f"[PolygonPlanner] Added point: ({lat:.6f}, {lon:.6f})")
    
    @pyqtSlot()
    def closeActivePolygon(self):
        """Close the active polygon"""
        if self._active_polygon_id and self._active_polygon_id in self._polygons:
            polygon = self._polygons[self._active_polygon_id]
            polygon.closePolygon()
            
            # Calculate and emit area
            area_sqm = self._calculate_area_sqm(polygon)
            area_acres = area_sqm * 0.000247105
            area_hectares = area_sqm / 10000
            
            self.calculationComplete.emit("area_sqm", area_sqm)
            self.calculationComplete.emit("area_acres", area_acres)
            self.calculationComplete.emit("area_hectares", area_hectares)
            
            print(f"[PolygonPlanner] Polygon closed - Area: {area_sqm:.2f} m² ({area_acres:.3f} acres)")
    
    @pyqtSlot(str, result='QVariant')
    def getPolygonData(self, polygon_id):
        """Get complete polygon data for given ID"""
        if polygon_id in self._polygons:
            polygon = self._polygons[polygon_id]
            return {
                "id": polygon_id,
                "name": polygon.name,
                "points": polygon.points,
                "closed": polygon.isClosed,
                "area_sqm": self._calculate_area_sqm(polygon) if polygon.isClosed else 0
            }
        return None
    
    @pyqtSlot(str, result=str)
    def exportPolygonJSON(self, polygon_id):
        """Export polygon as JSON string"""
        if polygon_id in self._polygons:
            polygon = self._polygons[polygon_id]
            data = {
                "type": "TiHAN_Polygon",
                "version": "1.0",
                "name": polygon.name,
                "points": [{"lat": p[0], "lon": p[1]} for p in polygon.get_raw_points()],
                "closed": polygon.isClosed,
                "area_sqm": self._calculate_area_sqm(polygon) if polygon.isClosed else 0
            }
            return json.dumps(data, indent=2)
        return "{}"
    
    @pyqtSlot(str, str, result=bool)
    def importPolygonJSON(self, json_string, name="Imported Polygon"):
        """Import polygon from JSON string"""
        try:
            data = json.loads(json_string)
            
            if data.get("type") != "TiHAN_Polygon":
                print("[PolygonPlanner] Invalid polygon format")
                return False
            
            polygon_id = self.createPolygon(name=data.get("name", name))
            polygon = self._polygons[polygon_id]
            
            for point in data.get("points", []):
                polygon.addPoint(point["lat"], point["lon"])
            
            if data.get("closed", False):
                polygon.closePolygon()
            
            print(f"[PolygonPlanner] Imported polygon: {polygon_id}")
            return True
            
        except Exception as e:
            print(f"[PolygonPlanner] Import failed: {e}")
            return False
    
    @pyqtSlot(str, result=bool)
    def validatePolygon(self, polygon_id):
        """Validate polygon geometry"""
        if polygon_id not in self._polygons:
            return False
        
        polygon = self._polygons[polygon_id]
        points = polygon.get_raw_points()
        
        # Check minimum points
        if len(points) < 3:
            print("[PolygonPlanner] Validation failed: < 3 points")
            return False
        
        # Check for self-intersection (simple check)
        if self._has_self_intersection(points):
            print("[PolygonPlanner] Validation failed: self-intersection")
            return False
        
        # Check area
        area = self._calculate_area_sqm(polygon)
        if area < 1:  # Less than 1 m²
            print("[PolygonPlanner] Validation failed: area too small")
            return False
        
        print(f"[PolygonPlanner] Polygon validated: {len(points)} points, {area:.2f} m²")
        return True
    
    def _on_polygon_changed(self):
        """Handle polygon updates"""
        self.polygonListChanged.emit()
    
    def _calculate_area_sqm(self, polygon):
        """Calculate polygon area in square meters using Shoelace formula with Haversine"""
        points = polygon.get_raw_points()
        
        if len(points) < 3:
            return 0.0
        
        # Earth radius in meters
        R = 6371000
        
        # Convert to radians
        coords = [(math.radians(lat), math.radians(lon)) for lat, lon in points]
        
        # Shoelace formula in spherical coordinates (approximation)
        area = 0.0
        n = len(coords)
        
        for i in range(n):
            lat1, lon1 = coords[i]
            lat2, lon2 = coords[(i + 1) % n]
            
            area += (lon2 - lon1) * (2 + math.sin(lat1) + math.sin(lat2))
        
        area = abs(area * R * R / 2.0)
        
        return area
    
    def _has_self_intersection(self, points):
        """Simple self-intersection check"""
        if len(points) < 4:
            return False
        
        # Check if any edge crosses another non-adjacent edge
        n = len(points)
        for i in range(n):
            for j in range(i + 2, n):
                if j == (i + n - 1) % n:  # Skip adjacent edges
                    continue
                
                if self._segments_intersect(
                    points[i], points[(i + 1) % n],
                    points[j], points[(j + 1) % n]
                ):
                    return True
        
        return False
    
    def _segments_intersect(self, p1, p2, p3, p4):
        """Check if two line segments intersect"""
        def ccw(A, B, C):
            return (C[1] - A[1]) * (B[0] - A[0]) > (B[1] - A[1]) * (C[0] - A[0])
        
        return ccw(p1, p3, p4) != ccw(p2, p3, p4) and ccw(p1, p2, p3) != ccw(p1, p2, p4)
    
    def get_polygon_object(self, polygon_id):
        """Get polygon object for survey planner (internal use)"""
        return self._polygons.get(polygon_id)
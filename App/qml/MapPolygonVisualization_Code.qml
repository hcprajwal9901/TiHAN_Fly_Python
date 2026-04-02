// ===================================
// MAP POLYGON VISUALIZATION HELPERS
// Add these to your MapViewQML.qml component
// ===================================

// Add these properties to MapViewQML:
property var polygonPath: []
property bool showPolygon: false

// Add this MapPolyline component inside your Map component:

MapPolyline {
    id: polygonLine
    visible: showPolygon && polygonPath.length > 1
    line.width: 3
    line.color: "#007bff"
    path: {
        var coordinates = []
        for (var i = 0; i < polygonPath.length; i++) {
            coordinates.push(QtPositioning.coordinate(
                polygonPath[i].lat,
                polygonPath[i].lng
            ))
        }
        // Close the polygon by connecting back to first point
        if (coordinates.length > 2) {
            coordinates.push(coordinates[0])
        }
        return coordinates
    }
}

// Add semi-transparent polygon fill
MapPolygon {
    id: polygonFill
    visible: showPolygon && polygonPath.length > 2
    color: "#007bff30"  // Semi-transparent blue
    border.color: "#007bff"
    border.width: 2
    path: {
        var coordinates = []
        for (var i = 0; i < polygonPath.length; i++) {
            coordinates.push(QtPositioning.coordinate(
                polygonPath[i].lat,
                polygonPath[i].lng
            ))
        }
        return coordinates
    }
}

// Add polygon vertex markers
Repeater {
    id: polygonVertexMarkers
    model: showPolygon ? polygonPath.length : 0
    
    MapQuickItem {
        coordinate: QtPositioning.coordinate(
            polygonPath[index].lat,
            polygonPath[index].lng
        )
        anchorPoint.x: vertexMarker.width / 2
        anchorPoint.y: vertexMarker.height / 2
        
        sourceItem: Rectangle {
            id: vertexMarker
            width: 16
            height: 16
            radius: 8
            color: "#007bff"
            border.color: "white"
            border.width: 2
            
            // Vertex number
            Text {
                anchors.centerIn: parent
                text: (index + 1).toString()
                color: "white"
                font.pixelSize: 10
                font.bold: true
            }
            
            // Delete button on hover
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                
                onEntered: {
                    vertexMarker.width = 24
                    vertexMarker.height = 24
                }
                
                onExited: {
                    vertexMarker.width = 16
                    vertexMarker.height = 16
                }
                
                onClicked: {
                    // Remove this vertex
                    var newPath = []
                    for (var i = 0; i < polygonPath.length; i++) {
                        if (i !== index) {
                            newPath.push(polygonPath[i])
                        }
                    }
                    polygonPath = newPath
                }
            }
        }
    }
}


// ===================================
// ADD THESE FUNCTIONS TO MapViewQML:
// ===================================

// Draw polygon line as points are added
function drawPolygonLine(points) {
    polygonPath = points
    showPolygon = true
    
    // Auto-zoom to fit polygon
    if (points.length > 0) {
        fitPolygonToView(points)
    }
}

// Clear polygon visualization
function clearPolygonLine() {
    polygonPath = []
    showPolygon = false
}

// Fit map view to show entire polygon
function fitPolygonToView(points) {
    if (points.length === 0) return
    
    var minLat = 999, maxLat = -999
    var minLng = 999, maxLng = -999
    
    for (var i = 0; i < points.length; i++) {
        if (points[i].lat < minLat) minLat = points[i].lat
        if (points[i].lat > maxLat) maxLat = points[i].lat
        if (points[i].lng < minLng) minLng = points[i].lng
        if (points[i].lng > maxLng) maxLng = points[i].lng
    }
    
    // Calculate center
    var centerLat = (minLat + maxLat) / 2
    var centerLng = (minLng + maxLng) / 2
    
    // Set map center
    map.center = QtPositioning.coordinate(centerLat, centerLng)
    
    // Calculate appropriate zoom level
    var latDiff = maxLat - minLat
    var lngDiff = maxLng - minLng
    var maxDiff = Math.max(latDiff, lngDiff)
    
    // Rough zoom calculation
    if (maxDiff > 1) map.zoomLevel = 8
    else if (maxDiff > 0.5) map.zoomLevel = 10
    else if (maxDiff > 0.1) map.zoomLevel = 12
    else if (maxDiff > 0.05) map.zoomLevel = 14
    else if (maxDiff > 0.01) map.zoomLevel = 16
    else map.zoomLevel = 18
}

// Get polygon area in square meters
function getPolygonArea(points) {
    if (points.length < 3) return 0
    
    var area = 0
    var R = 6371000 // Earth radius in meters
    
    for (var i = 0; i < points.length; i++) {
        var j = (i + 1) % points.length
        
        var lat1 = points[i].lat * Math.PI / 180
        var lat2 = points[j].lat * Math.PI / 180
        var lng1 = points[i].lng * Math.PI / 180
        var lng2 = points[j].lng * Math.PI / 180
        
        area += (lng2 - lng1) * (2 + Math.sin(lat1) + Math.sin(lat2))
    }
    
    area = Math.abs(area * R * R / 2)
    return area
}

// Get polygon perimeter in meters
function getPolygonPerimeter(points) {
    if (points.length < 2) return 0
    
    var perimeter = 0
    
    for (var i = 0; i < points.length; i++) {
        var j = (i + 1) % points.length
        var dist = calculateDistance(
            points[i].lat, points[i].lng,
            points[j].lat, points[j].lng
        )
        perimeter += dist
    }
    
    return perimeter
}

function calculateDistance(lat1, lon1, lat2, lon2) {
    var R = 6371000 // Earth radius in meters
    var dLat = (lat2 - lat1) * Math.PI / 180
    var dLon = (lon2 - lon1) * Math.PI / 180
    var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon/2) * Math.sin(dLon/2)
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    return R * c
}


// ===================================
// EXAMPLE USAGE IN NavigationControl.qml
// ===================================

/*
// When polygon tool adds a point:
waypointsMap.drawPolygonLine(polygonTool.polygonPoints)

// When polygon is cleared:
waypointsMap.clearPolygonLine()

// To get polygon statistics:
var area = waypointsMap.getPolygonArea(polygonTool.polygonPoints)
var perimeter = waypointsMap.getPolygonPerimeter(polygonTool.polygonPoints)

console.log("Polygon Area:", (area / 10000).toFixed(2), "hectares")
console.log("Polygon Perimeter:", (perimeter / 1000).toFixed(2), "km")
*/


// ===================================
// ENHANCED POLYGON TOOL FEATURES
// ===================================

// Add these to PolygonTool.qml for better user experience:

// Show polygon statistics
Rectangle {
    width: parent.width
    height: statsColumn.height + 20
    color: "#e3f2fd"
    radius: 6
    border.color: theme.accent
    border.width: 1
    visible: polygonPoints.length >= 3
    
    Column {
        id: statsColumn
        anchors.centerIn: parent
        width: parent.width - 20
        spacing: 5
        
        Text {
            text: "📊 Polygon Statistics"
            font.pixelSize: 12
            font.bold: true
            font.family: "Consolas"
            color: theme.textPrimary
        }
        
        Text {
            property real area: mapView ? mapView.getPolygonArea(polygonPoints) : 0
            text: "Area: " + (area / 10000).toFixed(2) + " hectares (" + 
                  (area / 1000000).toFixed(3) + " km²)"
            font.pixelSize: 10
            font.family: "Consolas"
            color: theme.textSecondary
            wrapMode: Text.WordWrap
            width: parent.width
        }
        
        Text {
            property real perimeter: mapView ? mapView.getPolygonPerimeter(polygonPoints) : 0
            text: "Perimeter: " + (perimeter / 1000).toFixed(2) + " km"
            font.pixelSize: 10
            font.family: "Consolas"
            color: theme.textSecondary
        }
        
        Text {
            property real estimatedTime: calculateEstimatedTime()
            text: "Est. Flight Time: " + formatTime(estimatedTime)
            font.pixelSize: 10
            font.family: "Consolas"
            color: theme.success
            font.bold: true
            
            function calculateEstimatedTime() {
                if (polygonPoints.length < 3) return 0
                var area = mapView ? mapView.getPolygonArea(polygonPoints) : 0
                var totalDistance = area / lineSpacing
                return totalDistance / surveySpeed
            }
            
            function formatTime(seconds) {
                var mins = Math.floor(seconds / 60)
                var secs = Math.floor(seconds % 60)
                return mins + "m " + secs + "s"
            }
        }
    }
}
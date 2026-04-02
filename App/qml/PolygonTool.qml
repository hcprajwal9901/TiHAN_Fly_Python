import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtPositioning 5.15

// ===================================
// POLYGON DRAWING TOOL COMPONENT
// ===================================
Item {
    id: polygonTool
    
    // Properties
    property var mapView: null  // Reference to the map component
    property bool isDrawingMode: false
    property var polygonPoints: []
    property real surveyAltitude: 10.0
    property real surveySpeed: 5.0
    property real lineSpacing: 10.0  // meters between survey lines
    property real surveyAngle: 0.0   // angle of survey lines (0-360 degrees)
    
    signal polygonCompleted(var waypoints)
    signal polygonCleared()
    
    // Theme colors (matching your main app)
    QtObject {
        id: theme
        property color primary: "#ffffff"
        property color accent: "#007bff"
        property color success: "#28a745"
        property color error: "#dc3545"
        property color warning: "#ffc107"
        property color cardBackground: "#ffffff"
        property color textPrimary: "#212529"
        property color textSecondary: "#6c757d"
        property color border: "#dee2e6"
        property int borderRadius: 8
    }
    
    // ✅ VISUAL INDICATOR - Shows when polygon mode is active
    Rectangle {
        id: polygonModeIndicator
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 100
        width: 280
        height: 60
        color: theme.accent
        radius: 8
        visible: isDrawingMode
        z: 250
        opacity: 0.95
        
        Row {
            anchors.centerIn: parent
            spacing: 12
            
            Text {
                text: "📐"
                font.pixelSize: 24
                color: "white"
                anchors.verticalCenter: parent.verticalCenter
            }
            
            Column {
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter
                
                Text {
                    text: "POLYGON MODE ACTIVE"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "Consolas"
                    color: "white"
                }
                
                Text {
                    text: "Click map to add points • " + polygonPoints.length + " points"
                    font.pixelSize: 10
                    font.family: "Consolas"
                    color: "#ffffff"
                    opacity: 0.9
                }
            }
        }
        
        SequentialAnimation on opacity {
            running: isDrawingMode
            loops: Animation.Infinite
            NumberAnimation { to: 0.75; duration: 800 }
            NumberAnimation { to: 0.95; duration: 800 }
        }
    }
    
    // ===================================
    // POLYGON CONTROL PANEL
    // ===================================
    Rectangle {
        id: polygonControlPanel
        width: 280
        height: columnLayout.height + 40
        color: theme.cardBackground
        radius: theme.borderRadius
        border.color: theme.border
        border.width: 1
        visible: false
        z: 200
        
        // Position - bottom left of parent
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.bottomMargin: 20
        
        Column {
            id: columnLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            
            // Header
            Rectangle {
                width: parent.width
                height: 40
                color: theme.accent
                radius: theme.borderRadius
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10
                    
                    Text {
                        text: "📐"
                        font.pixelSize: 20
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: "Polygon Survey Tool"
                        font.pixelSize: 14
                        font.bold: true
                        font.family: "Consolas"
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                Button {
                    width: 30
                    height: 30
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    contentItem: Text { 
                        text: "✖"
                        color: "white"
                        font.pixelSize: 14
                        font.family: "Consolas"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { 
                        color: parent.hovered ? "#ffffff30" : "transparent"
                        radius: 4
                    }
                    onClicked: {
                        hide()  // Use hide() function to properly cleanup
                    }
                }
            }
            
            // Instructions
            Rectangle {
                width: parent.width
                height: instructionText.height + 20
                color: "#e3f2fd"
                radius: 6
                border.color: theme.accent
                border.width: 1
                
                Text {
                    id: instructionText
                    anchors.centerIn: parent
                    width: parent.width - 20
                    text: isDrawingMode ? 
                          "🖱️ Click on map to add points\n✓ Need at least 3 points to complete" :
                          "⏸️ Drawing paused"
                    font.pixelSize: 11
                    font.family: "Consolas"
                    color: theme.textPrimary
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            
            // Point Counter
            Rectangle {
                width: parent.width
                height: 35
                color: "#f8f9fa"
                radius: 6
                border.color: theme.border
                border.width: 1
                visible: polygonPoints.length > 0
                
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    
                    Text {
                        text: "📍 Points:"
                        font.pixelSize: 12
                        font.family: "Consolas"
                        color: theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Rectangle {
                        width: 30
                        height: 25
                        radius: 4
                        color: theme.accent
                        
                        Text {
                            text: polygonPoints.length.toString()
                            font.pixelSize: 13
                            font.bold: true
                            font.family: "Consolas"
                            color: "white"
                            anchors.centerIn: parent
                        }
                    }
                }
            }
            
            // Survey Parameters
            Column {
                width: parent.width
                spacing: 10
                
                // Altitude
                Column {
                    width: parent.width
                    spacing: 5
                    
                    Text {
                        text: "Survey Altitude (m):"
                        font.pixelSize: 12
                        font.family: "Consolas"
                        color: theme.textPrimary
                    }
                    
                    Row {
                        width: parent.width
                        spacing: 5
                        
                        Button {
                            width: 35
                            height: 35
                            contentItem: Text { 
                                text: "−"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: theme.accent; radius: 4 }
                            onClicked: {
                                if (surveyAltitude > 5) surveyAltitude -= 5
                            }
                        }
                        
                        TextField {
                            id: altitudeInput
                            width: parent.width - 80
                            height: 35
                            text: surveyAltitude.toFixed(1)
                            font.pixelSize: 13
                            font.family: "Consolas"
                            horizontalAlignment: Text.AlignHCenter
                            background: Rectangle {
                                color: "#ffffff"
                                radius: 4
                                border.color: theme.border
                                border.width: 1
                            }
                            onTextChanged: {
                                var val = parseFloat(text)
                                if (!isNaN(val) && val >= 5)
                                    surveyAltitude = val
                            }
                        }
                        
                        Button {
                            width: 35
                            height: 35
                            contentItem: Text { 
                                text: "+"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: theme.accent; radius: 4 }
                            onClicked: surveyAltitude += 5
                        }
                    }
                }
                
                // Line Spacing
                Column {
                    width: parent.width
                    spacing: 5
                    
                    Text {
                        text: "Line Spacing (m):"
                        font.pixelSize: 12
                        font.family: "Consolas"
                        color: theme.textPrimary
                    }
                    
                    Row {
                        width: parent.width
                        spacing: 5
                        
                        Button {
                            width: 35
                            height: 35
                            contentItem: Text { 
                                text: "−"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: theme.accent; radius: 4 }
                            onClicked: {
                                if (lineSpacing > 2) lineSpacing -= 1
                            }
                        }
                        
                        TextField {
                            id: spacingInput
                            width: parent.width - 80
                            height: 35
                            text: lineSpacing.toFixed(1)
                            font.pixelSize: 13
                            font.family: "Consolas"
                            horizontalAlignment: Text.AlignHCenter
                            background: Rectangle {
                                color: "#ffffff"
                                radius: 4
                                border.color: theme.border
                                border.width: 1
                            }
                            onTextChanged: {
                                var val = parseFloat(text)
                                if (!isNaN(val) && val >= 2)
                                    lineSpacing = val
                            }
                        }
                        
                        Button {
                            width: 35
                            height: 35
                            contentItem: Text { 
                                text: "+"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: theme.accent; radius: 4 }
                            onClicked: lineSpacing += 1
                        }
                    }
                }
                
                // Survey Angle
                Column {
                    width: parent.width
                    spacing: 5
                    
                    Text {
                        text: "Survey Angle (°):"
                        font.pixelSize: 12
                        font.family: "Consolas"
                        color: theme.textPrimary
                    }
                    
                    Row {
                        width: parent.width
                        spacing: 5
                        
                        Button {
                            width: 35
                            height: 35
                            contentItem: Text { 
                                text: "↺"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: theme.accent; radius: 4 }
                            onClicked: {
                                surveyAngle -= 15
                                if (surveyAngle < 0) surveyAngle += 360
                            }
                        }
                        
                        TextField {
                            id: angleInput
                            width: parent.width - 80
                            height: 35
                            text: surveyAngle.toFixed(0)
                            font.pixelSize: 13
                            font.family: "Consolas"
                            horizontalAlignment: Text.AlignHCenter
                            background: Rectangle {
                                color: "#ffffff"
                                radius: 4
                                border.color: theme.border
                                border.width: 1
                            }
                            onTextChanged: {
                                var val = parseFloat(text)
                                if (!isNaN(val)) {
                                    surveyAngle = val % 360
                                    if (surveyAngle < 0) surveyAngle += 360
                                }
                            }
                        }
                        
                        Button {
                            width: 35
                            height: 35
                            contentItem: Text { 
                                text: "↻"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: theme.accent; radius: 4 }
                            onClicked: {
                                surveyAngle = (surveyAngle + 15) % 360
                            }
                        }
                    }
                }
            }
            
            // Action Buttons
            Column {
                width: parent.width
                spacing: 8
                
                // Complete Polygon Button
                Button {
                    width: parent.width
                    height: 45
                    visible: polygonPoints.length >= 3
                    
                    background: Rectangle {
                        color: parent.pressed ? "#1e7e34" : (parent.hovered ? "#218838" : theme.success)
                        radius: 6
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    contentItem: Row {
                        spacing: 10
                        anchors.centerIn: parent
                        
                        Text {
                            text: "✓"
                            font.pixelSize: 18
                            font.bold: true
                            color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: "Generate Survey Grid"
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                            font.family: "Consolas"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    onClicked: completePolygon()
                }
                
                // Clear Points Button
                Button {
                    width: parent.width
                    height: 40
                    visible: polygonPoints.length > 0
                    
                    background: Rectangle {
                        color: parent.pressed ? "#c82333" : (parent.hovered ? "#e0a800" : theme.warning)
                        radius: 6
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    contentItem: Row {
                        spacing: 8
                        anchors.centerIn: parent
                        
                        Text {
                            text: "🗑️"
                            font.pixelSize: 14
                            color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: "Clear Points"
                            color: "white"
                            font.pixelSize: 13
                            font.family: "Consolas"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    onClicked: clearPolygon()
                }
            }
        }
        
        // Drop shadow effect
        layer.enabled: true
        layer.effect: Item {
            ShaderEffect {
                property variant source
                fragmentShader: "
                    varying highp vec2 qt_TexCoord0;
                    uniform sampler2D source;
                    uniform lowp float qt_Opacity;
                    void main() {
                        gl_FragColor = texture2D(source, qt_TexCoord0) * qt_Opacity;
                    }
                "
            }
        }
    }
    
    // ===================================
    // FUNCTIONS
    // ===================================
    
function show() {
    console.log("📐 PolygonTool.show() called")
    polygonControlPanel.visible = true
    // ✅ AUTO-START drawing mode when panel opens
    startDrawingMode()
    console.log("   - After startDrawingMode(): isDrawingMode =", isDrawingMode)
}
    
    function hide() {
        console.log("📐 PolygonTool.hide() called")
        stopDrawingMode()
        clearPolygon()
        polygonControlPanel.visible = false
    }
    

function startDrawingMode() {
    console.log("📐 Starting polygon drawing mode")
    isDrawingMode = true
    polygonPoints = []
    
    if (mapView) {
        // Disable waypoint editing mode
        mapView.isEditable = false
        mapView.addMarkersMode = false
        console.log("🖊️ Polygon drawing mode activated - waypoint editing disabled")
    }
    
    console.log("   - isDrawingMode is now:", isDrawingMode)
    console.log("   - polygonTool.visible is:", visible)
}
    
    function stopDrawingMode() {
        console.log("📐 Stopping polygon drawing mode")
        isDrawingMode = false
        
        if (mapView) {
            // Re-enable waypoint editing
            mapView.isEditable = true
            console.log("✋ Polygon drawing mode deactivated - waypoint editing enabled")
        }
    }
    
    function addPoint(latitude, longitude) {
        if (!isDrawingMode) {
            console.log("⚠️ Not in drawing mode, ignoring point")
            return
        }
        
        polygonPoints.push({
            lat: latitude,
            lng: longitude
        })
        
        console.log("📍 Added polygon point #" + polygonPoints.length + ":", latitude.toFixed(6), longitude.toFixed(6))
        
        // Update visual on map
        if (mapView && typeof mapView.drawPolygonLine === 'function') {
            mapView.drawPolygonLine(polygonPoints)
        }
    }
    
    function clearPolygon() {
        console.log("🗑️ Clearing polygon points")
        polygonPoints = []
        
        if (mapView && typeof mapView.clearPolygonLine === 'function') {
            mapView.clearPolygonLine()
        }
        
        polygonCleared()
    }
    
    function completePolygon() {
        if (polygonPoints.length < 3) {
            console.log("⚠️ Need at least 3 points to create polygon (current:", polygonPoints.length, ")")
            return
        }
        
        console.log("✅ Generating survey waypoints from polygon with", polygonPoints.length, "points...")
        
        // Generate survey grid waypoints
        var surveyWaypoints = generateSurveyGrid(
            polygonPoints,
            surveyAltitude,
            surveySpeed,
            lineSpacing,
            surveyAngle
        )
        
        console.log("📊 Generated", surveyWaypoints.length, "survey waypoints")
        
        // Send waypoints to map
        if (mapView) {
            // Clear existing markers
            if (typeof mapView.clearAllMarkersJS === 'function') {
                mapView.clearAllMarkersJS()
            }
            
            // Add survey waypoints
            if (typeof mapView.addMarkerJS === 'function') {
                for (var i = 0; i < surveyWaypoints.length; i++) {
                    var wp = surveyWaypoints[i]
                    mapView.addMarkerJS(
                        wp.lat,
                        wp.lng,
                        wp.altitude,
                        wp.speed,
                        "waypoint",
                        0
                    )
                }
            }
        }
        
        // Emit signal
        polygonCompleted(surveyWaypoints)
        
        // Reset
        hide()  // This will call stopDrawingMode and clearPolygon
        
        console.log("✅ Survey grid generated successfully")
    }
    
    // ===================================
    // SURVEY GRID GENERATION ALGORITHM
    // ===================================
    function generateSurveyGrid(polygon, altitude, speed, spacing, angle) {
        var waypoints = []
        
        // Get polygon bounding box
        var bounds = getPolygonBounds(polygon)
        
        // Calculate rotated bounding box based on angle
        var angleRad = angle * Math.PI / 180
        var cosAngle = Math.cos(angleRad)
        var sinAngle = Math.sin(angleRad)
        
        // Calculate survey lines
        var lines = []
        var currentY = bounds.minLat
        var lineCount = 0
        
        while (currentY <= bounds.maxLat) {
            // Create line across width
            var line = {
                start: { lat: currentY, lng: bounds.minLng },
                end: { lat: currentY, lng: bounds.maxLng }
            }
            
            // Rotate line points
            line.start = rotatePoint(line.start, bounds.center, angleRad)
            line.end = rotatePoint(line.end, bounds.center, angleRad)
            
            // Check intersection with polygon
            var intersections = getLinePolygonIntersections(line, polygon)
            
            if (intersections.length >= 2) {
                // Sort intersections by longitude
                intersections.sort((a, b) => a.lng - b.lng)
                
                // Alternate direction (boustrophedon pattern)
                if (lineCount % 2 === 1) {
                    intersections.reverse()
                }
                
                // Add waypoints for this line
                for (var i = 0; i < intersections.length; i += 2) {
                    if (i + 1 < intersections.length) {
                        waypoints.push({
                            lat: intersections[i].lat,
                            lng: intersections[i].lng,
                            altitude: altitude,
                            speed: speed
                        })
                        
                        waypoints.push({
                            lat: intersections[i + 1].lat,
                            lng: intersections[i + 1].lng,
                            altitude: altitude,
                            speed: speed
                        })
                    }
                }
                
                lineCount++
            }
            
            // Move to next line (convert spacing from meters to degrees approximately)
            currentY += spacing / 111320  // 1 degree latitude ≈ 111.32 km
        }
        
        return waypoints
    }
    
    function getPolygonBounds(polygon) {
        var minLat = 999, maxLat = -999
        var minLng = 999, maxLng = -999
        
        for (var i = 0; i < polygon.length; i++) {
            if (polygon[i].lat < minLat) minLat = polygon[i].lat
            if (polygon[i].lat > maxLat) maxLat = polygon[i].lat
            if (polygon[i].lng < minLng) minLng = polygon[i].lng
            if (polygon[i].lng > maxLng) maxLng = polygon[i].lng
        }
        
        return {
            minLat: minLat,
            maxLat: maxLat,
            minLng: minLng,
            maxLng: maxLng,
            center: {
                lat: (minLat + maxLat) / 2,
                lng: (minLng + maxLng) / 2
            }
        }
    }
    
    function rotatePoint(point, center, angle) {
        var cosA = Math.cos(angle)
        var sinA = Math.sin(angle)
        
        var dx = point.lat - center.lat
        var dy = point.lng - center.lng
        
        return {
            lat: center.lat + (dx * cosA - dy * sinA),
            lng: center.lng + (dx * sinA + dy * cosA)
        }
    }
    
    function getLinePolygonIntersections(line, polygon) {
        var intersections = []
        
        for (var i = 0; i < polygon.length; i++) {
            var p1 = polygon[i]
            var p2 = polygon[(i + 1) % polygon.length]
            
            var intersection = getLineIntersection(
                line.start.lat, line.start.lng,
                line.end.lat, line.end.lng,
                p1.lat, p1.lng,
                p2.lat, p2.lng
            )
            
            if (intersection) {
                intersections.push(intersection)
            }
        }
        
        return intersections
    }
    
    function getLineIntersection(x1, y1, x2, y2, x3, y3, x4, y4) {
        var denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if (Math.abs(denom) < 0.0000001) return null
        
        var t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom
        var u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom
        
        if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
            return {
                lat: x1 + t * (x2 - x1),
                lng: y1 + t * (y2 - y1)
            }
        }
        
        return null
    }
}
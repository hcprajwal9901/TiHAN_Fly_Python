import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtPositioning 5.15

// Survey Mission Planner - Grid-based aerial survey
Item {
    id: surveyRoot
    anchors.fill: parent
    
    property var mapView: null
    property var surveyPolygon: []
    property var surveyWaypoints: []
    property bool isActive: false
    property bool polygonComplete: false
    
    // Survey parameters
    property real gridSpacing: 50.0        // meters between grid lines
    property real altitude: 50.0           // survey altitude in meters
    property real speed: 10.0              // flight speed m/s
    property real cameraAngle: 90.0        // camera gimbal angle (90 = straight down)
    property real overlap: 70.0            // percentage overlap between photos
    property real sideOverlap: 60.0        // side overlap percentage
    property string gridAngle: "0"         // grid rotation angle
    property bool turnaroundAtEnd: true    // add turnaround waypoints
    
    signal surveyGenerated(var waypoints)
    signal surveyCancelled()
    
    // Invisible overlay to capture map clicks when active
    MouseArea {
        anchors.fill: parent
        enabled: isActive && !polygonComplete
        propagateComposedEvents: false
        z: 50
        
        onClicked: {
            console.log("Survey click detected at:", mouse.x, mouse.y);
            // Convert screen coordinates to lat/lon
            if (mapView && mapView.map) {
                var coord = mapView.map.toCoordinate(Qt.point(mouse.x, mouse.y));
                addPolygonPoint(coord.latitude, coord.longitude);
            }
        }
    }
    
    // Main UI Panel
    Rectangle {
        id: surveyPanel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 380
        color: "#ffffff"
        border.color: "#dee2e6"
        border.width: 1
        radius: 8
        visible: isActive
        z: 150
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15
            
            // Header
            Rectangle {
                Layout.fillWidth: true
                height: 50
                color: "#28a745"
                radius: 8
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    
                    Text {
                        text: "📐 Survey Mission Planner"
                        font.pixelSize: 16
                        font.bold: true
                        font.family: "Consolas"
                        color: "white"
                        Layout.fillWidth: true
                    }
                    
                    Button {
                        width: 30
                        height: 30
                        text: "✖"
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.hovered ? "#dc3545" : "transparent"
                            radius: 4
                        }
                        onClicked: {
                            cancelSurvey();
                        }
                    }
                }
            }
            
            // Instructions
            Rectangle {
                Layout.fillWidth: true
                height: instructionText.height + 20
                color: "#e8f5e9"
                border.color: "#28a745"
                border.width: 1
                radius: 6
                
                Text {
                    id: instructionText
                    anchors.centerIn: parent
                    width: parent.width - 20
                    text: polygonComplete ? 
                        "✅ Survey area defined (" + surveyPolygon.length + " points)\nAdjust parameters and generate" :
                        "📍 Click on map to define survey area\n(Min 3 points, click near first point to close)"
                    font.pixelSize: 12
                    font.family: "Consolas"
                    color: "#1b5e20"
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            
            // Stats display
            Rectangle {
                Layout.fillWidth: true
                height: 80
                color: "#f8f9fa"
                border.color: "#dee2e6"
                border.width: 1
                radius: 6
                visible: polygonComplete
                
                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    columns: 2
                    rowSpacing: 5
                    columnSpacing: 10
                    
                    Text {
                        text: "Points:"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: "#6c757d"
                    }
                    Text {
                        text: surveyPolygon.length.toString()
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "Consolas"
                        color: "#212529"
                    }
                    
                    Text {
                        text: "Area:"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: "#6c757d"
                    }
                    Text {
                        text: calculateArea().toFixed(2) + " m²"
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "Consolas"
                        color: "#212529"
                    }
                    
                    Text {
                        text: "Est. Waypoints:"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: "#6c757d"
                    }
                    Text {
                        text: surveyWaypoints.length.toString()
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "Consolas"
                        color: "#212529"
                    }
                }
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                
                ColumnLayout {
                    width: parent.width - 20
                    spacing: 15
                    
                    // Grid Spacing
                    GroupBox {
                        Layout.fillWidth: true
                        title: "Grid Parameters"
                        font.family: "Consolas"
                        
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                
                                Text {
                                    text: "Spacing:"
                                    font.pixelSize: 12
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 80
                                }
                                
                                Slider {
                                    id: spacingSlider
                                    Layout.fillWidth: true
                                    from: 10
                                    to: 200
                                    value: gridSpacing
                                    stepSize: 5
                                    onValueChanged: {
                                        gridSpacing = value;
                                        if (polygonComplete) regenerateGrid();
                                    }
                                }
                                
                                Text {
                                    text: gridSpacing.toFixed(0) + "m"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 50
                                }
                            }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                
                                Text {
                                    text: "Angle:"
                                    font.pixelSize: 12
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 80
                                }
                                
                                Slider {
                                    id: angleSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 180
                                    value: parseFloat(gridAngle)
                                    stepSize: 5
                                    onValueChanged: {
                                        gridAngle = value.toString();
                                        if (polygonComplete) regenerateGrid();
                                    }
                                }
                                
                                Text {
                                    text: gridAngle + "°"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 50
                                }
                            }
                        }
                    }
                    
                    // Flight Parameters
                    GroupBox {
                        Layout.fillWidth: true
                        title: "Flight Parameters"
                        font.family: "Consolas"
                        
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                
                                Text {
                                    text: "Altitude:"
                                    font.pixelSize: 12
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 80
                                }
                                
                                Slider {
                                    Layout.fillWidth: true
                                    from: 10
                                    to: 200
                                    value: altitude
                                    stepSize: 5
                                    onValueChanged: altitude = value
                                }
                                
                                Text {
                                    text: altitude.toFixed(0) + "m"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 50
                                }
                            }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                
                                Text {
                                    text: "Speed:"
                                    font.pixelSize: 12
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 80
                                }
                                
                                Slider {
                                    Layout.fillWidth: true
                                    from: 2
                                    to: 20
                                    value: speed
                                    stepSize: 0.5
                                    onValueChanged: speed = value
                                }
                                
                                Text {
                                    text: speed.toFixed(1) + "m/s"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 50
                                }
                            }
                        }
                    }
                    
                    // Camera Parameters
                    GroupBox {
                        Layout.fillWidth: true
                        title: "Camera Settings"
                        font.family: "Consolas"
                        
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                
                                Text {
                                    text: "Overlap:"
                                    font.pixelSize: 12
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 80
                                }
                                
                                Slider {
                                    Layout.fillWidth: true
                                    from: 50
                                    to: 90
                                    value: overlap
                                    stepSize: 5
                                    onValueChanged: overlap = value
                                }
                                
                                Text {
                                    text: overlap.toFixed(0) + "%"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 50
                                }
                            }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                
                                Text {
                                    text: "Side Overlap:"
                                    font.pixelSize: 12
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 80
                                }
                                
                                Slider {
                                    Layout.fillWidth: true
                                    from: 40
                                    to: 80
                                    value: sideOverlap
                                    stepSize: 5
                                    onValueChanged: sideOverlap = value
                                }
                                
                                Text {
                                    text: sideOverlap.toFixed(0) + "%"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: "Consolas"
                                    Layout.preferredWidth: 50
                                }
                            }
                        }
                    }
                    
                    CheckBox {
                        text: "Add turnaround waypoints"
                        font.pixelSize: 12
                        font.family: "Consolas"
                        checked: turnaroundAtEnd
                        onCheckedChanged: {
                            turnaroundAtEnd = checked;
                            if (polygonComplete) regenerateGrid();
                        }
                    }
                }
            }
            
            // Action Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                
                Button {
                    Layout.fillWidth: true
                    height: 45
                    enabled: polygonComplete
                    
                    background: Rectangle {
                        color: parent.enabled ? (parent.pressed ? "#218838" : (parent.hovered ? "#1e7e34" : "#28a745")) : "#6c757d"
                        radius: 6
                    }
                    
                    contentItem: Text {
                        text: "✅ Generate Survey"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        font.family: "Consolas"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: generateSurvey()
                }
                
                Button {
                    Layout.fillWidth: true
                    height: 45
                    
                    background: Rectangle {
                        color: parent.pressed ? "#c82333" : (parent.hovered ? "#bd2130" : "#dc3545")
                        radius: 6
                    }
                    
                    contentItem: Text {
                        text: "🗑️ Clear"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        font.family: "Consolas"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: clearSurvey()
                }
            }
        }
    }
    
    // Visual feedback - polygon markers on map
    Repeater {
        model: surveyPolygon.length
        delegate: Rectangle {
            visible: isActive
            width: 12
            height: 12
            radius: 6
            color: "#28a745"
            border.color: "white"
            border.width: 2
            z: 100
            
            property var coord: surveyPolygon[index]
            property var screenPos: mapView && mapView.map ? 
                mapView.map.fromCoordinate(QtPositioning.coordinate(coord.lat, coord.lon)) : Qt.point(0, 0)
            
            x: screenPos.x - width/2
            y: screenPos.y - height/2
        }
    }
    
    // Functions
    function startSurvey() {
        isActive = true;
        surveyPolygon = [];
        surveyWaypoints = [];
        polygonComplete = false;
        console.log("✅ Survey planner started - click map to define area");
    }
    
    function addPolygonPoint(lat, lon) {
        if (polygonComplete) return;
        
        var point = {"lat": lat, "lon": lon};
        
        // Check if clicking near first point to close polygon
        if (surveyPolygon.length >= 3) {
            var first = surveyPolygon[0];
            var distance = calculateDistance(lat, lon, first.lat, first.lon);
            
            if (distance < 50) { // Within 50 meters of first point
                polygonComplete = true;
                console.log("✅ Survey polygon closed with " + surveyPolygon.length + " points");
                regenerateGrid();
                return;
            }
        }
        
        var tempArray = surveyPolygon.slice(); // Create copy
        tempArray.push(point);
        surveyPolygon = tempArray; // Trigger property change
        
        console.log("📍 Survey point " + surveyPolygon.length + " added at: " + lat.toFixed(6) + ", " + lon.toFixed(6));
    }
    
    function regenerateGrid() {
        if (!polygonComplete || surveyPolygon.length < 3) return;
        
        console.log("🔄 Generating survey grid...");
        surveyWaypoints = generateGridPattern();
        console.log("✅ Generated " + surveyWaypoints.length + " survey waypoints");
    }
    
    function generateGridPattern() {
        var waypoints = [];
        
        // Get polygon bounds
        var bounds = getPolygonBounds();
        var angle = parseFloat(gridAngle) * Math.PI / 180;
        
        // Calculate grid lines
        var gridLines = calculateGridLines(bounds, angle);
        
        // Convert grid lines to waypoints with lawnmower pattern
        var direction = 1; // 1 = forward, -1 = backward
        
        for (var i = 0; i < gridLines.length; i++) {
            var line = gridLines[i];
            var intersections = getPolygonIntersections(line);
            
            if (intersections.length >= 2) {
                if (direction === 1) {
                    waypoints.push({
                        lat: intersections[0].lat,
                        lng: intersections[0].lon,
                        altitude: altitude,
                        speed: speed,
                        commandType: "waypoint"
                    });
                    waypoints.push({
                        lat: intersections[1].lat,
                        lng: intersections[1].lon,
                        altitude: altitude,
                        speed: speed,
                        commandType: "waypoint"
                    });
                } else {
                    waypoints.push({
                        lat: intersections[1].lat,
                        lng: intersections[1].lon,
                        altitude: altitude,
                        speed: speed,
                        commandType: "waypoint"
                    });
                    waypoints.push({
                        lat: intersections[0].lat,
                        lng: intersections[0].lon,
                        altitude: altitude,
                        speed: speed,
                        commandType: "waypoint"
                    });
                }
                
                direction *= -1; // Alternate direction
            }
        }
        
        return waypoints;
    }
    
    function calculateGridLines(bounds, angle) {
        var lines = [];
        var spacing = gridSpacing;
        
        // Simplified grid generation (perpendicular lines across polygon)
        var width = calculateDistance(bounds.minLat, bounds.minLon, bounds.minLat, bounds.maxLon);
        var numLines = Math.ceil(width / spacing);
        
        for (var i = 0; i <= numLines; i++) {
            var offset = i * spacing;
            var lineLat = bounds.minLat + (offset / 111320); // rough meters to degrees
            
            lines.push({
                startLat: lineLat,
                startLon: bounds.minLon,
                endLat: lineLat,
                endLon: bounds.maxLon
            });
        }
        
        return lines;
    }
    
    function getPolygonIntersections(line) {
        var intersections = [];
        
        for (var i = 0; i < surveyPolygon.length; i++) {
            var p1 = surveyPolygon[i];
            var p2 = surveyPolygon[(i + 1) % surveyPolygon.length];
            
            var intersection = lineIntersection(
                line.startLat, line.startLon, line.endLat, line.endLon,
                p1.lat, p1.lon, p2.lat, p2.lon
            );
            
            if (intersection) {
                intersections.push(intersection);
            }
        }
        
        return intersections.sort(function(a, b) { return a.lon - b.lon; });
    }
    
    function lineIntersection(x1, y1, x2, y2, x3, y3, x4, y4) {
        var denom = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4));
        
        if (Math.abs(denom) < 0.000001) return null;
        
        var t = (((x1 - x3) * (y3 - y4)) - ((y1 - y3) * (x3 - x4))) / denom;
        var u = -(((x1 - x2) * (y1 - y3)) - ((y1 - y2) * (x1 - x3))) / denom;
        
        if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
            return {
                lat: x1 + t * (x2 - x1),
                lon: y1 + t * (y2 - y1)
            };
        }
        
        return null;
    }
    
    function getPolygonBounds() {
        var minLat = 999, maxLat = -999;
        var minLon = 999, maxLon = -999;
        
        for (var i = 0; i < surveyPolygon.length; i++) {
            minLat = Math.min(minLat, surveyPolygon[i].lat);
            maxLat = Math.max(maxLat, surveyPolygon[i].lat);
            minLon = Math.min(minLon, surveyPolygon[i].lon);
            maxLon = Math.max(maxLon, surveyPolygon[i].lon);
        }
        
        return {minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon};
    }
    
    function calculateArea() {
        if (surveyPolygon.length < 3) return 0;
        
        var area = 0;
        for (var i = 0; i < surveyPolygon.length; i++) {
            var j = (i + 1) % surveyPolygon.length;
            area += surveyPolygon[i].lat * surveyPolygon[j].lon;
            area -= surveyPolygon[j].lat * surveyPolygon[i].lon;
        }
        
        area = Math.abs(area / 2);
        return area * 111320 * 111320; // rough conversion to square meters
    }
    
    function calculateDistance(lat1, lon1, lat2, lon2) {
        var R = 6371000;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        return R * c;
    }
    
    function generateSurvey() {
        if (surveyWaypoints.length === 0) {
            console.log("⚠️ No survey waypoints to generate");
            return;
        }
        
        console.log("✅ Survey generated with " + surveyWaypoints.length + " waypoints");
        surveyGenerated(surveyWaypoints);
        
        // Add waypoints to main map
        if (mapView && mapView.clearAllMarkersJS) {
            mapView.clearAllMarkersJS();
        }
        
        for (var i = 0; i < surveyWaypoints.length; i++) {
            var wp = surveyWaypoints[i];
            if (mapView && mapView.addMarkerJS) {
                mapView.addMarkerJS(wp.lat, wp.lng, wp.altitude, wp.speed, "waypoint", 0);
            }
        }
        
        // Close the survey planner
        isActive = false;
        clearSurvey();
    }
    
    function clearSurvey() {
        surveyPolygon = [];
        surveyWaypoints = [];
        polygonComplete = false;
        
        console.log("🗑️ Survey cleared");
    }
    
    function cancelSurvey() {
        clearSurvey();
        isActive = false;
        surveyCancelled();
        console.log("❌ Survey cancelled");
    }
}
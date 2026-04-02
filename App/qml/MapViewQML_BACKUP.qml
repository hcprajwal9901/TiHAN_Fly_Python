// MapViewQML.qml - QtLocation-based map component
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtLocation 5.15
import QtPositioning 5.15

Item {
    id: root
    width: 700
    height: 500

    property var lastClickedCoordinate: null
    property var markers: []
    property bool addMarkersMode: false
    
    property real currentLat: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.lat || 0 : 0
    property real currentLon: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.lon || 0 : 0
    property real currentAlt: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.rel_alt || 0 : 0
    property bool isDroneConnected: (typeof droneModel !== "undefined" && droneModel) ? droneModel.isConnected : false
    
    property bool hasValidDroneLocation: currentLat !== 0 && currentLon !== 0 && !isNaN(currentLat) && !isNaN(currentLon)

    Rectangle {
        anchors.fill: parent
        color: "#0a0a0a"
        radius: 8
        border.color: "#404040"
        border.width: 1

        Plugin {
            id: mapPlugin
            name: "google"
            
            Component.onCompleted: {
                console.log("=== MAP PLUGIN VALIDATION ===")
                console.log("Plugin name:", name)
                console.log("Supported map types:", map.supportedMapTypes.length)
                
                if (map.supportedMapTypes.length === 0) {
                    console.error("❌ CRITICAL: No map types available")
                } else {
                    console.log("✅ Plugin loaded successfully")
                    for (var i = 0; i < map.supportedMapTypes.length; i++) {
                        console.log("   Type", i + ":", map.supportedMapTypes[i].name)
                    }
                }
            }
        }

        Map {
            id: map
            anchors.fill: parent
            anchors.margins: 2
            plugin: mapPlugin
            center: QtPositioning.coordinate(0, 0)
            zoomLevel: 2
            activeMapType: supportedMapTypes.length > 0 ? supportedMapTypes[supportedMapTypes.length - 1] : supportedMapTypes[0]
            
            MapQuickItem {
                id: droneMarker
                visible: root.isDroneConnected && root.hasValidDroneLocation
                coordinate: QtPositioning.coordinate(root.currentLat, root.currentLon)
                anchorPoint.x: 25
                anchorPoint.y: 25
                zoomLevel: 0
                
                sourceItem: Rectangle {
                    width: 50
                    height: 50
                    radius: 25
                    color: "#00e676"
                    border.color: "white"
                    border.width: 2
                }
            }
            
            MapPolyline {
                id: routePath
                line.width: 3
                line.color: "#FF0000"
                path: {
                    var pathCoords = []
                    for (var i = 0; i < root.markers.length; i++) {
                        pathCoords.push(QtPositioning.coordinate(root.markers[i].lat, root.markers[i].lng))
                    }
                    return pathCoords
                }
            }
            
            Repeater {
                model: root.markers
                
                MapQuickItem {
                    coordinate: QtPositioning.coordinate(modelData.lat, modelData.lng)
                    anchorPoint.x: 16
                    anchorPoint.y: 16
                    zoomLevel: 0
                    
                    sourceItem: Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: "#00bcd4"
                        border.color: "white"
                        border.width: 2
                        
                        Text {
                            anchors.centerIn: parent
                            text: index + 1
                            color: "white"
                            font.bold: true
                        }
                    }
                }
            }
        }
        
        // Drone info panel (top-left)
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 10
            width: 220
            height: root.isDroneConnected && root.hasValidDroneLocation ? 120 : 40
            color: "#1a1a1a"
            opacity: 0.9
            radius: 6
            border.color: root.isDroneConnected ? "#00bcd4" : "#404040"
            border.width: 1
            
            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                
                Text {
                    text: root.isDroneConnected && root.hasValidDroneLocation ? "Drone Connected" : "Drone Disconnected"
                    color: root.isDroneConnected && root.hasValidDroneLocation ? "#00e676" : "#f44336"
                    font.bold: true
                    font.pixelSize: 12
                }
                
                Column {
                    visible: root.isDroneConnected && root.hasValidDroneLocation
                    spacing: 2
                    
                    Text {
                        text: "Position: " + root.currentLat.toFixed(6) + "°, " + root.currentLon.toFixed(6) + "°"
                        color: "#e0e0e0"
                        font.pixelSize: 11
                    }
                    
                    Text {
                        text: "Altitude: " + root.currentAlt.toFixed(1) + "m"
                        color: "#e0e0e0"
                        font.pixelSize: 11
                    }
                    
                    Text {
                        text: "Last Update: " + Qt.formatTime(new Date(), "hh:mm:ss")
                        color: "#e0e0e0"
                        font.pixelSize: 11
                    }
                }
            }
        }
        
        // Cursor/Zoom info panel (bottom-left)
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 10
            width: 280
            height: 50
            color: "#1a1a1a"
            opacity: 0.9
            radius: 6
            border.color: "#404040"
            border.width: 1
            
            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                
                Text {
                    id: cursorText
                    text: "Cursor: 0.000000°, 0.000000°"
                    color: "#e0e0e0"
                    font.pixelSize: 11
                }
                
                Text {
                    text: "Zoom: " + Math.round(map.zoomLevel) + " | " + 
                          (map.activeMapType ? map.activeMapType.name : "Satellite View")
                    color: "#e0e0e0"
                    font.pixelSize: 11
                }
            }
        }
        
        // Full-map MouseArea for cursor tracking
        MouseArea {
            anchors.fill: map
            hoverEnabled: true
            propagateComposedEvents: true
            acceptedButtons: Qt.NoButton  // Don't capture clicks
            
            onPositionChanged: {
                var coord = map.toCoordinate(Qt.point(mouse.x, mouse.y))
                if (coord.isValid) {
                    cursorText.text = "Cursor: " + coord.latitude.toFixed(6) + "°, " + coord.longitude.toFixed(6) + "°"
                }
            }
        }
        
        // Map controls panel (right side)
        Rectangle {
            id: mapControls
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 15
            width: 50
            height: 280
            color: "#1a1a1a"
            opacity: 0.9
            radius: 8
            border.color: "#404040"
            border.width: 1
            
            Column {
                anchors.centerIn: parent
                spacing: 12
                
                // Secure Mode indicator
                Rectangle {
                    width: 40
                    height: 25
                    radius: 4
                    color: "#00e676"
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    Text {
                        anchors.centerIn: parent
                        text: "🔒"
                        color: "white"
                        font.pixelSize: 14
                    }
                }
                
                // Zoom In
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: "#2a2a2a"
                    border.color: "#00bcd4"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: "#00bcd4"
                        font.pixelSize: 20
                        font.bold: true
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.zoomIn()
                    }
                }
                
                // Zoom Out
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: "#2a2a2a"
                    border.color: "#00bcd4"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "-"
                        color: "#00bcd4"
                        font.pixelSize: 20
                        font.bold: true
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.zoomOut()
                    }
                }
                
                // Center on Drone
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: "#2a2a2a"
                    border.color: root.hasValidDroneLocation ? "#00e676" : "#404040"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "⌖"
                        color: root.hasValidDroneLocation ? "#00e676" : "#404040"
                        font.pixelSize: 20
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.hasValidDroneLocation
                        onClicked: root.centerOnDrone()
                    }
                }
                
                // Map Type
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: "#2a2a2a"
                    border.color: "#00bcd4"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "🗺"
                        color: "#00bcd4"
                        font.pixelSize: 16
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var currentIndex = -1
                            for (var i = 0; i < map.supportedMapTypes.length; i++) {
                                if (map.activeMapType === map.supportedMapTypes[i]) {
                                    currentIndex = i
                                    break
                                }
                            }
                            var nextIndex = (currentIndex + 1) % map.supportedMapTypes.length
                            map.activeMapType = map.supportedMapTypes[nextIndex]
                        }
                    }
                }
                
                // Add Marker
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: "#2a2a2a"
                    border.color: "#ff4081"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "📍"
                        color: "#ff4081"
                        font.pixelSize: 16
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.addMarkersMode = !root.addMarkersMode
                    }
                }
            }
        }
    }
    
    Timer {
        interval: 500
        running: true
        repeat: true
        
        property bool hasTriggeredInitialCenter: false
        property bool previousConnectionState: false
        
        onTriggered: {
            var currentConnectionState = root.isDroneConnected && root.hasValidDroneLocation
            
            if (currentConnectionState && (!previousConnectionState || !hasTriggeredInitialCenter)) {
                console.log("Centering on drone:", root.currentLat, root.currentLon)
                map.center = QtPositioning.coordinate(root.currentLat, root.currentLon)
                map.zoomLevel = 18
                hasTriggeredInitialCenter = true
            } else if (!currentConnectionState && previousConnectionState) {
                map.center = QtPositioning.coordinate(0, 0)
                map.zoomLevel = 2
                hasTriggeredInitialCenter = false
            }
            
            previousConnectionState = currentConnectionState
        }
    }
    
    function addMarker(lat, lng, altitude, speed) {
        markers.push({lat: lat, lng: lng, altitude: altitude || 10, speed: speed || 5})
        markersChanged()
    }
    
    function deleteMarker(index) {
        if (index >= 0 && index < markers.length) {
            markers.splice(index, 1)
            markersChanged()
        }
    }
    
    function centerOnDrone() {
        if (root.hasValidDroneLocation) {
            map.center = QtPositioning.coordinate(root.currentLat, root.currentLon)
            map.zoomLevel = 18
        }
    }
    
    function zoomIn() { map.zoomLevel = Math.min(map.zoomLevel + 1, map.maximumZoomLevel) }
    function zoomOut() { map.zoomLevel = Math.max(map.zoomLevel - 1, map.minimumZoomLevel) }
    
    function addMarkerJS(lat, lon, altitude, speed) { addMarker(lat, lon, altitude, speed) }
    function deleteMarkerJS(index) { deleteMarker(index) }
    function centerOnDroneJS() { centerOnDrone() }
    function zoomInJS() { zoomIn() }
    function zoomOutJS() { zoomOut() }
}

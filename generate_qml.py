"""Generate MapViewQML.qml file"""

qml_content = '''// MapViewQML.qml - QtLocation-based map component
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
            
            onClicked: {
                var coord = map.toCoordinate(Qt.point(mouse.x, mouse.y))
                root.lastClickedCoordinate = coord
                
                if (root.addMarkersMode) {
                    addMarker(coord.latitude, coord.longitude, 10, 5)
                    root.addMarkersMode = false
                }
                
                if (typeof mapBridge !== "undefined" && mapBridge) {
                    mapBridge.mapClicked(coord.latitude, coord.longitude)
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
'''

with open(r"c:\Users\Tihan 02\Desktop\Tfly Final Pyversion\App\qml\MapViewQML.qml", "w", encoding="utf-8") as f:
    f.write(qml_content)

print("✅ MapViewQML.qml created successfully")

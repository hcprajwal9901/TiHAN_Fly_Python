import QtQuick 2.15
import QtLocation 5.15
import QtPositioning 5.15

// Drone marker overlay - positioned via coordinate conversion
Item {
    id: droneOverlay
    width: 50
    height: 50
    z: 2000  // Above waypoint markers
    
    // Get references from parent MapViewQML
    property var mapView: parent.parent  // MapViewQML root
    property var mapComponent: mapView ? mapView.children[0].children[0] : null  // Map component
    
    // Drone connection and location properties
    property bool droneConnected: mapView ? mapView.isDroneConnected : false
    property bool validLocation: mapView ? mapView.hasValidDroneLocation : false
    property real droneLat: mapView ? mapView.currentLat : 0
    property real droneLon: mapView ? mapView.currentLon : 0
    
    visible: droneConnected && validLocation && mapComponent !== null
    
    property var coordinate: QtPositioning.coordinate(droneLat, droneLon)
    property var screenPos: mapComponent ? mapComponent.fromCoordinate(coordinate) : Qt.point(0, 0)
    
    x: screenPos.x - width/2
    y: screenPos.y - height/2
    
    Rectangle {
        anchors.fill: parent
        radius: 25
        color: "#00e676"  // Green
        border.color: "white"
        border.width: 3
        
        // Drone icon
        Text {
            anchors.centerIn: parent
            text: "🚁"
            font.pixelSize: 24
        }
    }
    
    // Update position when map moves/zooms or drone moves
    Connections {
        target: mapComponent
        function onCenterChanged() { 
            if (mapComponent) screenPos = mapComponent.fromCoordinate(coordinate) 
        }
        function onZoomLevelChanged() { 
            if (mapComponent) screenPos = mapComponent.fromCoordinate(coordinate) 
        }
    }
    
    onCoordinateChanged: {
        if (mapComponent) screenPos = mapComponent.fromCoordinate(coordinate)
    }
    
    Component.onCompleted: {
        console.log("🚁 Drone marker overlay created")
        console.log("   Map component:", mapComponent ? "FOUND" : "NOT FOUND")
        console.log("   Connected:", droneConnected, "Valid location:", validLocation)
        console.log("   Lat:", droneLat, "Lon:", droneLon)
    }
}

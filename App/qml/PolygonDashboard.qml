// PolygonDashboard.qml
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: polygonDashboard
    width: 320
    height: expanded ? 280 : 60
    color: "#ffffff"
    radius: 10
    border.color: "#FF9900"
    border.width: 2
    opacity: 0.95
    visible: dashboardVisible
    
    property bool expanded: true
    property int cornerCount: 0
    property real totalArea: 0  // in square meters
    property real perimeter: 0  // in meters
    property var corners: []
    
    Component.onCompleted: {
        console.log("✅ PolygonDashboard component created")
    }
    
    Behavior on height {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }
    
    // Header
    Rectangle {
        id: header
        width: parent.width
        height: 50
        color: "#FF9900"
        radius: 10
        
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius
            color: parent.color
        }
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            
            Text {
                text: "📐"
                font.pixelSize: 24
                color: "white"
            }
            
            Text {
                text: "Polygon Survey Area"
                font.pixelSize: 16
                font.bold: true
                font.family: "Consolas"
                color: "white"
                Layout.fillWidth: true
            }
            
            Button {
                width: 30
                height: 30
                
                background: Rectangle {
                    color: parent.hovered ? "#ffffff20" : "transparent"
                    radius: 4
                }
                
                contentItem: Text {
                    text: polygonDashboard.expanded ? "−" : "+"
                    font.pixelSize: 20
                    font.bold: true
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: polygonDashboard.expanded = !polygonDashboard.expanded
            }
        }
    }
    
    // Content
    Column {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 15
        spacing: 12
        visible: polygonDashboard.expanded
        
        // Corners Count
        Row {
            width: parent.width
            spacing: 10
            
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: "#FFF3E0"
                border.color: "#FF9900"
                border.width: 2
                
                Text {
                    anchors.centerIn: parent
                    text: "📍"
                    font.pixelSize: 20
                }
            }
            
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                
                Text {
                    text: "Polygon Corners"
                    font.pixelSize: 11
                    font.family: "Consolas"
                    color: "#666666"
                }
                
                Text {
                    text: polygonDashboard.cornerCount + " points"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Consolas"
                    color: "#212529"
                }
            }
        }
        
        // Separator
        Rectangle {
            width: parent.width
            height: 1
            color: "#e0e0e0"
        }
        
        // Area (Acres)
        Row {
            width: parent.width
            spacing: 10
            
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: "#E8F5E9"
                border.color: "#4CAF50"
                border.width: 2
                
                Text {
                    anchors.centerIn: parent
                    text: "📏"
                    font.pixelSize: 20
                }
            }
            
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                
                Text {
                    text: "Total Area"
                    font.pixelSize: 11
                    font.family: "Consolas"
                    color: "#666666"
                }
                
                Text {
                    text: (polygonDashboard.totalArea / 4046.86).toFixed(3) + " acres"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Consolas"
                    color: "#212529"
                }
                
                Text {
                    text: "(" + (polygonDashboard.totalArea / 10000).toFixed(4) + " hectares)"
                    font.pixelSize: 10
                    font.family: "Consolas"
                    color: "#999999"
                }
            }
        }
        
        // Separator
        Rectangle {
            width: parent.width
            height: 1
            color: "#e0e0e0"
        }
        
        // Perimeter
        Row {
            width: parent.width
            spacing: 10
            
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: "#E3F2FD"
                border.color: "#2196F3"
                border.width: 2
                
                Text {
                    anchors.centerIn: parent
                    text: "📐"
                    font.pixelSize: 20
                }
            }
            
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                
                Text {
                    text: "Perimeter"
                    font.pixelSize: 11
                    font.family: "Consolas"
                    color: "#666666"
                }
                
                Text {
                    text: polygonDashboard.perimeter < 1000 ? 
                          polygonDashboard.perimeter.toFixed(1) + " m" :
                          (polygonDashboard.perimeter / 1000).toFixed(2) + " km"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Consolas"
                    color: "#212529"
                }
            }
        }
    }
    
    // Functions
function show() {
    console.log("📊 PolygonDashboard.show() called")
    visible = true  // ✅ Use 'visible' directly
    dashboardVisible = true
    expanded = true
}

function hide() {
    console.log("📊 PolygonDashboard.hide() called")
    visible = false  // ✅ Use 'visible' directly
    dashboardVisible = false
}
    
    function updatePolygonData(corners) {
        console.log("📊 PolygonDashboard.updatePolygonData() called - corners:", corners.length)
        
        polygonDashboard.corners = corners
        polygonDashboard.cornerCount = corners.length
        
        if (corners.length < 3) {
            polygonDashboard.totalArea = 0
            polygonDashboard.perimeter = 0
            return
        }
        
        // Calculate area using Shoelace formula
        var area = 0
        var perimeter = 0
        
        for (var i = 0; i < corners.length; i++) {
            var j = (i + 1) % corners.length
            
            // Area calculation (Shoelace formula)
            area += corners[i].lat * corners[j].lng
            area -= corners[j].lat * corners[i].lng
            
            // Perimeter calculation
            var dist = calculateDistance(
                corners[i].lat, corners[i].lng,
                corners[j].lat, corners[j].lng
            )
            perimeter += dist
        }
        
        area = Math.abs(area / 2)
        
        // Convert to square meters (approximate)
        var latToM = 111320
        var lonToM = 111320 * Math.cos(corners[0].lat * Math.PI / 180)
        polygonDashboard.totalArea = area * latToM * lonToM
        polygonDashboard.perimeter = perimeter
        
        console.log("📊 Polygon stats - Area:", polygonDashboard.totalArea.toFixed(2), "m²")
        console.log("📊 Polygon stats - Acres:", (polygonDashboard.totalArea / 4046.86).toFixed(3))
        console.log("📊 Polygon stats - Perimeter:", polygonDashboard.perimeter.toFixed(2), "m")
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
}

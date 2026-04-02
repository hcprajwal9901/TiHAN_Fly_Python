// Updated Sidebar Section for Navigation Controls
// Add this to replace your existing sidebar ColumnLayout content

ColumnLayout {
    anchors.fill: parent
    anchors.margins: 20
    spacing: 15
    
    Text {
        text: "Mission Planning"
        color: theme.textPrimary
        font.pixelSize: 14
        font.bold: true
        font.family: "Consolas"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
    }
    
    // Add Waypoints Button
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: parent.hovered ? "#e3f2fd" : "#f8f9fa"
            radius: 8
            border.color: theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { text: "➕"; font.pixelSize: 16; font.family: "Consolas"; color: theme.accent }
            Text { 
                text: "Add Waypoints"
                color: theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: {
            waypointsMap.setAddMarkersModeJS(true);
            surveyPlanner.isActive = false;
            polygonPlanner.isActive = false;
            if (!waypointDashboard.visible) {
                waypointDashboard.show();
                Qt.callLater(function() {
                    updateWaypointDashboard();
                });
            }
        }
    }
    
    // Survey Mission Button (NEW)
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: surveyPlanner.isActive ? "#28a745" : (parent.hovered ? "#e8f5e9" : "#f8f9fa")
            radius: 8
            border.color: surveyPlanner.isActive ? "#28a745" : theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { 
                text: "📐"
                font.pixelSize: 16
                font.family: "Consolas"
                color: surveyPlanner.isActive ? "white" : "#28a745"
            }
            Text { 
                text: "Survey Mission"
                color: surveyPlanner.isActive ? "white" : theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: {
            if (surveyPlanner.isActive) {
                surveyPlanner.cancelSurvey();
            } else {
                waypointsMap.setAddMarkersModeJS(false);
                polygonPlanner.isActive = false;
                surveyPlanner.startSurvey();
            }
        }
    }
    
    // Polygon Mission Button (NEW)
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: polygonPlanner.isActive ? "#17a2b8" : (parent.hovered ? "#d1ecf1" : "#f8f9fa")
            radius: 8
            border.color: polygonPlanner.isActive ? "#17a2b8" : theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { 
                text: "⬡"
                font.pixelSize: 16
                font.family: "Consolas"
                color: polygonPlanner.isActive ? "white" : "#17a2b8"
            }
            Text { 
                text: "Polygon Mission"
                color: polygonPlanner.isActive ? "white" : theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: {
            if (polygonPlanner.isActive) {
                polygonPlanner.cancelPolygon();
            } else {
                waypointsMap.setAddMarkersModeJS(false);
                surveyPlanner.isActive = false;
                polygonPlanner.startPolygon();
            }
        }
    }
    
    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: theme.border
    }
    
    // Send Waypoints Button
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: parent.hovered ? "#e8f5e8" : "#f8f9fa"
            radius: 8
            border.color: theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { text: "📤"; font.pixelSize: 16; font.family: "Consolas"; color: theme.success }
            Text { 
                text: "Send Waypoints"
                color: theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: sendMarkers()
    }
    
    // Clear Waypoints Button
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: parent.hovered ? "#ffeaea" : "#f8f9fa"
            radius: 8
            border.color: theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { text: "🗑️"; font.pixelSize: 16; font.family: "Consolas"; color: theme.error }
            Text { 
                text: "Clear Waypoints"
                color: theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: { 
            waypointsMap.clearAllMarkersJS(); 
            surveyPlanner.clearSurvey();
            polygonPlanner.clearPolygon();
            lastClickedCoordinate = null;
            Qt.callLater(function() {
                onWaypointDeleted();
            });
        }
    }
    
    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: theme.border
    }
    
    // Save Waypoints Button
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: parent.hovered ? "#e3f2fd" : "#f8f9fa"
            radius: 8
            border.color: theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { text: "💾"; font.pixelSize: 16; font.family: "Consolas"; color: "#007bff" }
            Text { 
                text: "Save Waypoints"
                color: theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: {
            saveWaypointsPopup.open();
        }
    }
    
    // Load Waypoints Button
    Button {
        Layout.fillWidth: true
        height: 50
        background: Rectangle {
            color: parent.hovered ? "#f0f4ff" : "#f8f9fa"
            radius: 8
            border.color: theme.border
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 10
            Text { text: "📂"; font.pixelSize: 16; font.family: "Consolas"; color: "#28a745" }
            Text { 
                text: "Load Waypoints"
                color: theme.textPrimary
                font.pixelSize: 14
                font.family: "Consolas"
                Layout.fillWidth: true
            }
        }
        onClicked: {
            loadWaypointsPopup.open();
        }
    }
    
    Item { Layout.fillHeight: true }
    
    Text { 
        text: "💡 Tip: Use Survey for grid patterns,\nPolygon for custom flight paths"
        color: theme.textSecondary
        font.pixelSize: 10
        font.family: "Consolas"
        font.italic: true
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignLeft
        wrapMode: Text.WordWrap
    }
}



 NavigationSidebarContent.qml - Updated Sidebar

Integrated Survey and Polygon buttons
Visual feedback when modes are active
Organized mission planning workflow
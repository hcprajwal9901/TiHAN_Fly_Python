import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import QtWebEngine 1.10
import QtPositioning 5.15
import QtQuick.Layouts 1.0
import QtGraphicalEffects 1.10
import QtQuick.Dialogs 1.3
import Qt.labs.platform 1.1 // For FileDialog

ApplicationWindow {
    id: mainWindow
    visible: true
    visibility: Window.Maximized

    width: Math.min(Screen.width * 0.95, 1920)
    height: Math.min(Screen.height * 0.95, 1080)

    minimumWidth: 1280
    minimumHeight: 720
    title: "TiHAN Fly-Drone Control Station"
    color: "#f8f9fa"  // Light background
    property var referencePoint: QtPositioning.coordinate(17.601588777182204, 78.12690006798547)
    property var lastClickedCoordinate: null
    property var waypoints: []
    property bool isDragging: false
    property var pendingWaypointData: ""  // ✅ Correct
    property var mainGcsWindow: null      // Reference to the main GCS window for syncing map views

    QtObject {
        id: theme
        property color primary: "#ffffff"
        property color accent: "#007bff"
        property color success: "#28a745"
        property color error: "#dc3545"
        property color cardBackground: "#ffffff"
        property color textPrimary: "#212529"
        property color textSecondary: "#6c757d"
        property color border: "#dee2e6"
        property int borderRadius: 8
    }



FileDialog {
    id: saveWaypointsDialog
    title: "Save Waypoints File"
    fileMode: FileDialog.SaveFile
    nameFilters: ["Waypoints Files (*.waypoints)"]
    defaultSuffix: "waypoints"
    folder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)

    onAccepted: {
        var path = file.toString().replace("file://", "");
        if (!path.endsWith(".waypoints"))
            path += ".waypoints";

        console.log("💾 Saving to:", path);

        // Save using Python helper
        var success = waypointsSaver.save_file(path, pendingWaypointData);
        if (success) {
            console.log("✅ Waypoints saved at: " + path);
            statusNotification.color = theme.success;
            statusNotificationLabel.text = "✅ File saved: " + path;
        } else {
            console.log("❌ Save failed");
            statusNotification.color = theme.error;
            statusNotificationLabel.text = "Error saving file!";
        }
        statusNotification.opacity = 1;
        statusNotificationTimer.restart();
    }

    onRejected: {
        console.log("⚠️ Save canceled by user");
    }
}

FileDialog {
    id: openWaypointsDialog
    title: "Select Waypoints File"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Waypoints Files (*.waypoints *.mission)"]
    folder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
    onAccepted: {
        var path = file.toString().replace("file://", "");
        console.log("📂 Selected file:", path);
        selectedFileText.text = path;

        // Load file content immediately
        var content = waypointsSaver.load_file(path);
        if (content && content.length > 0) {
            loadDataInput.text = content;  // show content in text box for confirmation
        } else {
            statusNotification.color = theme.error;
            statusNotificationLabel.text = "⚠️ Failed to read file.";
            statusNotification.opacity = 1;
            statusNotificationTimer.restart();
        }
    }
    onRejected: {
        console.log("⚠️ File selection canceled");
    }
}
// Add this button after menuToggle in the header RowLayout (around line 93)

// Header
   // Updated Header section with Language Dropdown
// Header - REPLACE THIS ENTIRE SECTION
Rectangle {
    id: header
    width: parent.width
    height: 80  // Increased height for stats
    color: "#ffffff"
    border.color: theme.border
    border.width: 1
    z: 2

    Rectangle {
        width: parent.width
        height: 2
        anchors.bottom: parent.bottom
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000020" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 15

        // Left side - Menu and Home buttons
        Row {
            spacing: 10
            Layout.alignment: Qt.AlignLeft
           
            Button {
                id: menuToggle
                text: sidebar.opened ? "✖" : "☰"
                contentItem: Text {
                    text: parent.text
                    color: theme.textPrimary
                    font.pixelSize: 24
                    font.family: "Consolas"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.hovered ? "#f8f9fa" : "transparent"
                    radius: 6
                }
                onClicked: sidebar.opened ? sidebar.close() : sidebar.open()
            }

            Button {
                id: homeButton
                text: "🏠"
                contentItem: Text {
                    text: parent.text
                    color: theme.textPrimary
                    font.pixelSize: 30
                    font.family: "Consolas"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.hovered ? "#f8f9fa" : "transparent"
                    radius: 6
                }
                onClicked: {
                    mainWindow.close();
                }
               
                ToolTip.visible: hovered
                ToolTip.text: "Return to Main Dashboard"
                ToolTip.delay: 500
            }
        }

        // Center - Mission Statistics
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignCenter
            color: "transparent"
           
            Row {
                anchors.centerIn: parent
                spacing: 25
               
                // Total Waypoints
                Column {
                    spacing: 2
                   
                    Text {
                        text: "📍 Waypoints"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: theme.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                   
                    Text {
                        id: totalWaypointsText
                        text: "0"
                        font.pixelSize: 18
                        font.bold: true
                        font.family: "Consolas"
                        color: theme.accent
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
               
                Rectangle {
                    width: 1
                    height: 40
                    color: theme.border
                }
               
                // Total Distance
                Column {
                    spacing: 2
                   
                    Text {
                        text: "📏 Total Distance"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: theme.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                   
                    Text {
                        id: totalDistanceText
                        text: "0.0 km"
                        font.pixelSize: 18
                        font.bold: true
                        font.family: "Consolas"
                        color: "#9c27b0"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
               
                Rectangle {
                    width: 1
                    height: 40
                    color: theme.border
                }
               
                // Distance Covered
                Column {
                    spacing: 2
                   
                    Text {
                        text: "✓ Covered"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: theme.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                   
                    Text {
                        id: coveredDistanceText
                        text: "0.0 km"
                        font.pixelSize: 18
                        font.bold: true
                        font.family: "Consolas"
                        color: theme.success
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
               
                Rectangle {
                    width: 1
                    height: 40
                    color: theme.border
                }
               
                // Estimated Time
                Column {
                    spacing: 2
                   
                    Text {
                        text: "⏱️ Est. Time"
                        font.pixelSize: 11
                        font.family: "Consolas"
                        color: theme.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                   
                    Text {
                        id: estimatedTimeText
                        text: "0m 0s"
                        font.pixelSize: 18
                        font.bold: true
                        font.family: "Consolas"
                        color: "#ff9800"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }
    }
   
    Image {
        source: "../images/tihan.png"
        width: 70
        height: 70
        fillMode: Image.PreserveAspectFit
        anchors.right: parent.right
        anchors.rightMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        smooth: true
    }
}
    // Language dropdown removed - not used in this version

    // Status notification
    Item {
        id: parametersWindowRoot

        Rectangle {
            id: statusNotification
            anchors.top: parametersWindowRoot.top
            anchors.horizontalCenter: parametersWindowRoot.horizontalCenter
            anchors.topMargin: 100
            width: 300
            height: 50
            color: theme.success
            radius: 8
            opacity: 0
            z: 1000
           
            Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        color: "#00000015"
        radius: parent.radius
        z: -1
    }

    Label {
        id: statusNotificationLabel  // ✅ ADD THIS ID
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 12
        font.bold: true
        font.family: "Consolas"
    }
           
            Behavior on opacity {
                NumberAnimation { duration: 300 }
            }
        }
       
        Timer {
            id: statusNotificationTimer
            interval: 2000
            onTriggered: statusNotification.opacity = 0
        }
    }

    // Google Maps WebEngine Implementation
    Rectangle {
        id: mapContainer
        anchors.fill: parent
        anchors.topMargin: header.height
        color: "#0a0a0a"
        radius: 8
        border.color: "#404040"
        border.width: 1

        MapViewQML {
            id: waypointsMap
            anchors.fill: parent
            anchors.margins: 2
           
            isEditable: true
            showBuiltinControls: false  // NavigationControls has its own mapControls panel
            showVideoOverlay: false     // Hide camera system from navigation view
           
            // Telemetry Bindings
            currentLat: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.lat || 0 : 0
            currentLon: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.lon || 0 : 0
            currentAlt: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.rel_alt || 0 : 0
            isDroneConnected: (typeof droneModel !== "undefined" && droneModel) ? droneModel.isConnected : false
           
            // Signal Handlers
            onMarkerAdded: {
                console.log("📍 Waypoint added at:", lat, lon)
                if (typeof onWaypointAdded === "function") {
                    console.log("Calling onWaypointAdded handler if exists")
                }
                // Auto-show waypoint dashboard when first waypoint is added
                if (!waypointDashboard.visible) {
                    waypointDashboard.show()
                }
                if (!waypointDashboard.expanded) {
                    waypointDashboard.expanded = true
                }
                // Update waypoint dashboard when marker is added
                updateWaypointDashboard()
            }
           
            onMarkerMoved: {
                console.log("🔄 Waypoint moved")
                if (typeof onWaypointMoved === "function") {
                    console.log("Calling onWaypointMoved handler if exists")
                }
                // Update waypoint dashboard when marker is moved
                updateWaypointDashboard()
            }
           
            onMarkerDeleted: {
                console.log("🗑️ Waypoint deleted")
                 if (typeof onWaypointDeleted === "function") {
                    console.log("Calling onWaypointDeleted handler if exists")
                }
                // Update waypoint dashboard when marker is deleted
                updateWaypointDashboard()
            }
           
            onLocationClicked: {
                console.log("🌤️ Map location clicked, updating weather for:", lat, lon)
                weatherDashboard.setLocation(lat, lon)
                if (!weatherDashboard.dashboardVisible) {
                    weatherDashboard.show()
                }
            }
           
            // API Compatibility for existing calls
            function setAddMarkersModeJS(enabled) {
                isEditable = true // Ensure edit mode is on
                addMarkersMode = enabled
            }
           
            function clearAllMarkersJS() {
                clearAllMarkers()
            }
           
            function getAllMarkersJS(callback) {
                // Return JSON string to match WebEngine behavior
                if (callback) callback(getMarkersJSON())
                else return getMarkersJSON()
            }
           
            function resetToWorldViewJS() {
                console.log("🌍 Reset to world view requested")
                // Function kept for compatibility but does nothing
                // Map centering should be done through Map component methods
            }
        }

        // Map overlay controls
        // Black MapViewQML panel is hidden — this white panel sits at the top
Rectangle {
    id: mapControls
    anchors.top: parent.top
    anchors.topMargin: 70
    anchors.right: parent.right
    anchors.rightMargin: 15
    width: 50
    height: 180  // 4 buttons × 35px + 3 gaps × 8px + 16px padding = 180
    z: 2000
    color: "#1a1a1a"
    radius: 8
    border.color: "#404040"
    border.width: 1
    opacity: 0.95

    Column {
        anchors.centerIn: parent
        spacing: 8

        // Weather Button
        Button {
    id: weatherControlBtn
    width: 35
    height: 35
    text: "🌤️"
   
    background: Rectangle {
        color: weatherDashboard.visible ? "#1a1a1a" :
               (weatherControlBtn.pressed ? "#e9ecef" : (weatherControlBtn.hovered ? "#f8f9fa" : "#1a1a1a"))
        radius: 6
        border.color: "#404040"
        border.width: 1
    }
   
    contentItem: Text {
        text: weatherControlBtn.text
        font.pixelSize: 14
        color: weatherDashboard.visible ? "white" : "#404040"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

           
   onClicked: {
        if (weatherDashboard.dashboardVisible) {  // Use dashboardVisible instead of visible
            weatherDashboard.hide();
        } else {
            var lat = droneModel.telemetry.lat || 17.601588777182204;
            var lon = droneModel.telemetry.lon || 78.12690006798547;
            weatherDashboard.setLocation(lat, lon);
            weatherDashboard.show();
        }
    }
}
        // Map Type Switcher Button - FIXED
        Button {
            id: mapTypeSwitcherBtn
            width: 35
            height: 35
            text: "🗺️"

            background: Rectangle {
                color: mapTypeSwitcherBtn.pressed ? "#e9ecef" : (mapTypeSwitcherBtn.hovered ? "#f8f9fa" : "#1a1a1a")
                radius: 6
                border.color: "#404040"
                border.width: 1
            }

            contentItem: Text {
                text: mapTypeSwitcherBtn.text
                font.pixelSize: 14
                color: "#404040"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                console.log("🗺️ Map type button clicked")
                if (waypointsMap && typeof waypointsMap.cycleMapType !== 'undefined') {
                    var newType = waypointsMap.cycleMapType()
                    console.log("✅ Switched to:", newType)
                    if (typeof statusNotification !== 'undefined') {
                        statusNotification.color = "#404040"
                        statusNotificationLabel.text = "🗺️ Map: " + newType
                        statusNotification.opacity = 1
                        statusNotificationTimer.restart()
                    }
                } else {
                    console.log("❌ cycleMapType not available")
                }
            }

            ToolTip.visible: hovered
            ToolTip.text: "Switch map type"
            ToolTip.delay: 500
        }

        // Map Provider Switcher Button (Google/Bing/OSM)
        Button {
            id: mapProviderSwitcherBtn
            width: 35
            height: 35
            text: "🌐"

            background: Rectangle {
                color: mapProviderSwitcherBtn.pressed ? "#e9ecef" : (mapProviderSwitcherBtn.hovered ? "#f8f9fa" : "#1a1a1a")
                radius: 6
                border.color: "#404040"
                border.width: 1
            }

            contentItem: Text {
                text: mapProviderSwitcherBtn.text
                font.pixelSize: 14
                color: "#404040"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                console.log("🌐 Map provider button clicked")
                if (waypointsMap && typeof waypointsMap.cycleMapProvider !== 'undefined') {
                    var newProvider = waypointsMap.cycleMapProvider()
                    console.log("✅ Switched to provider:", newProvider)
                    if (typeof statusNotification !== 'undefined') {
                        statusNotification.color = "#28a745"
                        statusNotificationLabel.text = "🌐 Provider: " + newProvider
                        statusNotification.opacity = 1
                        statusNotificationTimer.restart()
                    }
                } else {
                    console.log("❌ cycleMapProvider not available")
                }
            }

            ToolTip.visible: hovered
            ToolTip.text: "Switch map provider (Google/Bing/OSM)"
            ToolTip.delay: 500
        }

        // Waypoint Dashboard Button
        Button {
            id: waypointDashboardBtn
            width: 35
            height: 35
            text: "📝"
           
            background: Rectangle {
                color: waypointDashboard.visible ? theme.accent :
                       (waypointDashboardBtn.pressed ? "#e9ecef" : (waypointDashboardBtn.hovered ? "#f8f9fa" : "#ffffff"))
                radius: 6
                border.color: theme.accent
                border.width: 1
               
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
           
            contentItem: Text {
                text: waypointDashboardBtn.text
                font.pixelSize: 14
                color: waypointDashboard.visible ? "white" : theme.textPrimary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                if (waypointDashboard.visible) {
                    waypointDashboard.hide();
                } else {
                    waypointDashboard.show();
                    testGetAllMarkers();
                   
                    var timer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 500; repeat: false; }', mainWindow);
                    timer.triggered.connect(function() {
                        updateWaypointDashboard();
                        timer.destroy();
                    });
                    timer.start();
                }
            }
        }
    }

    DropShadow {
        anchors.fill: parent
        horizontalOffset: 0
        verticalOffset: 3
        radius: 8
        samples: 17
        color: "#60000000"
        source: parent
    }
}
    }

  ListModel {
        id: rallyModel
    }

    // Rally Point Click Handler - Intercept map clicks
    Connections {
        target: waypointsMap
        
        function onLocationClicked(lat, lon) {
            // Check if in rally mode
            if (sidebar.mapMode === "rally") {
                addRallyPoint(lat, lon)
            } else {
                // Original behavior - show weather
                weatherDashboard.setLocation(lat, lon)
                if (!weatherDashboard.dashboardVisible) {
                    weatherDashboard.show()
                }
            }
        }
    }

    // Rally Point Functions - Now at ApplicationWindow root level
    function addRallyPoint(lat, lon) {
        console.log("🏁 Adding rally point at:", lat, lon)
        
        var altitude = 50.0  // Default rally altitude
        
        // Add to local model
        rallyModel.append({
            latitude: lat,
            longitude: lon,
            altitude: altitude
        })
        
        // Send to drone
        if (typeof droneCommander !== "undefined") {
            var success = droneCommander.sendRallyPoint(lat, lon, altitude)
            
            if (success) {
                statusNotification.color = "#2196f3"
                statusNotificationLabel.text = "🏁 Rally point " + rallyModel.count + " added"
            } else {
                statusNotification.color = theme.error
                statusNotificationLabel.text = "❌ Failed to add rally point"
                rallyModel.remove(rallyModel.count - 1)
            }
        } else {
            statusNotification.color = "#2196f3"
            statusNotificationLabel.text = "🏁 Rally point " + rallyModel.count + " added (local only)"
        }
        
        statusNotification.opacity = 1
        statusNotificationTimer.restart()
    }

    function clearRallyPoints() {
        rallyModel.clear()
        
        if (typeof droneCommander !== "undefined") {
            droneCommander.clearAllRallyPoints()
        }
    }



    // Marker Popup (unchanged)
    Popup {
        id: markerPopup
        width: 300
        height: 400
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
       
        property int markerIndex: -1
        property real altitude: 10
        property real speed: 1.5
       
        background: Rectangle {
            color: theme.cardBackground
            border.color: theme.border
            border.width: 1
            radius: theme.borderRadius
           
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                color: "#00000010"
                radius: parent.radius
                z: -1
            }
        }
       
        contentItem: Column {
            spacing: 12
            padding: 15
           
            Rectangle {
                width: parent.width - 10
                height: 40
                color: theme.accent
                radius: theme.borderRadius
               
                Text {
                    text: "Waypoint " + (markerPopup.markerIndex + 1)
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Consolas"
                    color: "white"
                    anchors.centerIn: parent
                }
               
                Button {
                    width: 30
                    height: 30
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    contentItem: Text { text: "✖"; color: "white"; font.pixelSize: 14; font.family: "Consolas" }
                    background: Rectangle {
                        color: parent.hovered ? "#ffffff20" : "transparent"
                        radius: 4
                    }
                    onClicked: markerPopup.close()
                }
            }
           
            Text {
                text: "💡 Tip: Drag marker to move it"
                font.pixelSize: 12
                font.family: "Consolas"
                color: theme.textSecondary
                font.italic: true
            }
           
            Column {
                width: parent.width - 10
                spacing: 5
                Text { text: "Altitude (m):"; font.pixelSize: 14; font.family: "Consolas"; color: theme.textPrimary }
                Row {
                    spacing: 3
                    width: parent.width
                    height: 35
               
                    Button {
                        width: 35; height: parent.height
                        contentItem: Text { text: "−"; color: "white"; font.pixelSize: 16; font.bold: true; font.family: "Consolas" }
                        background: Rectangle { color: theme.accent; radius: 4 }
                        onClicked: {
                            if (markerPopup.altitude > 1) {
                                markerPopup.altitude -= 1;
                                altitudeField.text = markerPopup.altitude.toString();
                            }
                        }
                    }
                   
                    TextField {
                        id: altitudeField
                        width: parent.width - 115; height: parent.height
                        text: markerPopup.altitude.toString()
                        validator: DoubleValidator { bottom: 0; decimals: 1 }
                        font.pixelSize: 14
                        font.family: "Consolas"
                        horizontalAlignment: Text.AlignHCenter
                        background: Rectangle {
                            color: "#ffffff"
                            radius: 4
                            border.color: theme.border
                            border.width: 1
                        }
                        color: theme.textPrimary
                    }
                   
                    Button {
                        width: 35; height: parent.height
                        contentItem: Text { text: "+"; color: "white"; font.pixelSize: 16; font.bold: true; font.family: "Consolas" }
                        background: Rectangle { color: theme.accent; radius: 4 }
                        onClicked: {
                            markerPopup.altitude += 1;
                            altitudeField.text = markerPopup.altitude.toString();
                        }
                    }
                   
                    Button {
                        width: 35; height: parent.height
                        contentItem: Text { text: "✓"; color: "white"; font.pixelSize: 16; font.bold: true; font.family: "Consolas" }
                        background: Rectangle { color: theme.success; radius: 4 }
                        onClicked: {
                            var val = parseFloat(altitudeField.text);
                            if (!isNaN(val) && markerPopup.markerIndex >= 0) {
                                markerPopup.altitude = val;
                                waypointsMap.updateMarkerAltitude(markerPopup.markerIndex, val);
                            }
                        }
                    }
                }
            }
           
            Column {
                width: parent.width - 10
                spacing: 5
                Text { text: "Speed (m/s):"; font.pixelSize: 14; font.family: "Consolas"; color: theme.textPrimary }
                Row {
                    spacing: 3
                    width: parent.width
                    height: 35
               
                    Button {
                        width: 35; height: parent.height
                        contentItem: Text { text: "−"; color: "white"; font.pixelSize: 16; font.bold: true; font.family: "Consolas" }
                        background: Rectangle { color: theme.accent; radius: 4 }
                        onClicked: {
                            if (markerPopup.speed > 0.5) {
                                markerPopup.speed -= 0.5;
                                speedField.text = markerPopup.speed.toString();
                            }
                        }
                    }
                   
                    TextField {
                        id: speedField
                        width: parent.width - 115; height: parent.height
                        text: markerPopup.speed.toString()
                        validator: DoubleValidator { bottom: 0; decimals: 1 }
                        font.pixelSize: 14
                        font.family: "Consolas"
                        horizontalAlignment: Text.AlignHCenter
                        background: Rectangle {
                            color: "#ffffff"
                            radius: 4
                            border.color: theme.border
                            border.width: 1
                        }
                        color: theme.textPrimary
                    }
                   
                    Button {
                        width: 35; height: parent.height
                        contentItem: Text { text: "+"; color: "white"; font.pixelSize: 16; font.bold: true; font.family: "Consolas" }
                        background: Rectangle { color: theme.accent; radius: 4 }
                        onClicked: {
                            markerPopup.speed += 0.5;
                            speedField.text = markerPopup.speed.toString();
                        }
                    }
                   
                    Button {
                        width: 35; height: parent.height
                        contentItem: Text { text: "✓"; color: "white"; font.pixelSize: 16; font.bold: true; font.family: "Consolas" }
                        background: Rectangle { color: theme.success; radius: 4 }
                        onClicked: {
                            var val = parseFloat(speedField.text);
                            if (!isNaN(val) && markerPopup.markerIndex >= 0) {
                                markerPopup.speed = val;
                                waypointsMap.updateMarkerSpeed(markerPopup.markerIndex, val);
                            }
                        }
                    }
                }
            }
           
            Button {
                width: parent.width - 10
                height: 40
                contentItem: Text { text: "🗑️ Delete Waypoint"; color: "white"; font.pixelSize: 14; font.family: "Consolas" }
                background: Rectangle { color: theme.error; radius: 4 }
                onClicked: {
                    if (markerPopup.markerIndex >= 0) {
                        waypointsMap.deleteMarkerJS(markerPopup.markerIndex);
                        markerPopup.close();
                    }
                }
            }
        }
    }
Popup {
    id: surveySettingsPopup
    width: 450
    height: 600  // Increased height to accommodate new field
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
   
    background: Rectangle {
        color: "#2c3e50"
        border.color: "#e91e63"
        border.width: 2
        radius: 8
    }
   
    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15
       
        // Header
        Text {
            text: "⚙ Survey Settings"
            font.pixelSize: 18
            font.bold: true
            color: "white"
        }
       
        // Altitude
        Column {
            width: parent.width
            spacing: 5
           
            Text {
                text: "Altitude (m)"
                font.pixelSize: 13
                color: "#ecf0f1"
            }
           
            TextField {
                id: altitudeInput
                width: parent.width
                height: 40
                text: waypointsMap.surveyAltitude
                validator: DoubleValidator { bottom: 10; top: 500 }
                font.pixelSize: 14
                background: Rectangle {
                    color: "#34495e"
                    border.color: "#e91e63"
                    radius: 4
                }
                color: "white"
            }
        }
       
        // Line Spacing (NEW - Direct control in meters)
        Column {
            width: parent.width
            spacing: 5
           
            Text {
                text: "Line Spacing (m) - Gap between survey lines"
                font.pixelSize: 13
                color: "#ecf0f1"
                wrapMode: Text.WordWrap
            }
           
            Row {
                width: parent.width
                spacing: 10
               
                TextField {
                    id: lineSpacingInput
                    width: parent.width - 80
                    height: 40
                    text: "25"  // Default 25 meters
                    validator: DoubleValidator { bottom: 5; top: 200 }
                    font.pixelSize: 14
                    background: Rectangle {
                        color: "#34495e"
                        border.color: "#e91e63"
                        radius: 4
                    }
                    color: "white"
                    placeholderText: "5-200m"
                }
               
                Text {
                    text: "meters"
                    font.pixelSize: 12
                    color: "#95a5a6"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            // Helper text
            Text {
                text: "💡 Smaller = closer lines, more coverage"
                font.pixelSize: 11
                color: "#95a5a6"
                font.italic: true
            }
        }
       
        // Overlap
        Column {
            width: parent.width
            spacing: 5
           
            Text {
                text: "Overlap (%) - Forward image overlap"
                font.pixelSize: 13
                color: "#ecf0f1"
            }
           
            TextField {
                id: overlapInput
                width: parent.width
                height: 40
                text: waypointsMap.surveyOverlap
                validator: DoubleValidator { bottom: 0; top: 95 }
                font.pixelSize: 14
                background: Rectangle {
                    color: "#34495e"
                    border.color: "#e91e63"
                    radius: 4
                }
                color: "white"
            }
        }
       
        // Sidelap (Keep this for advanced users, or remove if you prefer)
        Column {
            width: parent.width
            spacing: 5
           
            Text {
                text: "Sidelap (%) - Auto-calculated from Line Spacing"
                font.pixelSize: 13
                color: "#95a5a6"
            }
           
            TextField {
                id: sidelapInput
                width: parent.width
                height: 40
                text: waypointsMap.surveySidelap
                validator: DoubleValidator { bottom: 0; top: 95 }
                font.pixelSize: 14
                background: Rectangle {
                    color: "#34495e"
                    border.color: "#e91e63"
                    radius: 4
                }
                color: "white"
                readOnly: true  // Make it read-only since it's auto-calculated
                opacity: 0.7
            }
        }
       
        // Grid Angle
        Column {
            width: parent.width
            spacing: 5
           
            Text {
                text: "Grid Angle (°)"
                font.pixelSize: 13
                color: "#ecf0f1"
            }
           
            TextField {
                id: gridAngleInput
                width: parent.width
                height: 40
                text: waypointsMap.surveyAngle
                validator: DoubleValidator { bottom: 0; top: 360 }
                font.pixelSize: 14
                background: Rectangle {
                    color: "#34495e"
                    border.color: "#e91e63"
                    radius: 4
                }
                color: "white"
            }
        }
       
        // Speed
        Column {
            width: parent.width
            spacing: 5
           
            Text {
                text: "Speed (m/s)"
                font.pixelSize: 13
                color: "#ecf0f1"
            }
           
            TextField {
                id: speedInput
                width: parent.width
                height: 40
                text: waypointsMap.surveySpeed
                validator: DoubleValidator { bottom: 0.5; top: 20 }
                font.pixelSize: 14
                background: Rectangle {
                    color: "#34495e"
                    border.color: "#e91e63"
                    radius: 4
                }
                color: "white"
            }
        }
       
        // Buttons Row
        Row {
            width: parent.width
            spacing: 10
           
            Button {
                width: (parent.width - 10) / 2
                height: 45
                text: "Cancel"
                background: Rectangle {
                    color: parent.pressed ? "#7f8c8d" : "#95a5a6"
                    radius: 6
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                onClicked: surveySettingsPopup.close()
            }
           
            Button {
                width: (parent.width - 10) / 2
                height: 45
                text: "Apply & Regenerate"
                background: Rectangle {
                    color: parent.pressed ? "#c2185b" : "#e91e63"
                    radius: 6
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }
                onClicked: {
                    var altitude = parseFloat(altitudeInput.text);
                    var lineSpacing = parseFloat(lineSpacingInput.text);
                   
                    // Calculate sidelap from line spacing
                    // Assumption: Camera footprint width = altitude * 0.8 (adjust based on your camera)
                    var cameraFootprintWidth = altitude * 0.8;
                    var calculatedSidelap = ((cameraFootprintWidth - lineSpacing) / cameraFootprintWidth) * 100;
                   
                    // Clamp sidelap between 0 and 95
                    calculatedSidelap = Math.max(0, Math.min(95, calculatedSidelap));
                   
                    // Apply values
                    waypointsMap.surveyAltitude = altitude;
                    waypointsMap.surveyOverlap = parseFloat(overlapInput.text);
                    waypointsMap.surveySidelap = calculatedSidelap;
                    waypointsMap.surveyAngle = parseFloat(gridAngleInput.text);
                    waypointsMap.surveySpeed = parseFloat(speedInput.text);
                   
                    // Update sidelap display
                    sidelapInput.text = calculatedSidelap.toFixed(1);
                   
                    console.log("📐 Line Spacing:", lineSpacing, "m → Sidelap:", calculatedSidelap.toFixed(1), "%");
                   
                    waypointsMap.generateSurveyPattern();
                    surveySettingsPopup.close();
                }
            }
        }
    }
   
    // Initialize line spacing when popup opens
    onOpened: {
        altitudeInput.text = waypointsMap.surveyAltitude || "50";
        overlapInput.text = waypointsMap.surveyOverlap || "70";
        sidelapInput.text = waypointsMap.surveySidelap || "60";
        gridAngleInput.text = waypointsMap.surveyAngle || "0";
        speedInput.text = waypointsMap.surveySpeed || "1.5";
       
        // Calculate initial line spacing from current sidelap
        var altitude = parseFloat(altitudeInput.text);
        var sidelap = parseFloat(sidelapInput.text);
        var cameraFootprintWidth = altitude * 0.8;
        var initialLineSpacing = cameraFootprintWidth * (1 - sidelap / 100);
        lineSpacingInput.text = initialLineSpacing.toFixed(1);
    }
}

// ========================================
// DRONE COMMANDER SIGNAL HANDLERS
// ========================================
Connections {
    target: typeof droneCommander !== 'undefined' ? droneCommander : null
    
    function onCommandFeedback(message) {
        console.log("📡 DroneCommander feedback:", message);
        
        // Check for success messages
        if (message.indexOf("Mission upload successful") !== -1 ||
            message.indexOf("Mission uploaded successfully") !== -1 ||
            message.indexOf("All waypoints sent") !== -1 ||
            message.indexOf("Flight plan received") !== -1) {
            
            console.log("✅ Mission upload SUCCESS detected!");
            
            // Get the actual waypoints data that was sent
            var markersData = waypointsMap.getAllMarkers();
            
            // Populate the detailed popup with waypoint information
            uploadSuccessPopup.populateWaypoints(markersData);
            uploadSuccessPopup.open();
            
            // Also show green notification
            statusNotification.color = theme.success;
            statusNotificationLabel.text = "✅ Mission uploaded: " + markersData.length + " waypoints";
            statusNotification.opacity = 1;
            statusNotificationTimer.restart();
        }
        
        // Check for error messages
        else if (message.indexOf("failed") !== -1 ||
                 message.indexOf("Error") !== -1 ||
                 message.indexOf("❌") !== -1 ||
                 message.indexOf("denied") !== -1) {
            
            console.log("❌ Mission upload ERROR detected!");
            
            uploadErrorPopup.errorMessage = message;
            uploadErrorPopup.open();
            
            // Also show red notification
            statusNotification.color = theme.error;
            statusNotificationLabel.text = "❌ Upload failed";
            statusNotification.opacity = 1;
            statusNotificationTimer.restart();
        }
    }
}
WeatherDashboard {
    id: weatherDashboard
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: 20
    anchors.bottomMargin: 20
    width: 350
    height: expanded ? (hasWarnings ? 400 : 320) : 60
    visible: dashboardVisible  // Make sure this uses the internal property
    z: 100
}

// ═══════════════════════════════════════════════════════════════════════
// RALLY POINTS DASHBOARD
// ═══════════════════════════════════════════════════════════════════════

Rectangle {
    id: rallyDashboard
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.topMargin: header.height + 20
    anchors.leftMargin: 20
    width: 280
    height: expanded ? (rallyModel.count * 60 + 120) : 60
    radius: 8
    color: "#2c3e50"
    border.color: "#2196f3"
    border.width: 2
    opacity: 0.95
    visible: rallyModel.count > 0
    z: 100
    
    property bool expanded: true
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 10
        
        // Header
        Row {
            width: parent.width
            spacing: 10
            
            Text {
                text: "🏁 Rally Points"
                font.pixelSize: 16
                font.bold: true
                color: "#2196f3"
                font.family: "Consolas"
            }
            
            Item { width: parent.width - 120 }
            
            Text {
                text: rallyModel.count
                font.pixelSize: 16
                font.bold: true
                color: "white"
                font.family: "Consolas"
            }
            
            Button {
                width: 30
                height: 30
                
                background: Rectangle {
                    color: parent.hovered ? "#34495e" : "transparent"
                    radius: 4
                }
                
                contentItem: Text {
                    text: rallyDashboard.expanded ? "▼" : "▶"
                    color: "white"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: rallyDashboard.expanded = !rallyDashboard.expanded
            }
        }
        
        // Rally points list
        ListView {
            width: parent.width
            height: rallyModel.count * 60
            clip: true
            visible: rallyDashboard.expanded
            interactive: false
            
            model: rallyModel
            
            delegate: Rectangle {
                width: parent.width
                height: 55
                color: "#34495e"
                radius: 6
                border.color: "#2196f3"
                border.width: 1
                
                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    
                    Row {
                        spacing: 8
                        
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: "#2196f3"
                            
                            Text {
                                text: "R" + (index + 1)
                                font.pixelSize: 10
                                font.bold: true
                                color: "white"
                                anchors.centerIn: parent
                            }
                        }
                        
                        Text {
                            text: "Rally Point " + (index + 1)
                            font.pixelSize: 13
                            font.bold: true
                            color: "white"
                        }
                    }
                    
                    Text {
                        text: "📍 " + model.latitude.toFixed(6) + "°, " + 
                              model.longitude.toFixed(6) + "°"
                        font.pixelSize: 10
                        font.family: "Courier New"
                        color: "#ecf0f1"
                    }
                    
                    Text {
                        text: "⬆️ Alt: " + model.altitude.toFixed(1) + "m"
                        font.pixelSize: 10
                        color: "#ecf0f1"
                    }
                }
                
                Button {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    
                    background: Rectangle {
                        color: parent.hovered ? "#e74c3c" : "#c0392b"
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: "✖"
                        color: "white"
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                    }
                    
                    onClicked: {
                        rallyModel.remove(index)
                        
                        statusNotification.color = theme.error
                        statusNotificationLabel.text = "🗑️ Rally point removed"
                        statusNotification.opacity = 1
                        statusNotificationTimer.restart()
                    }
                }
            }
        }
    }
    
    DropShadow {
        anchors.fill: parent
        horizontalOffset: 0
        verticalOffset: 3
        radius: 8
        samples: 17
        color: "#60000000"
        source: parent
    }
}
    WaypointDashboard {
    id: waypointDashboard
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: header.height + 20
    anchors.rightMargin: 20
    visible: false
    z: 100
    mapView: waypointsMap  // Connect to the map component
}
PolygonDashboard {
    id: polygonDashboard
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 20
    anchors.bottomMargin: 20
    visible: false
    z: 100
}
// ✅ NEW: Live Mission Status Dashboard
Rectangle {
    id: missionStatusDashboard
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: 20
    anchors.topMargin: 100
    width: 280
    height: 140
    radius: 8
    color: "#2c3e50"
    border.color: "#00FF00"
    border.width: 2
    opacity: 0.95
    visible: waypointsMap.missionActive
    z: 200
   
    Column {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 10
       
        // Header
        Text {
            text: "🚁 MISSION ACTIVE"
            font.pixelSize: 16
            font.bold: true
            color: "#00FF00"
            font.family: "Consolas"
        }
       
        // Current waypoint
        Text {
            text: "Waypoint: " + (waypointsMap.currentWaypointIndex + 1) + " / " + waypointsMap.markers.length
            font.pixelSize: 14
            color: "white"
            font.family: "Consolas"
        }
       
        // Distance to target
        Text {
            id: distanceText
            text: "Distance: calculating..."
            font.pixelSize: 13
            color: "#ecf0f1"
            font.family: "Consolas"
           
            Timer {
                interval: 500
                running: waypointsMap.missionActive
                repeat: true
               
                onTriggered: {
                    if (waypointsMap.currentWaypointIndex >= 0 &&
                        waypointsMap.currentWaypointIndex < waypointsMap.markers.length) {
                       
                        var targetWP = waypointsMap.markers[waypointsMap.currentWaypointIndex]
                        var dist = waypointsMap.calculateDistance(
                            waypointsMap.currentLat,
                            waypointsMap.currentLon,
                            targetWP.lat,
                            targetWP.lng
                        )
                       
                        distanceText.text = "Distance: " + dist.toFixed(1) + "m"
                    }
                }
            }
        }
       
        // Path traveled
        Text {
            text: "Path: " + waypointsMap.actualFlightPath.length + " points"
            font.pixelSize: 13
            color: "#ecf0f1"
            font.family: "Consolas"
        }
       
        // Stop button
        Button {
            width: parent.width - 30
            height: 35
           
            background: Rectangle {
                color: parent.pressed ? "#c0392b" : "#e74c3c"
                radius: 6
            }
           
            contentItem: Text {
                text: "🛑 STOP MISSION"
                color: "white"
                font.bold: true
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }
           
            onClicked: {
                waypointsMap.stopMissionTracking()
            }
        }
    }
}
   // Updated Sidebar with language translations
Drawer {
    id: sidebar
    width: 300
    height: parent.height - 70
    y: header.height
    modal: false
    dim: false
    interactive: false
       property string mapMode: "waypoint"  // "waypoint" or "rally"
    background: Rectangle {
        color: "#ffffff"
        border.color: theme.border
        border.width: 1
    }
   
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15
       
        Text {
            text: "Mission Upload" // You can add this to translations later
            color: theme.textPrimary
            font.pixelSize: 14
            font.bold: true
            font.family: "Consolas"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
       
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
                    text: "Add " + languageManager.getText("Waypoints")
                    color: theme.textPrimary
                    font.pixelSize: 14
                    font.family: "Consolas"
                    Layout.fillWidth: true
                }
            }
            onClicked: {
                waypointsMap.setAddMarkersModeJS(true);
                // Auto-show waypoint dashboard when adding waypoints
                if (!waypointDashboard.visible) {
                    waypointDashboard.show();
                    Qt.callLater(function() {
                        updateWaypointDashboard();
                    });
                }
            }
        }
       
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
                    text: "Send " + languageManager.getText("Waypoints")
                    color: theme.textPrimary
                    font.pixelSize: 14
                    font.family: "Consolas"
                    Layout.fillWidth: true
                }
            }
            onClicked: sendMarkers()
        }
       
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
                    text: "Clear " + languageManager.getText("Waypoints")
                    color: theme.textPrimary
                    font.pixelSize: 14
                    font.family: "Consolas"
                    Layout.fillWidth: true
                }
            }
            onClicked: {
                waypointsMap.clearAllMarkersJS();
                lastClickedCoordinate = null;

                // Clear the mission path stored on the backend model so any
                // secondary map view also loses its path line.
                if (typeof droneModel !== "undefined" && droneModel) {
                    droneModel.setMissionPath([])
                }

                // Reset header statistics to zero
                totalWaypointsText.text   = "0"
                totalDistanceText.text    = "0.0 km"
                coveredDistanceText.text  = "0.0 km"
                estimatedTimeText.text    = "0m 0s"

                // Hide the waypoint dashboard
                waypointDashboard.hide()

                // Update dashboard after clearing in case it is still visible
                Qt.callLater(function() { updateWaypointDashboard() })
            }
        }

// Polygon Survey Button (Opens Menu)
Button {
    Layout.fillWidth: true
    height: 50
   
    background: Rectangle {
        color: waypointsMap.polygonSurveyMode ? "#f3e5f5" :
               (parent.hovered ? "#f3e5f5" : "#f8f9fa")
        radius: 8
        border.color: waypointsMap.polygonSurveyMode ? "#9c27b0" : theme.border
        border.width: waypointsMap.polygonSurveyMode ? 2 : 1
       
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }
   
    contentItem: RowLayout {
        spacing: 10
       
        Text {
            text: "📐"
            font.pixelSize: 16
            font.family: "Consolas"
            color: "#9c27b0"
        }
       
        Text {
            text: waypointsMap.polygonSurveyMode ?
                  "Polygon Menu (" + waypointsMap.polygonCorners.length + ")" :
                  "Polygon Survey"
            color: theme.textPrimary
            font.pixelSize: 14
            font.family: "Consolas"
            Layout.fillWidth: true
        }
       
        // Arrow indicator
        Text {
            text: "▶"
            font.pixelSize: 12
            color: "#9c27b0"
            rotation: polygonMenuPopup.visible ? 90 : 0
           
            Behavior on rotation {
                NumberAnimation { duration: 200 }
            }
        }
    }
   
    onClicked: {
        if (polygonMenuPopup.visible) {
            polygonMenuPopup.close()
        } else {
            polygonMenuPopup.open()
        }
    }
   
    ToolTip.visible: hovered
    ToolTip.text: "Open polygon survey menu"
    ToolTip.delay: 500
}
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
            text: "Save " + languageManager.getText("Waypoints")
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
            text: "Load " + languageManager.getText("Waypoints")
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
    // ═══════════════════════════════════════════════════════════════
        // RALLY POINTS SECTION
        // ═══════════════════════════════════════════════════════════════

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 2
            color: theme.border
            Layout.topMargin: 10
            Layout.bottomMargin: 10
        }

        // Rally Points Header
        Text {
            text: "Rally Points"
            color: theme.textPrimary
            font.pixelSize: 14
            font.bold: true
            font.family: "Consolas"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        // Add Rally Points Button
        Button {
            Layout.fillWidth: true
            height: 50
            
            background: Rectangle {
                color: sidebar.mapMode === "rally" ? "#e3f2fd" :
                       (parent.hovered ? "#f3e5f5" : "#f8f9fa")
                radius: 8
                border.color: sidebar.mapMode === "rally" ? "#2196f3" : theme.border
                border.width: sidebar.mapMode === "rally" ? 2 : 1
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: RowLayout {
                spacing: 10
                
                Text {
                    text: "🏁"
                    font.pixelSize: 16
                    font.family: "Consolas"
                    color: "#2196f3"
                }
                
                Text {
                    text: sidebar.mapMode === "rally" ? 
                          "Rally Mode (Active)" : "Add Rally Points"
                    color: theme.textPrimary
                    font.pixelSize: 14
                    font.family: "Consolas"
                    Layout.fillWidth: true
                }
            }
            
            onClicked: {
                if (sidebar.mapMode === "rally") {
                    sidebar.mapMode = "waypoint"
                    statusNotification.color = theme.textSecondary
                    statusNotificationLabel.text = "📍 Waypoint mode activated"
                } else {
                    sidebar.mapMode = "rally"
                    waypointsMap.addMarkersMode = false
                    statusNotification.color = "#2196f3"
                    statusNotificationLabel.text = "🏁 Rally mode - Click map to add rally points"
                }
                statusNotification.opacity = 1
                statusNotificationTimer.restart()
            }
            
            ToolTip.visible: hovered
            ToolTip.text: sidebar.mapMode === "rally" ? 
                          "Switch to waypoint mode" : 
                          "Switch to rally point mode"
            ToolTip.delay: 500
        }

        // Clear Rally Points Button
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
                
                Text {
                    text: "🗑️"
                    font.pixelSize: 16
                    font.family: "Consolas"
                    color: theme.error
                }
                
                Text {
                    text: "Clear Rally Points"
                    color: theme.textPrimary
                    font.pixelSize: 14
                    font.family: "Consolas"
                    Layout.fillWidth: true
                }
            }
            
            onClicked: {
                rallyModel.clear()
                if (typeof droneCommander !== "undefined") {
                    droneCommander.clearAllRallyPoints()
                }
                
                statusNotification.color = theme.success
                statusNotificationLabel.text = "✅ Rally points cleared"
                statusNotification.opacity = 1
                statusNotificationTimer.restart()
            }
        }

        // Spacer to push everything up
        Item { 
            Layout.fillHeight: true 
        }
        
        // Footer text
        Text {
            color: theme.textSecondary
            font.pixelSize: 12
            font.family: "Consolas"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
        }
       
        Text {
            color: theme.textSecondary
            font.pixelSize: 12
            font.family: "Consolas"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
        }
       
    }

 
}

// Save Waypoints Popup
Popup {
    id: saveWaypointsPopup
    width: 500
    height: 350
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
   
    background: Rectangle {
        color: theme.cardBackground
        border.color: theme.border
        border.width: 1
        radius: theme.borderRadius
       
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            color: "#00000010"
            radius: parent.radius
            z: -1
        }
    }
   
    contentItem: Column {
        spacing: 15
        padding: 20
       
        // Header
        Rectangle {
            width: parent.width - 40
            height: 50
            color: theme.accent
            radius: theme.borderRadius
           
            Text {
                text: "💾 Save Waypoints"
                font.pixelSize: 18
                font.bold: true
                font.family: "Consolas"
                color: "white"
                anchors.centerIn: parent
            }
           
            Button {
                width: 35
                height: 35
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
               
                contentItem: Text {
                    text: "✖"
                    color: "white"
                    font.pixelSize: 16
                    font.family: "Consolas"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
               
                background: Rectangle {
                    color: parent.hovered ? "#ffffff20" : "transparent"
                    radius: 4
                }
               
                onClicked: saveWaypointsPopup.close()
            }
        }
       
        // Info Text
        Text {
            text: "Enter a filename for your waypoints mission:"
            font.pixelSize: 14
            font.family: "Consolas"
            color: theme.textPrimary
            width: parent.width - 40
            wrapMode: Text.WordWrap
        }
       
        // Filename Input
        Column {
            width: parent.width - 40
            spacing: 8
           
            Text {
                text: "Filename:"
                font.pixelSize: 13
                font.family: "Consolas"
                color: theme.textSecondary
            }
           
            Row {
                width: parent.width
                spacing: 8
               
                TextField {
                    id: saveFilenameInput
                    width: parent.width - 120
                    height: 45
                    placeholderText: "my_mission"
                    font.pixelSize: 14
                    font.family: "Consolas"
                   
                    background: Rectangle {
                        color: "#ffffff"
                        radius: 6
                        border.color: saveFilenameInput.activeFocus ? theme.accent : theme.border
                        border.width: saveFilenameInput.activeFocus ? 2 : 1
                    }
                   
                    color: theme.textPrimary
                   
                    // Set default filename when popup opens
                    Component.onCompleted: {
                        text = "mission_" + Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss")
                    }
                }
               
                Text {
                    text: ".waypoints"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    color: theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
       
        // Waypoint Count Info
        Rectangle {
            width: parent.width - 40
            height: 45
            color: "#f8f9fa"
            radius: 6
            border.color: theme.border
            border.width: 1
           
            Row {
                anchors.centerIn: parent
                spacing: 10
               
                Text {
                    text: "📍"
                    font.pixelSize: 20
                }
               
                Text {
                    text: waypointsMap.markers.length + " waypoint(s) will be saved"
                    font.pixelSize: 13
                    font.family: "Consolas"
                    color: theme.textSecondary
                }
            }
        }
       
        // Buttons
        Row {
            width: parent.width - 40
            spacing: 10
           
            Button {
                width: (parent.width - 10) / 2
                height: 50
               
                background: Rectangle {
                    color: parent.pressed ? "#e9ecef" : (parent.hovered ? "#f8f9fa" : "#ffffff")
                    radius: 6
                    border.color: theme.border
                    border.width: 1
                   
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
               
                contentItem: Text {
                    text: "Cancel"
                    color: theme.textPrimary
                    font.pixelSize: 15
                    font.family: "Consolas"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
               
                onClicked: saveWaypointsPopup.close()
            }
           
            Button {
                width: (parent.width - 10) / 2
                height: 50
               
                background: Rectangle {
                    color: parent.pressed ? "#0056b3" : (parent.hovered ? "#0069d9" : theme.accent)
                    radius: 6
                   
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
               
                contentItem: Text {
                    text: "💾 Save File"
                    color: "white"
                    font.pixelSize: 15
                    font.family: "Consolas"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
               
                onClicked: {
                    if (saveFilenameInput.text.trim().length === 0) {
                        statusNotification.color = theme.error
                        statusNotification.children[0].text = "⚠️ Please enter a filename"
                        mainWindow.statusNotification.opacity = 1
                        statusNotificationTimer.restart()
                        return
                    }
                   
                    var filename = saveFilenameInput.text.trim()
                   
                    // Remove .waypoints extension if user added it
                    if (filename.endsWith(".waypoints")) {
                        filename = filename.slice(0, -11)
                    }
                   
                    saveWaypointsPopup.close()
                    saveWaypointsData(filename)
                }
            }
        }
    }
   
 onOpened: {
        // Set sensible defaults when popup opens
        altitudeInput.text = waypointsMap.surveyAltitude || "50"
        overlapInput.text = waypointsMap.surveyOverlap || "70"
        sidelapInput.text = waypointsMap.surveySidelap || "60"
        gridAngleInput.text = waypointsMap.surveyAngle || "0"
        speedInput.text = waypointsMap.surveySpeed || "1.5"
    }
}

// Load Waypoints Popup
Popup {
    id: loadWaypointsPopup
    width: 550
    height: 450
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
   
    background: Rectangle {
        color: theme.cardBackground
        border.color: theme.border
        border.width: 1
        radius: theme.borderRadius
       
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            color: "#00000010"
            radius: parent.radius
            z: -1
        }
    }
   
    contentItem: Column {
        spacing: 15
        padding: 20
       
        // Header
        Rectangle {
            width: parent.width - 40
            height: 50
            color: theme.success
            radius: theme.borderRadius
           
            Text {
                text: "📂 Load Waypoints"
                font.pixelSize: 18
                font.bold: true
                font.family: "Consolas"
                color: "white"
                anchors.centerIn: parent
            }
           
            Button {
                width: 35
                height: 35
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
               
                contentItem: Text {
                    text: "✖"
                    color: "white"
                    font.pixelSize: 16
                    font.family: "Consolas"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
               
                background: Rectangle {
                    color: parent.hovered ? "#ffffff20" : "transparent"
                    radius: 4
                }
               
                onClicked: loadWaypointsPopup.close()
            }
        }
       
        // File Selection
        Column {
            width: parent.width - 40
            spacing: 8
           
            Text {
                text: "Selected File:"
                font.pixelSize: 13
                font.family: "Consolas"
                color: theme.textSecondary
            }
           
            Row {
                width: parent.width
                spacing: 10
               
                Rectangle {
                    width: parent.width - 150
                    height: 45
                    color: "#f8f9fa"
                    radius: 6
                    border.color: theme.border
                    border.width: 1
                   
                    Text {
                        id: selectedFileText
                        anchors.fill: parent
                        anchors.margins: 12
                        text: "No file selected"
                        font.pixelSize: 12
                        font.family: "Consolas"
                        color: theme.textSecondary
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                    }
                }
               
                Button {
                    width: 135
                    height: 45
                   
                    background: Rectangle {
                        color: parent.pressed ? "#0056b3" : (parent.hovered ? "#0069d9" : theme.accent)
                        radius: 6
                       
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                   
                    contentItem: Text {
                        text: "📁 Browse..."
                        color: "white"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                   
                    onClicked: {
                        openWaypointsDialog.open()
                    }
                }
            }
        }
       
        // Data Preview
        Column {
            width: parent.width - 40
            spacing: 8
           
            Text {
                text: "File Preview:"
                font.pixelSize: 13
                font.family: "Consolas"
                color: theme.textSecondary
            }
           
            Rectangle {
                width: parent.width
                height: 180
                color: "#f8f9fa"
                radius: 6
                border.color: theme.border
                border.width: 1
                clip: true
               
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                   
                    TextArea {
                        id: loadDataInput
                        readOnly: true
                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        font.pixelSize: 11
                        font.family: "Courier New"
                        color: theme.textPrimary
                        placeholderText: "Select a .waypoints file to preview its contents..."
                        background: Rectangle { color: "transparent" }
                    }
                }
            }
        }
       
        // Buttons
        Row {
            width: parent.width - 40
            spacing: 10
           
            Button {
                width: (parent.width - 10) / 2
                height: 50
               
                background: Rectangle {
                    color: parent.pressed ? "#e9ecef" : (parent.hovered ? "#f8f9fa" : "#ffffff")
                    radius: 6
                    border.color: theme.border
                    border.width: 1
                   
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
               
                contentItem: Text {
                    text: "Cancel"
                    color: theme.textPrimary
                    font.pixelSize: 15
                    font.family: "Consolas"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
               
                onClicked: loadWaypointsPopup.close()
            }
           
            Button {
                width: (parent.width - 10) / 2
                height: 50
                enabled: loadDataInput.text.length > 0
               
                background: Rectangle {
                    color: parent.enabled ?
                           (parent.pressed ? "#1e7e34" : (parent.hovered ? "#218838" : theme.success)) :
                           "#cccccc"
                    radius: 6
                   
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
               
                contentItem: Text {
                    text: "📂 Load Mission"
                    color: "white"
                    font.pixelSize: 15
                    font.family: "Consolas"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
               
                onClicked: {
                    if (loadDataInput.text.trim().length === 0) {
                        statusNotification.color = theme.error
                        statusNotification.children[0].text = "⚠️ No file data to load"
                        mainWindow.statusNotification.opacity = 1
                        statusNotificationTimer.restart()
                        return
                    }
                   
                    loadWaypointsPopup.close()
                    loadWaypointsData(loadDataInput.text)
                }
            }
        }
    }
   
    onOpened: {
        loadDataInput.text = ""
        selectedFileText.text = "No file selected"
    }
}
// Polygon Survey Menu Popup - UPDATED UI
Popup {
    id: polygonMenuPopup
    width: 200
    height: contentItem.implicitHeight + 20
    x: sidebar.width + 20
    y: 200
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
   
    property int cornerCount: waypointsMap.polygonCorners.length
   
    Connections {
        target: waypointsMap
        function onPolygonCornersChanged() {
            polygonMenuPopup.cornerCount = waypointsMap.polygonCorners.length
        }
    }
   
    background: Rectangle {
        color: "white"
        border.color: "#e0e0e0"
        border.width: 1
        radius: 8
       
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 2
            radius: 8
            samples: 17
            color: "#40000000"
        }
    }
   
    contentItem: Column {
        spacing: 0
        width: parent.width
       
        // 1. Draw Polygon Button
        Rectangle {
            width: parent.width
            height: 50
            color: waypointsMap.polygonSurveyMode ? "#ffe8f5" :
                   (drawPolygonMouseArea.containsMouse ? "#f5f5f5" : "white")
           
            // Left colored border indicator
            Rectangle {
                width: 4
                height: parent.height
                color: "#ff1493"
                anchors.left: parent.left
                visible: waypointsMap.polygonSurveyMode
            }
           
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                spacing: 10
               
                Text {
                    text: waypointsMap.polygonSurveyMode ?
                          "Drawing... (" + polygonMenuPopup.cornerCount + ")" :
                          "Draw Polygon"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    color: waypointsMap.polygonSurveyMode ? "#ff1493" : "#333333"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            MouseArea {
                id: drawPolygonMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
               
                onClicked: {
                    if (!waypointsMap.polygonSurveyMode) {
                        waypointsMap.polygonSurveyMode = true
                        waypointsMap.addMarkersMode = false
                        waypointsMap.polygonCorners = []
                        waypointsMap.clearAllMarkers()
                       
                        statusNotification.color = "#9c27b0"
                        if (statusNotification.children.length > 0) {
                            statusNotification.children[0].text = "📐 Click map to add polygon corners"
                        }
                        mainWindow.statusNotification.opacity = 1
                        statusNotificationTimer.restart()
                    } else {
                        waypointsMap.polygonSurveyMode = false
                    }
                }
            }
           
            Rectangle {
                width: parent.width - 32
                height: 1
                color: "#e0e0e0"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
       
        // 2. Edit Polygon Button (Pattern Selector)
        Rectangle {
            width: parent.width
            height: 50
            color: editPolygonMouseArea.containsMouse ? "#f5f5f5" : "white"
           
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                spacing: 10
               
                Text {
                    text: "Edit Polygon"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    color: "#333333"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            MouseArea {
                id: editPolygonMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
               
                onClicked: {
                    // Open pattern selector popup
                    patternSelectorPopup.open()
                }
            }
           
            Rectangle {
                width: parent.width - 32
                height: 1
                color: "#e0e0e0"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
       
        // 3. Survey Settings Button
        Rectangle {
            width: parent.width
            height: 50
            color: surveySettingsMouseArea.containsMouse ? "#f5f5f5" : "white"
            opacity: polygonMenuPopup.cornerCount >= 3 ? 1.0 : 0.5
           
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                spacing: 10
               
                Text {
                    text: "Survey Settings"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    color: "#333333"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            MouseArea {
                id: surveySettingsMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: polygonMenuPopup.cornerCount >= 3 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: polygonMenuPopup.cornerCount >= 3
               
                onClicked: {
                    if (polygonMenuPopup.cornerCount >= 3) {
                        polygonMenuPopup.close()
                        surveySettingsPopup.open()
                    }
                }
            }
           
            Rectangle {
                width: parent.width - 32
                height: 1
                color: "#e0e0e0"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
       
        // 4. Send to Drone Button
        Rectangle {
            width: parent.width
            height: 50
            color: sendDroneMouseArea.containsMouse ? "#f5f5f5" : "white"
            opacity: waypointsMap.markers.length > 0 ? 1.0 : 0.5
           
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                spacing: 10
               
                Text {
                    text: "✈️"
                    font.pixelSize: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
               
                Text {
                    text: "Send to Drone"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    color: "#333333"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            MouseArea {
                id: sendDroneMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: waypointsMap.markers.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: waypointsMap.markers.length > 0
               
                onClicked: {
                    var validation = validateSurveyMission()
                   
                    if (!validation.valid) {
                        uploadErrorPopup.errorMessage = validation.error
                        uploadErrorPopup.open()
                        return
                    }
                   
                    polygonMenuPopup.close()
                    sendSurveyMission()
                }
            }
           
            Rectangle {
                width: parent.width - 32
                height: 1
                color: "#e0e0e0"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // 5. Start Mission Button (NEW)
        Rectangle {
            width: parent.width
            height: 50
            color: startMissionMouseArea.containsMouse ? "#e8f5e9" : "white"
            // Enabled if markers exist
            opacity: waypointsMap.markers.length > 0 ? 1.0 : 0.5
           
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                spacing: 10
               
                Text {
                    text: "🚀"
                    font.pixelSize: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
               
                Text {
                    text: "Start Mission"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    font.bold: true
                    color: "#2e7d32" // Green text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            MouseArea {
                id: startMissionMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: waypointsMap.markers.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: waypointsMap.markers.length > 0
               
                onClicked: {
                    console.log("🚀 Start Mission clicked")
                    if (typeof droneModel === "undefined" || !droneModel.isConnected) {
                         uploadErrorPopup.errorMessage = "Drone not connected"
                         uploadErrorPopup.open()
                         return
                    }

                    // ARM if not armed
                    if (!droneModel.telemetry.armed) {
                        console.log("🛡️ Arming drone before mission start...")
                        droneCommander.arm()
                        // Wait for arming to complete before takeoff
                        missionStartTimer.restart() 
                    } else {
                        console.log("✅ Already armed. Starting takeoff sequence...")
                        // Already armed, start takeoff immediately
                        missionStartTimer.restart()
                    }
                    
                    polygonMenuPopup.close()
                }
            }
           
            Timer {
                id: missionStartTimer
                interval: 3000 // 3 seconds delay to allow motors to spin up after arming
                repeat: false
                onTriggered: {
                    console.log("⌛ Arming complete. Setting GUIDED mode and taking off...")
                    // Step 1: Set to GUIDED mode
                    droneCommander.setMode("GUIDED")
                    
                    // Step 2: Wait a moment for mode change, then takeoff
                    missionTakeoffTimer.restart()
                }
            }
            
            Timer {
                id: missionTakeoffTimer
                interval: 2000 // 2 seconds for mode change
                repeat: false
                onTriggered: {
                    console.log("🚁 Initiating takeoff to 10m...")
                    // Takeoff to 10m altitude
                    droneCommander.takeoff(10)
                    
                    // Step 3: Wait for takeoff to complete, then switch to AUTO
                    missionAutoSwitchTimer.restart()
                }
            }
            
            Timer {
                id: missionAutoSwitchTimer
                interval: 8000 // 8 seconds for takeoff to complete
                repeat: false
                onTriggered: {
                    console.log("✈️ Takeoff complete. Switching to AUTO mode for waypoint navigation...")
                    droneCommander.setMode("AUTO")
                }
            }

            Rectangle {
                width: parent.width - 32
                height: 1
                color: "#e0e0e0"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
       
        // 5. Clear Polygon Button
        Rectangle {
            width: parent.width
            height: 50
            color: clearPolygonMouseArea.containsMouse ? "#f5f5f5" : "white"
            opacity: polygonMenuPopup.cornerCount > 0 ? 1.0 : 0.5
           
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                spacing: 10
               
                Text {
                    text: "Clear Polygon"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    color: "#333333"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
           
            MouseArea {
                id: clearPolygonMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: polygonMenuPopup.cornerCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: polygonMenuPopup.cornerCount > 0
               
                onClicked: {
                    waypointsMap.polygonCorners = []
                    waypointsMap.polygonSurveyMode = false
                    waypointsMap.clearAllMarkers()
                   
                    statusNotification.color = theme.success
                    statusNotification.children[0].text = "✅ Polygon cleared"
                    mainWindow.statusNotification.opacity = 1
                    statusNotificationTimer.restart()
                   
                    polygonMenuPopup.close()
                }
            }
        }
    }
}

// Pattern Selector Popup (replaces the inline pattern buttons)
Popup {
    id: patternSelectorPopup
    width: 360
    height: 340
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: parent

    background: Rectangle {
        color: "white"
        border.color: "#e0e0e0"
        border.width: 1
        radius: 12
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 4
            radius: 12
            samples: 25
            color: "#40000000"
        }
    }

    contentItem: Item {
        width: patternSelectorPopup.width
        height: patternSelectorPopup.height

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                text: "Select Survey Pattern"
                font.pixelSize: 16
                font.bold: true
                font.family: "Consolas"
                color: "#333333"
            }

            // Row 1: Horizontal + Vertical
            Row {
                spacing: 12
                width: parent.width

                Button {
                    width: (parent.width - 12) / 2
                    height: 60
                    background: Rectangle {
                        color: waypointsMap.surveyPattern === "horizontal" ? "#9c27b0" :
                               (parent.hovered ? "#f3e5f5" : "#fafafa")
                        radius: 8
                        border.color: waypointsMap.surveyPattern === "horizontal" ? "#9c27b0" : "#e0e0e0"
                        border.width: waypointsMap.surveyPattern === "horizontal" ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Column {
                        spacing: 4
                        anchors.centerIn: parent
                        Text {
                            text: "═"
                            font.pixelSize: 24
                            font.bold: true
                            color: waypointsMap.surveyPattern === "horizontal" ? "white" : "#9c27b0"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Horizontal"
                            font.pixelSize: 11
                            font.family: "Consolas"
                            color: waypointsMap.surveyPattern === "horizontal" ? "white" : "#666666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    onClicked: {
                        waypointsMap.surveyPattern = "horizontal"
                        console.log("📐 Pattern set to: horizontal")
                        patternSelectorPopup.close()
                    }
                }

                Button {
                    width: (parent.width - 12) / 2
                    height: 60
                    background: Rectangle {
                        color: waypointsMap.surveyPattern === "vertical" ? "#9c27b0" :
                               (parent.hovered ? "#f3e5f5" : "#fafafa")
                        radius: 8
                        border.color: waypointsMap.surveyPattern === "vertical" ? "#9c27b0" : "#e0e0e0"
                        border.width: waypointsMap.surveyPattern === "vertical" ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Column {
                        spacing: 4
                        anchors.centerIn: parent
                        Text {
                            text: "║"
                            font.pixelSize: 24
                            font.bold: true
                            color: waypointsMap.surveyPattern === "vertical" ? "white" : "#9c27b0"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Vertical"
                            font.pixelSize: 11
                            font.family: "Consolas"
                            color: waypointsMap.surveyPattern === "vertical" ? "white" : "#666666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    onClicked: {
                        waypointsMap.surveyPattern = "vertical"
                        console.log("📐 Pattern set to: vertical")
                        patternSelectorPopup.close()
                    }
                }
            }

            // Row 2: Crosshatch + Rectangle
            Row {
                spacing: 12
                width: parent.width

                Button {
                    width: (parent.width - 12) / 2
                    height: 60
                    background: Rectangle {
                        color: waypointsMap.surveyPattern === "crosshatch" ? "#9c27b0" :
                               (parent.hovered ? "#f3e5f5" : "#fafafa")
                        radius: 8
                        border.color: waypointsMap.surveyPattern === "crosshatch" ? "#9c27b0" : "#e0e0e0"
                        border.width: waypointsMap.surveyPattern === "crosshatch" ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Column {
                        spacing: 4
                        anchors.centerIn: parent
                        Text {
                            text: "╬"
                            font.pixelSize: 24
                            font.bold: true
                            color: waypointsMap.surveyPattern === "crosshatch" ? "white" : "#9c27b0"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Crosshatch"
                            font.pixelSize: 11
                            font.family: "Consolas"
                            color: waypointsMap.surveyPattern === "crosshatch" ? "white" : "#666666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    onClicked: {
                        waypointsMap.surveyPattern = "crosshatch"
                        console.log("📐 Pattern set to: crosshatch")
                        patternSelectorPopup.close()
                    }
                }

                Button {
                    width: (parent.width - 12) / 2
                    height: 60
                    background: Rectangle {
                        color: waypointsMap.surveyPattern === "rectangle" ? "#9c27b0" :
                               (parent.hovered ? "#f3e5f5" : "#fafafa")
                        radius: 8
                        border.color: waypointsMap.surveyPattern === "rectangle" ? "#9c27b0" : "#e0e0e0"
                        border.width: waypointsMap.surveyPattern === "rectangle" ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    contentItem: Column {
                        spacing: 4
                        anchors.centerIn: parent
                        Text {
                            text: "▭"
                            font.pixelSize: 24
                            font.bold: true
                            color: waypointsMap.surveyPattern === "rectangle" ? "white" : "#9c27b0"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Rectangle"
                            font.pixelSize: 11
                            font.family: "Consolas"
                            color: waypointsMap.surveyPattern === "rectangle" ? "white" : "#666666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    onClicked: {
                        waypointsMap.surveyPattern = "rectangle"
                        console.log("📐 Pattern set to: rectangle")
                        patternSelectorPopup.close()
                    }
                }
            }

            // Row 3: Circle (full width)
            Button {
                width: parent.width
                height: 60
                background: Rectangle {
                    color: waypointsMap.surveyPattern === "circle" ? "#9c27b0" :
                           (parent.hovered ? "#f3e5f5" : "#fafafa")
                    radius: 8
                    border.color: waypointsMap.surveyPattern === "circle" ? "#9c27b0" : "#e0e0e0"
                    border.width: waypointsMap.surveyPattern === "circle" ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                contentItem: Row {
                    spacing: 10
                    anchors.centerIn: parent
                    Text {
                        text: "○"
                        font.pixelSize: 24
                        font.bold: true
                        color: waypointsMap.surveyPattern === "circle" ? "white" : "#9c27b0"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Circle"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        color: waypointsMap.surveyPattern === "circle" ? "white" : "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                onClicked: {
                    waypointsMap.surveyPattern = "circle"
                    console.log("📐 Pattern set to: circle")
                    patternSelectorPopup.close()
                }
            }
        }
    }
}

   
// Upload Success Popup
Popup {
    id: uploadSuccessPopup
    width: 520
    height: 600
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    property int waypointCount: 0
    property var waypointsData: []
    
    background: Rectangle {
        color: theme.cardBackground
        border.color: theme.success
        border.width: 2
        radius: theme.borderRadius
        
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            color: "#00000010"
            radius: parent.radius
            z: -1
        }
    }
    
    // Function to calculate distance between two coordinates
    function calculateDistance(lat1, lon1, lat2, lon2) {
        var R = 6371000; // Earth radius in meters
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        return R * c; // Distance in meters
    }
    
    // Function to populate waypoints data
    function populateWaypoints(waypoints) {
        waypointsData = waypoints;
        detailedWaypointListModel.clear();
        
        for (var i = 0; i < waypoints.length; i++) {
            var wpData = {
                lat: waypoints[i].lat || waypoints[i].x || 0,
                lng: waypoints[i].lng || waypoints[i].y || 0,
                altitude: waypoints[i].altitude || waypoints[i].z || 0,
                speed: waypoints[i].speed || 0,
                commandType: getCommandTypeName(waypoints[i].command || waypoints[i].commandType),
                placeName: undefined,
                distanceToNext: ""
            };
            
            // Calculate distance to next waypoint
            if (i < waypoints.length - 1) {
                var nextWP = waypoints[i + 1];
                var nextLat = nextWP.lat || nextWP.x || 0;
                var nextLng = nextWP.lng || nextWP.y || 0;
                var dist = calculateDistance(wpData.lat, wpData.lng, nextLat, nextLng);
                wpData.distanceToNext = (dist / 1000).toFixed(2) + " km (" + dist.toFixed(0) + " m)";
            }
            
            detailedWaypointListModel.append(wpData);
        }
        
        waypointCount = waypoints.length;
    }
    
    // Helper function to get human-readable command type
    function getCommandTypeName(cmd) {
        if (typeof cmd === 'string') return cmd;
        
        switch(cmd) {
            case 16: return "Waypoint";
            case 22: return "Takeoff";
            case 21: return "Land";
            case 20: return "Return to Launch";
            case 17: return "Loiter Unlimited";
            case 18: return "Loiter Turns";
            case 19: return "Loiter Time";
            default: return "Waypoint";
        }
    }
    
    onOpened: {
        // Fetch place names for all waypoints
        for (var i = 0; i < waypointsData.length; i++) {
            fetchPlaceName(i, waypointsData[i].lat, waypointsData[i].lng);
        }
    }
    
    function fetchPlaceName(index, lat, lng) {
        var url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=" + 
                  lat + "," + lng + 
                  "&key=AIzaSyDnBjIddcNnhfndEEJHi8puawYx3cPspWI";
        
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    if (response.results && response.results.length > 0) {
                        waypointsData[index].placeName = response.results[0].formatted_address;
                        detailedWaypointListModel.set(index, waypointsData[index]);
                    }
                } catch (e) {
                    console.log("Error parsing geocoding response:", e);
                }
            }
        };
        xhr.send();
    }
    
    contentItem: Column {
        spacing: 15
        padding: 20
        
        // Success Icon
        Rectangle {
            width: 70
            height: 70
            radius: 35
            color: "#28a74520"
            anchors.horizontalCenter: parent.horizontalCenter
            
            Text {
                text: "✓"
                font.pixelSize: 42
                font.bold: true
                color: theme.success
                anchors.centerIn: parent
            }
        }
        
        // Success Message
        Text {
            text: "Mission Uploaded Successfully!"
            font.pixelSize: 18
            font.bold: true
            font.family: "Consolas"
            color: theme.textPrimary
            anchors.horizontalCenter: parent.horizontalCenter
        }
        
        // Summary
        Text {
            text: uploadSuccessPopup.waypointCount + " waypoint(s) uploaded to drone"
            font.pixelSize: 13
            font.family: "Consolas"
            color: theme.textSecondary
            anchors.horizontalCenter: parent.horizontalCenter
        }
        
        // Waypoints List Header
        Rectangle {
            width: parent.width - 40
            height: 35
            color: "#f8f9fa"
            radius: 6
            border.color: theme.border
            border.width: 1
            
            Text {
                text: "📍 Waypoint Details"
                font.pixelSize: 14
                font.bold: true
                font.family: "Consolas"
                color: theme.textPrimary
                anchors.centerIn: parent
            }
        }
        
        // Scrollable Waypoints List
        Rectangle {
            width: parent.width - 40
            height: 320
            color: "#ffffff"
            radius: 6
            border.color: theme.border
            border.width: 1
            clip: true
            
            ListView {
                id: detailedWaypointListView
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                clip: true
                
                model: ListModel {
                    id: detailedWaypointListModel
                }
                
                delegate: Rectangle {
                    width: detailedWaypointListView.width - 10
                    height: waypointDetailColumn.height + 16
                    color: index % 2 === 0 ? "#f8f9fa" : "#ffffff"
                    radius: 6
                    border.color: "#e9ecef"
                    border.width: 1
                    
                    Column {
                        id: waypointDetailColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 10
                        spacing: 4
                        
                        // Waypoint Header
                        Row {
                            spacing: 8
                            width: parent.width
                            
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                color: theme.accent
                                
                                Text {
                                    text: (index + 1).toString()
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "Consolas"
                                    color: "white"
                                    anchors.centerIn: parent
                                }
                            }
                            
                            Text {
                                text: model.commandType + " " + (index + 1)
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "Consolas"
                                color: theme.textPrimary
                            }
                        }
                        
                        // Coordinates
                        Text {
                            text: "📍 " + model.lat.toFixed(6) + "°, " + model.lng.toFixed(6) + "°"
                            font.pixelSize: 10
                            font.family: "Consolas"
                            color: theme.textSecondary
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                        
                        // Place Name
                        Text {
                            text: model.placeName ? "📌 " + model.placeName : "📌 Fetching location..."
                            font.pixelSize: 10
                            font.family: "Consolas"
                            color: "#007bff"
                            wrapMode: Text.WordWrap
                            width: parent.width
                            visible: model.placeName !== undefined
                        }
                        
                        // Altitude & Speed
                        Row {
                            spacing: 15
                            width: parent.width
                            
                            Text {
                                text: "⬆️ " + model.altitude.toFixed(1) + "m"
                                font.pixelSize: 10
                                font.family: "Consolas"
                                color: theme.textSecondary
                            }
                            
                            Text {
                                text: "🚀 " + model.speed.toFixed(1) + "m/s"
                                font.pixelSize: 10
                                font.family: "Consolas"
                                color: theme.textSecondary
                            }
                        }
                        
                        // Distance to next waypoint
                        Text {
                            text: model.distanceToNext ? 
                                  "➡️ Distance to next: " + model.distanceToNext : ""
                            font.pixelSize: 10
                            font.family: "Consolas"
                            color: "#28a745"
                            font.bold: true
                            visible: model.distanceToNext !== undefined && model.distanceToNext !== ""
                        }
                    }
                }
                
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 8
                    
                    contentItem: Rectangle {
                        radius: 4
                        color: parent.pressed ? "#adb5bd" : "#dee2e6"
                    }
                }
            }
        }
        
        // Close Button
        Button {
            width: parent.width - 40
            height: 45
            anchors.horizontalCenter: parent.horizontalCenter
            
            background: Rectangle {
                color: parent.pressed ? "#1e7e34" : (parent.hovered ? "#218838" : theme.success)
                radius: 6
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: "OK"
                color: "white"
                font.pixelSize: 16
                font.family: "Consolas"
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: uploadSuccessPopup.close()
        }
    }
}
Popup {
    id: missionUploadSuccessPopup
    width: 520
    height: 600
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
   
    property int waypointCount: 0
    property var waypointsData: []
   
    background: Rectangle {
        color: theme.cardBackground
        border.color: theme.success
        border.width: 2
        radius: theme.borderRadius
       
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            color: "#00000010"
            radius: parent.radius
            z: -1
        }
    }
   
    // Function to calculate distance between two coordinates
function calculateDistance(lat1, lon1, lat2, lon2) {
    var R = 6371000; // Earth radius in meters
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLon = (lon2 - lon1) * Math.PI / 180;
    var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c; // Distance in meters
}
    // Function to populate waypoints and calculate distances
    function populateWaypoints(waypoints) {
        waypointsData = waypoints;
        uploadWaypointListModel.clear();
       
        for (var i = 0; i < waypoints.length; i++) {
            var wpData = {
                lat: waypoints[i].lat,
                lng: waypoints[i].lng,
                altitude: waypoints[i].altitude || 0,
                speed: waypoints[i].speed || 0,
                commandType: waypoints[i].commandType || "waypoint",
                placeName: undefined,
                distanceToNext: ""
            };
           
            // Calculate distance to next waypoint
            if (i < waypoints.length - 1) {
                var dist = calculateDistance(
                    waypoints[i].lat,
                    waypoints[i].lng,
                    waypoints[i + 1].lat,
                    waypoints[i + 1].lng
                );
                wpData.distanceToNext = (dist / 1000).toFixed(2) + " km (" + dist.toFixed(0) + " m)";
            }
           
            uploadWaypointListModel.append(wpData);
        }
       
        waypointCount = waypoints.length;
    }
   
    onOpened: {
        // Fetch place names for all waypoints
        for (var i = 0; i < waypointsData.length; i++) {
            fetchPlaceName(i, waypointsData[i].lat, waypointsData[i].lng);
        }
    }
   
    function fetchPlaceName(index, lat, lng) {
        var url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=" +
                  lat + "," + lng +
                  "&key=AIzaSyDnBjIddcNnhfndEEJHi8puawYx3cPspWI";
       
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    if (response.results && response.results.length > 0) {
                        waypointsData[index].placeName = response.results[0].formatted_address;
                        uploadWaypointListModel.set(index, waypointsData[index]);
                    }
                } catch (e) {
                    console.log("Error parsing geocoding response:", e);
                }
            }
        };
        xhr.send();
    }
   
    contentItem: Column {
        spacing: 15
        padding: 20
       
        // Success Icon
        Rectangle {
            width: 70
            height: 80
            radius: 35
            color: "#28a74520"
            anchors.horizontalCenter: parent.horizontalCenter
           
            Text {
                text: "✓"
                font.pixelSize: 42
                font.bold: true
                color: theme.success
                anchors.centerIn: parent
            }
        }
       
        // Success Message
        Text {
            text: "Mission Uploaded Successfully!"
            font.pixelSize: 18
            font.bold: true
            font.family: "Consolas"
            color: theme.textPrimary
            anchors.horizontalCenter: parent.horizontalCenter
        }
       
        // Summary
        Text {
            text: missionUploadSuccessPopup.waypointCount + " waypoint(s) uploaded to drone"
            font.pixelSize: 13
            font.family: "Consolas"
            color: theme.textSecondary
            anchors.horizontalCenter: parent.horizontalCenter
        }
       
        // Waypoints List Header
        Rectangle {
            width: parent.width - 40
            height: 35
            color: "#f8f9fa"
            radius: 6
            border.color: theme.border
            border.width: 1
           
            Text {
                text: "📍 Waypoint Details"
                font.pixelSize: 14
                font.bold: true
                font.family: "Consolas"
                color: theme.textPrimary
                anchors.centerIn: parent
            }
        }
       
        // Scrollable Waypoints List
        Rectangle {
            width: parent.width - 40
            height: 320
            color: "#ffffff"
            radius: 6
            border.color: theme.border
            border.width: 1
            clip: true
           
            ListView {
                id: uploadWaypointListView
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                clip: true
               
                model: ListModel {
                    id: uploadWaypointListModel
                }
               
                delegate: Rectangle {
                    width: uploadWaypointListView.width - 10
                    height: uploadWaypointColumn.height + 16
                    color: index % 2 === 0 ? "#f8f9fa" : "#ffffff"
                    radius: 6
                    border.color: "#e9ecef"
                    border.width: 1
                   
                    Column {
                        id: uploadWaypointColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 10
                        spacing: 4
                       
                        // Waypoint Header
                        Row {
                            spacing: 8
                            width: parent.width
                           
                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                color: theme.accent
                               
                                Text {
                                    text: (index + 1).toString()
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "Consolas"
                                    color: "white"
                                    anchors.centerIn: parent
                                }
                            }
                           
                            Text {
                                text: model.commandType === "waypoint" ? "Waypoint " + (index + 1) :
                                      model.commandType === "takeoff" ? "Takeoff Point" :
                                      model.commandType === "land" ? "Landing Point" :
                                      model.commandType === "return" ? "Return Point" :
                                      "Waypoint " + (index + 1)
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "Consolas"
                                color: theme.textPrimary
                            }
                        }
                       
                        // Coordinates
                        Text {
                            text: "📍 " + model.lat.toFixed(6) + "°, " + model.lng.toFixed(6) + "°"
                            font.pixelSize: 10
                            font.family: "Consolas"
                            color: theme.textSecondary
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                       
                        // Place Name
                        Text {
                            text: model.placeName ? "📌 " + model.placeName : "📌 Fetching location..."
                            font.pixelSize: 10
                            font.family: "Consolas"
                            color: "#007bff"
                            wrapMode: Text.WordWrap
                            width: parent.width
                            visible: model.placeName !== undefined
                        }
                       
                        // Altitude & Speed
                        Row {
                            spacing: 15
                            width: parent.width
                           
                            Text {
                                text: "⬆️ " + model.altitude.toFixed(1) + "m"
                                font.pixelSize: 10
                                font.family: "Consolas"
                                color: theme.textSecondary
                            }
                           
                            Text {
                                text: "🚀 " + model.speed.toFixed(1) + "m/s"
                                font.pixelSize: 10
                                font.family: "Consolas"
                                color: theme.textSecondary
                            }
                        }
                       
                        // Distance to next waypoint
                        Text {
                            text: model.distanceToNext ?
                                  "➡️ Distance to next: " + model.distanceToNext : ""
                            font.pixelSize: 10
                            font.family: "Consolas"
                            color: "#28a745"
                            font.bold: true
                            visible: model.distanceToNext !== undefined && model.distanceToNext !== ""
                        }
                    }
                }
               
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 8
                   
                    contentItem: Rectangle {
                        radius: 4
                        color: parent.pressed ? "#adb5bd" : "#dee2e6"
                    }
                }
            }
        }
       
        // Close Button
        Button {
            width: parent.width - 40
            height: 45
            anchors.horizontalCenter: parent.horizontalCenter
           
            background: Rectangle {
                color: parent.pressed ? "#1e7e34" : (parent.hovered ? "#218838" : theme.success)
                radius: 6
               
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
           
            contentItem: Text {
                text: "OK"
                color: "white"
                font.pixelSize: 16
                font.family: "Consolas"
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
           
            onClicked: missionUploadSuccessPopup.close()
        }
    }
}
function addMarker(lat, lon) {
    waypointsMap.addMarkerJS(lat, lon, 10, 5, "waypoint", 0);
    lastClickedCoordinate = QtPositioning.coordinate(lat, lon);
    // Trigger dashboard update after marker is added
    Qt.callLater(function() {
        onWaypointAdded();
    });
}

function deleteMarker(index) {
    waypointsMap.deleteMarkerJS(index);
    if (lastClickedCoordinate) {
        lastClickedCoordinate = null;
    }
    // Trigger dashboard update after marker is deleted
    Qt.callLater(function() {
        onWaypointDeleted();
    });
}
    function fetchDroneLocation() {
        // This is now handled by the Timer in WebEngineView
    }

function getWeather(lat, lon) {
    console.log("Getting weather for coordinates:", lat, lon);
    weatherDashboard.setLocation(lat, lon);
    weatherDashboard.show();
}

    function showMarkerPopupForIndex(index) {
        var markers = waypointsMap.getAllMarkers();
        if (index >= 0 && index < markers.length) {
            var data = markers[index];
            markerPopup.markerIndex = index;
            markerPopup.altitude = data.altitude || 10;
            markerPopup.speed = data.speed || 1.5;
            markerPopup.open();
        } else {
            console.log("Invalid marker index:", index);
        }
    }
// Add these functions at the bottom of your ApplicationWindow
function updateWaypointDashboard() {
    console.log("=== DEBUG: updateWaypointDashboard called ===");
    console.log("Dashboard visible:", waypointDashboard.visible);
    console.log("Dashboard expanded:", waypointDashboard.expanded);
   
    if (waypointsMap && typeof waypointsMap.getAllMarkersJS !== 'undefined') {
        console.log("Calling getAllMarkersJS...");
        waypointsMap.getAllMarkersJS(function(result) {
            console.log("getAllMarkersJS result type:", typeof result);
            console.log("getAllMarkersJS result:", result);
           
            if (result && typeof result === 'string') {
                try {
                    var markersData = JSON.parse(result);
                    console.log("Parsed markers data:", markersData.length, "waypoints");
                   
                    // Force the dashboard to completely refresh by hiding and showing
                    waypointDashboard.updateWaypoints(markersData);
                   
                    // Force a visual refresh by temporarily changing a property
                    var currentExpanded = waypointDashboard.expanded;
                    waypointDashboard.expanded = false;
                    Qt.callLater(function() {
                        waypointDashboard.expanded = currentExpanded;
                    });
                   
                    console.log("Dashboard waypoints length after update:", waypointDashboard.waypoints.length);

                    // ---- SYNCHRONIZE WITH MAIN MAP -----
                    console.log("SYNC DEBUG: mainGcsWindow type:", typeof mainGcsWindow);
                    if (typeof mainGcsWindow !== 'undefined' && mainGcsWindow && mainGcsWindow.mapViewInstance) {
                        console.log("SYNC DEBUG: syncing to mainGcsWindow.mapViewInstance...");
                        mainGcsWindow.mapViewInstance.setMarkersOnly(markersData);
                    } else {
                        console.log("SYNC DEBUG: Failed to find main window map instance!");
                    }
                    // ------------------------------------
                } catch (e) {
                    console.log("Error parsing markers data:", e);
                    waypointDashboard.updateWaypoints([]);
                }
            } else {
                console.log("Invalid result from getAllMarkersJS - not a string");
                waypointDashboard.updateWaypoints([]);
            }
        });
    } else {
        console.log("waypointsMap or getAllMarkersJS not available");
    }
}
// Add this test function to check if getAllMarkersJS works
    function testGetAllMarkers() {
        console.log("Testing getAllMarkers...");
        var markers = waypointsMap.getAllMarkers();
        console.log("Markers count:", markers.length);
        console.log("Markers JSON:", JSON.stringify(markers));
    }
function onWaypointAdded() {
    console.log("Waypoint added, dashboard visible:", waypointDashboard.visible);
    if (waypointDashboard.visible) {
        // Add a small delay to ensure the JavaScript markers array is updated
        var timer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 300; repeat: false; }', mainWindow);
        timer.triggered.connect(function() {
            updateWaypointDashboard();
            timer.destroy();
        });
        timer.start();
    }
}


function onWaypointDeleted() {
    console.log("Waypoint deleted, dashboard visible:", waypointDashboard.visible);
    if (waypointDashboard.visible) {
        // Add a small delay to ensure the JavaScript markers array is updated
        var timer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 300; repeat: false; }', mainWindow);
        timer.triggered.connect(function() {
            updateWaypointDashboard();
            timer.destroy();
        });
        timer.start();
    }
}
function sendMarkers() {
    console.log("📤 ========== SENDING MISSION ==========");
    
    var markers = waypointsMap.getAllMarkers();
    
    if (!markers || markers.length === 0) {
        console.log("❌ No waypoints to send");
        return;
    }
    
    console.log("✅ Found", markers.length, "waypoints");
    
    var waypoints = [];
    var hasRTLCommand = false;
    var rtlWaypointIndex = -1;

    // ── Inject DO_CHANGE_SPEED as item 0 so ArduPilot honours nav speed ──
    // MAVLink cmd 178: param1=speed_type(0=airspeed,1=groundspeed),
    //                  param2=speed_m/s, param3=throttle(-1=ignore)
    // Default waypoint navigation speed = 1.5 m/s
    var navSpeed = (waypointsMap.surveySpeed && waypointsMap.surveySpeed > 0)
                   ? waypointsMap.surveySpeed : 1.5;
    waypoints.push({
        "id": 0,
        "command": "DO_CHANGE_SPEED",
        "latitude": 0,
        "longitude": 0,
        "altitude": 0,
        "speed": navSpeed,      // Python reads this to fill param2
        "hold_time": 0
    });
    console.log("⚡ Injected DO_CHANGE_SPEED:", navSpeed, "m/s at WP0");
    // ─────────────────────────────────────────────────────────────────────

    // ✅ STEP 1: Process all markers
    for (var i = 0; i < markers.length; i++) {
        var marker = markers[i];
        var commandType = marker.commandType || "waypoint";
        
        // ✅ Check if this waypoint is marked as RTL
        if (commandType.toLowerCase() === "return" || commandType.toLowerCase() === "rtl") {
            hasRTLCommand = true;
            rtlWaypointIndex = i;
            // ✅ CHANGE: Send as regular WAYPOINT, not RETURN
            commandType = "waypoint";
        }
        
        // Map to uppercase command
        var commandString = "WAYPOINT";
        switch(commandType.toLowerCase()) {
            case "takeoff":
                commandString = "TAKEOFF";
                break;
            case "land":
                commandString = "LAND";
                break;
            case "loiter":
                commandString = "LOITER";
                break;
            case "circle":
                commandString = "CIRCLE";
                break;
            default:
                commandString = "WAYPOINT";
                break;
        }
        
        console.log("📍 WP" + (i+1) + ":", commandString, "at", 
                   marker.lat.toFixed(6) + ",", marker.lng.toFixed(6), 
                   "| Alt=" + (marker.altitude || 10) + "m");
        
        waypoints.push({
            "id": i + 1,
            "command": commandString,
            "latitude": marker.lat,
            "longitude": marker.lng,
            "altitude": marker.altitude || 10,
            "hold_time": 0
        });
    }
    
    // ✅ STEP 2: If user marked a waypoint as RTL, add RTL as separate command
    if (hasRTLCommand && rtlWaypointIndex >= 0) {
        var rtlMarker = markers[rtlWaypointIndex];
        
        waypoints.push({
            "id": waypoints.length + 1,
            "command": "RETURN",
            "latitude": rtlMarker.lat,  // RTL location (or use home)
            "longitude": rtlMarker.lng,
            "altitude": 0,  // RTL altitude is usually 0
            "hold_time": 0
        });
        
        console.log("📍 WP" + (waypoints.length) + ": RETURN (after reaching waypoint " + (rtlWaypointIndex + 1) + ")");
    }
    
    // ✅ STEP 3: Create mission package
    var missionName = "Mission " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
    
    var missionPackage = {
        "mission_name": missionName,
        "frame": "GLOBAL_RELATIVE_ALT",
        "waypoints": waypoints,
        "total_waypoints": waypoints.length
    };
    
    console.log("📦 Mission Package:");
    console.log("   Total WPs:", waypoints.length, "(including RTL command)");
    console.log("   JSON:", JSON.stringify(missionPackage, null, 2));
    
    // Send to drone...
    var uploadStarted = droneCommander.uploadMission(waypoints);
    
    if (uploadStarted === false) {
        uploadErrorPopup.errorMessage = "Mission upload failed.";
        uploadErrorPopup.open();
    } else {
        if (typeof droneModel !== 'undefined' && droneModel) {
            droneModel.setMissionPath(waypoints);
        }
        
        waypointsMap.setUploadedMissionPath(waypoints);
        
        statusNotification.color = theme.success;
        statusNotificationLabel.text = "📡 Uploading " + waypoints.length + " waypoints...";
        statusNotification.opacity = 1;
        statusNotificationTimer.restart();
        
        updateMissionStatistics();
    }
}

function sendSurveyMission() {
    console.log("🛰️ ========== SENDING SURVEY MISSION ==========");
    
    var markersData = waypointsMap.getAllMarkers();
    
    if (!markersData || markersData.length === 0) {
        console.log("❌ No survey waypoints");
        uploadErrorPopup.errorMessage = "No survey waypoints.\nGenerate a survey grid first.";
        uploadErrorPopup.open();
        return;
    }
    
    try {
        var waypoints = [];
        
        for (var i = 0; i < markersData.length; i++) {
            var marker = markersData[i];
            
            var waypoint = {
                "id": i + 1,
                "command": "WAYPOINT",
                "latitude": marker.lat,
                "longitude": marker.lng,
                "altitude": marker.altitude || waypointsMap.surveyAltitude || 50.0,
                "hold_time": 0
            };
            
            waypoints.push(waypoint);
        }
        
        console.log("✅ Prepared " + waypoints.length + " survey waypoints");
        
        if (typeof droneCommander === 'undefined') {
            uploadErrorPopup.errorMessage = "Drone commander not initialized.";
            uploadErrorPopup.open();
            return;
        }
        
        var uploadStarted = droneCommander.uploadMission(waypoints);
        
        if (uploadStarted === false) {
            uploadErrorPopup.errorMessage = "Survey mission upload failed.";
            uploadErrorPopup.open();
        } else {
            if (typeof droneModel !== 'undefined' && droneModel) {
                droneModel.setMissionPath(waypoints);
            }
            
            waypointsMap.setUploadedMissionPath(waypoints);
            
            statusNotification.color = "#9c27b0";
            statusNotificationLabel.text = "📡 Uploading " + waypoints.length + " survey waypoints...";
            statusNotification.opacity = 1;
            statusNotificationTimer.restart();
            
            updateMissionStatistics();
        }
        
    } catch (e) {
        console.log("❌ Error:", e);
        uploadErrorPopup.errorMessage = "Error preparing survey mission.";
        uploadErrorPopup.open();
    }
}
function validateSurveyMission() {
    console.log("🔍 Validating survey mission...");
    
    // Check: Do we have waypoints?
    var markersData = waypointsMap.getAllMarkers();
    
    if (!markersData || markersData.length === 0) {
        console.log("❌ No waypoints found");
        return {
            valid: false,
            error: "No waypoints on the map!\n\n✅ How to fix:\n1. Click 'Draw Polygon'\n2. Click map 3+ times\n3. Click 'Survey Settings'\n4. Click 'Apply & Regenerate'\n5. Then try again"
        };
    }
    
    console.log("✅ Ready to send - " + markersData.length + " waypoints");
    return {
        valid: true
    };
}
function showSurveyMissionSummary() {
    var validation = validateSurveyMission();
   
    if (!validation.valid) {
        uploadErrorPopup.errorMessage = validation.error;
        uploadErrorPopup.open();
        return;
    }
   
    var markersData = waypointsMap.getAllMarkers();
   
    // Calculate total mission distance
    var totalDistance = 0;
    for (var i = 0; i < markersData.length - 1; i++) {
        totalDistance += calculateDistance(
            markersData[i].lat, markersData[i].lng,
            markersData[i + 1].lat, markersData[i + 1].lng
        );
    }
   
    // Calculate estimated flight time
    var estimatedTime = totalDistance / waypointsMap.surveySpeed; // seconds
    var minutes = Math.floor(estimatedTime / 60);
    var seconds = Math.floor(estimatedTime % 60);
   
    // Create confirmation popup
    var confirmPopup = Qt.createQmlObject(`
        import QtQuick 2.15
        import QtQuick.Controls 2.15
       
        Popup {
            width: 450
            height: 400
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            modal: true
            focus: true
           
            background: Rectangle {
                color: "#ffffff"
                border.color: "#9c27b0"
                border.width: 2
                radius: 8
            }
           
            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 15
               
                Text {
                    text: "📐 Survey Mission Summary"
                    font.pixelSize: 18
                    font.bold: true
                    color: "#9c27b0"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
               
                Rectangle {
                    width: parent.width
                    height: 240
                    color: "#f8f9fa"
                    radius: 6
                    border.color: "#dee2e6"
                    border.width: 1
                   
                    Column {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 10
                       
                        Text {
                            text: "🛰️ Total Waypoints: ${markersData.length}"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "⬆️ Altitude: ${waypointsMap.surveyAltitude} meters"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "🚀 Speed: ${waypointsMap.surveySpeed} m/s"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "📏 Total Distance: ${(totalDistance / 1000).toFixed(2)} km"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "⏱️ Est. Flight Time: ${minutes}m ${seconds}s"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "📷 Overlap: ${waypointsMap.surveyOverlap}%"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "📷 Sidelap: ${waypointsMap.surveySidelap}%"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                       
                        Text {
                            text: "🧭 Grid Angle: ${waypointsMap.surveyAngle}°"
                            font.pixelSize: 14
                            font.family: "Consolas"
                        }
                    }
                }
               
                Text {
                    text: "⚠️ Make sure drone is armed and in AUTO mode"
                    font.pixelSize: 12
                    font.italic: true
                    color: "#dc3545"
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
               
                Row {
                    spacing: 10
                    width: parent.width
                   
                    Button {
                        width: (parent.width - 10) / 2
                        height: 45
                        text: "Cancel"
                        background: Rectangle {
                            color: parent.pressed ? "#e9ecef" : "#f8f9fa"
                            radius: 6
                            border.color: "#dee2e6"
                            border.width: 1
                        }
                        onClicked: parent.parent.parent.parent.destroy()
                    }
                   
                    Button {
                        width: (parent.width - 10) / 2
                        height: 45
                        text: "Send to Drone"
                        background: Rectangle {
                            color: "#9c27b0"
                            radius: 6
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: {
                            parent.parent.parent.parent.destroy()
                            sendSurveyMission()
                        }
                    }
                }
            }
        }
    `, mainWindow);
   
    confirmPopup.open();
}
function calculateDistance(lat1, lon1, lat2, lon2) {
    var R = 6371000; // Earth radius in meters
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLon = (lon2 - lon1) * Math.PI / 180;
    var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c; // Distance in meters
}

// ===============================
// WAYPOINTS HANDLING SCRIPT
// ===============================

// Open File Dialog for loading waypoints
function openFileDialog() {
    waypointsMap.runJavaScript(`
        var fileInput = document.createElement('input');
        fileInput.type = 'file';
        fileInput.accept = '.waypoints,.json';
        fileInput.style.display = 'none';
       
        fileInput.onchange = function(e) {
            var file = e.target.files[0];
            if (file) {
                var reader = new FileReader();
                reader.onload = function(event) {
                    window.selectedFileContent = event.target.result;
                    window.selectedFileName = file.name;
                    console.log('File selected: ' + file.name);
                };
                reader.readAsText(file);
            }
        };
       
        document.body.appendChild(fileInput);
        fileInput.click();
        document.body.removeChild(fileInput);
    `);

    // Create QML timer to wait for file read completion
    var checkTimer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 500; repeat: true }', mainWindow);
    var attempts = 0;

    checkTimer.triggered.connect(function() {
        attempts++;

        waypointsMap.runJavaScript(`
            if (window.selectedFileContent && window.selectedFileName) {
                JSON.stringify({
                    content: window.selectedFileContent,
                    name: window.selectedFileName
                });
            } else null;
        `, function(result) {
            if (result) {
                try {
                    var data = JSON.parse(result);
                    loadDataInput.text = data.content;
                    selectedFileText.text = data.name;

                    waypointsMap.runJavaScript(`
                        window.selectedFileContent = null;
                        window.selectedFileName = null;
                    `);

                    checkTimer.stop();
                    checkTimer.destroy();

                    console.log("✅ File loaded successfully: " + data.name);

                } catch (err) {
                    console.log("⚠️ Error parsing file data:", err);
                }
            } else if (attempts > 20) {
                checkTimer.stop();
                checkTimer.destroy();
            }
        });
    });

    checkTimer.start();
        openWaypointsDialog.open(); // ✅ Opens the native system file explorer

}



// ===============================
// SAVE WAYPOINTS TO SYSTEM
// ===============================

function saveWaypointsData(filename) {
    var markersData = waypointsMap.getAllMarkers();
    
    if (!markersData || markersData.length === 0) {
        console.log("⚠️ No waypoints to save");
        statusNotification.color = theme.error;
        statusNotificationLabel.text = "No waypoints to save!";
        statusNotification.opacity = 1;
        statusNotificationTimer.restart();
        return;
    }

    try {
        // ═══════════════════════════════════════════════════════════════
        // BUILD WAYPOINTS IN NEW FORMAT
        // ═══════════════════════════════════════════════════════════════
        var waypoints = [];
        
        for (var i = 0; i < markersData.length; i++) {
            var marker = markersData[i];
            
            // Map commandType to command names
            var commandName = "WAYPOINT";
            var commandType = marker.commandType || "waypoint";
            
            if (commandType === "takeoff") commandName = "TAKEOFF";
            else if (commandType === "land") commandName = "LAND";
            else if (commandType === "return") commandName = "RTL";
            else if (commandType === "loiter") commandName = "LOITER";
            else if (commandType === "circle") commandName = "CIRCLE";
            
            var waypoint = {
                "id": i + 1,
                "command": commandName,
                "latitude": marker.lat,
                "longitude": marker.lng,
                "altitude": marker.altitude || 10.0,
                "hold_time": marker.holdTime || 0
            };
            
            waypoints.push(waypoint);
        }
        
        // ═══════════════════════════════════════════════════════════════
        // CREATE MISSION FILE WITH METADATA
        // ═══════════════════════════════════════════════════════════════
        var missionData = {
            "mission_name": filename,
            "frame": "GLOBAL_RELATIVE_ALT",
            "created_date": new Date().toISOString(),
            "waypoints": waypoints,
            "total_waypoints": waypoints.length
        };
        
        mainWindow.pendingWaypointData = JSON.stringify(missionData, null, 2);
        
        console.log("💾 Prepared mission file:");
        console.log("   Mission name:", filename);
        console.log("   Total waypoints:", waypoints.length);
        console.log("   Frame:", "GLOBAL_RELATIVE_ALT");

        // Open save dialog
        saveWaypointsDialog.open();

    } catch (e) {
        console.log("❌ Error preparing waypoints data:", e);
        statusNotification.color = theme.error;
        statusNotificationLabel.text = "Error preparing data";
        statusNotification.opacity = 1;
        statusNotificationTimer.restart();
    }
}
// ===============================
// LOAD WAYPOINTS DATA
// ===============================
// LOAD WAYPOINTS DATA (Dynamic Dialog - always opens system folder)
// ===============================
// ===============================
// LOAD WAYPOINTS DATA (Mission Planner style)
// ===============================
function loadWaypointsData(jsonString) {
    try {
        var missionData = JSON.parse(jsonString);
        
        // Check for new format with metadata
        if (missionData.waypoints && Array.isArray(missionData.waypoints)) {
            console.log("📂 Loading mission file (NEW FORMAT)");
            console.log("   Mission name:", missionData.mission_name || "Unknown");
            console.log("   Frame:", missionData.frame || "GLOBAL_RELATIVE_ALT");
            console.log("   Total waypoints:", missionData.total_waypoints || missionData.waypoints.length);
            console.log("   Created:", missionData.created_date || "Unknown");
            
            // Clear existing waypoints
            if (typeof waypointsMap !== "undefined" && waypointsMap.clearAllMarkersJS) {
                waypointsMap.clearAllMarkersJS();
            }

            // Add waypoints from file
            if (typeof waypointsMap !== "undefined" && waypointsMap.addMarkerJS) {
                for (var i = 0; i < missionData.waypoints.length; i++) {
                    var wp = missionData.waypoints[i];
                    
                    // Map command name to commandType
                    var commandType = "waypoint";
                    var command = wp.command ? wp.command.toUpperCase() : "WAYPOINT";
                    
                    if (command === "TAKEOFF") commandType = "takeoff";
                    else if (command === "LAND") commandType = "land";
                    else if (command === "RTL") commandType = "return";
                    else if (command === "LOITER") commandType = "loiter";
                    else if (command === "CIRCLE") commandType = "circle";
                    
                    waypointsMap.addMarkerJS(
                        wp.latitude,
                        wp.longitude,
                        wp.altitude,
                        0,  // speed (not used in this format)
                        commandType,
                        wp.hold_time || 0
                    );
                    
                    console.log("📍 Loaded WP" + wp.id + ": " + 
                               "Command=" + command + ", " +
                               "Alt=" + wp.altitude + "m");
                }
            }

            console.log("✅ Loaded " + missionData.waypoints.length + " waypoints");
            
            statusNotification.color = theme.success;
            statusNotificationLabel.text = "✅ Loaded mission: " + (missionData.mission_name || "Unknown");
            statusNotification.opacity = 1;
            statusNotificationTimer.restart();
            
        } else {
            throw new Error("Invalid mission file format");
        }

    } catch (err) {
        console.log("❌ Error loading waypoints:", err);
        statusNotification.color = theme.error;
        statusNotificationLabel.text = "Invalid mission file.";
        statusNotification.opacity = 1;
        statusNotificationTimer.restart();
    }
}


// ===============================
// COPY TO CLIPBOARD
// ===============================
function copyToClipboard(text) {
    waypointsMap.runJavaScript(`
        const textarea = document.createElement('textarea');
        textarea.value = ${JSON.stringify(text)};
        document.body.appendChild(textarea);
        textarea.select();
        try {
            document.execCommand('copy');
            console.log('✅ Data copied to clipboard');
        } catch (err) {
            console.log('❌ Failed to copy to clipboard');
        }
        document.body.removeChild(textarea);
    `);
}



// ===============================
// SHOW EXPORT DATA POPUP
// ===============================
function showWaypointExportData(jsonString) {
    var exportPopup = Qt.createQmlObject(`
        import QtQuick 2.15
        import QtQuick.Controls 2.15

        Popup {
            width: 500
            height: 420
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            modal: true
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            background: Rectangle {
                color: "#ffffff"
                border.color: "#dee2e6"
                border.width: 1
                radius: 8
            }

            Column {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10

                Text {
                    text: "Exported Waypoints Data"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#212529"
                }

                Rectangle {
                    width: parent.width - 10
                    height: 310
                    radius: 6
                    border.color: "#dee2e6"
                    border.width: 1
                    color: "#f8f9fa"
                    clip: true

                    TextEdit {
                        anchors.fill: parent
                        anchors.margins: 10
                        font.pixelSize: 11
                        font.family: "Courier New"
                        color: "#212529"
                        readOnly: true
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        text: ${JSON.stringify(jsonString)}
                    }
                }

                Button {
                    width: parent.width - 10
                    height: 35
                    background: Rectangle {
                        color: "#007bff"
                        radius: 6
                    }
                    contentItem: Text {
                        text: "Close"
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: destroy()
                }
            }
        }
    `, mainWindow);
    exportPopup.open();
}


Connections {
    target: droneCommander
   
    // If droneCommander emits missionUploadSuccess signal
    function onMissionUploadSuccess(waypointCount) {
        uploadSuccessPopup.waypointCount = waypointCount;
        uploadSuccessPopup.open();
    }
   
    // If droneCommander emits missionUploadFailed signal
    function onMissionUploadFailed(errorMsg) {
        uploadErrorPopup.errorMessage = "Upload failed:\n" + errorMsg;
        uploadErrorPopup.open();
    }
}

function clearPolygon() {
    waypointsMap.polygonCorners = []
    waypointsMap.polygonSurveyMode = false
    waypointsMap.clearAllMarkers()
    console.log("🗑️ Polygon cleared")
}
// ===============================
// MISSION STATISTICS FUNCTIONS
// ===============================

// ===============================
// MISSION STATISTICS FUNCTIONS - ROBUST VERSION
// ===============================

function updateMissionStatistics() {
    var markersData = waypointsMap.getAllMarkers();
   
    if (!markersData || markersData.length === 0) {
        totalWaypointsText.text = "0";
        totalDistanceText.text = "0.0 km";
        estimatedTimeText.text = "0m 0s";
        coveredDistanceText.text = "0.0 km";
        return;
    }
   
    // Update total waypoints
    totalWaypointsText.text = markersData.length.toString();
   
    // Calculate total distance
    var totalDistance = 0;
    for (var i = 0; i < markersData.length - 1; i++) {
        var dist = calculateDistance(
            markersData[i].lat, markersData[i].lng,
            markersData[i + 1].lat, markersData[i + 1].lng
        );
        if (!isNaN(dist) && isFinite(dist)) {
            totalDistance += dist;
        }
    }
   
    // Update total distance text
    totalDistanceText.text = (totalDistance / 1000).toFixed(2) + " km";
   
    // Calculate estimated time BEFORE mission starts
    if (!waypointsMap.missionActive) {
        var avgSpeed = waypointsMap.surveySpeed || 1.5; // Default 1.5 m/s
        if (avgSpeed > 0) {
            var estimatedSeconds = totalDistance / avgSpeed;
            var minutes = Math.floor(estimatedSeconds / 60);
            var seconds = Math.floor(estimatedSeconds % 60);
            estimatedTimeText.text = minutes + "m " + seconds + "s";
        } else {
            estimatedTimeText.text = "0m 0s";
        }
        estimatedTimeText.color = "#ff9800";
       
        // Reset covered distance when mission not active
        coveredDistanceText.text = "0.0 km";
        coveredDistanceText.color = theme.success;
    }
}

function updateCoveredDistance() {
    console.log("📊 Updating covered distance...");
   
    if (!waypointsMap.missionActive) {
        console.log("   Mission not active");
        coveredDistanceText.text = "0.0 km";
        coveredDistanceText.color = theme.success;
        return;
    }
   
    var markersData = waypointsMap.getAllMarkers();
    if (!markersData || markersData.length === 0) {
        console.log("   No waypoints");
        coveredDistanceText.text = "0.0 km";
        return;
    }
   
    var currentWPIndex = waypointsMap.currentWaypointIndex || 0;
    var droneLat = waypointsMap.currentLat || 0;
    var droneLon = waypointsMap.currentLon || 0;
   
    console.log("   Drone position:", droneLat, droneLon);
    console.log("   Current WP index:", currentWPIndex);
   
    // Check if drone has valid position
    if (droneLat === 0 && droneLon === 0) {
        console.log("   Invalid drone position");
        coveredDistanceText.text = "0.0 km";
        return;
    }
   
    var coveredDist = 0;
    var validCalculation = false;
   
    // Method 1: Try using actual flight path (most accurate)
    var actualPath = waypointsMap.actualFlightPath;
    if (actualPath && actualPath.length >= 2) {
        console.log("   Using actual flight path:", actualPath.length, "points");
        for (var i = 0; i < actualPath.length - 1; i++) {
            var pathDist = calculateDistance(
                actualPath[i].latitude,
                actualPath[i].longitude,
                actualPath[i + 1].latitude,
                actualPath[i + 1].longitude
            );
            if (!isNaN(pathDist) && isFinite(pathDist)) {
                coveredDist += pathDist;
                validCalculation = true;
            }
        }
    }
   
    // Method 2: If no flight path, calculate based on waypoint progress
    if (!validCalculation && currentWPIndex > 0) {
        console.log("   Using waypoint-based calculation");
       
        // Add distance of completed waypoint segments
        for (var j = 0; j < currentWPIndex && j < markersData.length - 1; j++) {
            var segDist = calculateDistance(
                markersData[j].lat, markersData[j].lng,
                markersData[j + 1].lat, markersData[j + 1].lng
            );
            if (!isNaN(segDist) && isFinite(segDist)) {
                coveredDist += segDist;
                validCalculation = true;
            }
        }
       
        // Add partial distance to current waypoint
        if (currentWPIndex < markersData.length && currentWPIndex > 0) {
            var prevWP = markersData[currentWPIndex - 1];
            var partialDist = calculateDistance(
                prevWP.lat, prevWP.lng,
                droneLat, droneLon
            );
            if (!isNaN(partialDist) && isFinite(partialDist)) {
                coveredDist += partialDist;
            }
        }
    }
   
    // Method 3: If still no valid data, use distance from first waypoint
    if (!validCalculation && markersData.length > 0) {
        console.log("   Using distance from start");
        var startWP = markersData[0];
        var fromStart = calculateDistance(
            startWP.lat, startWP.lng,
            droneLat, droneLon
        );
        if (!isNaN(fromStart) && isFinite(fromStart)) {
            coveredDist = fromStart;
            validCalculation = true;
        }
    }
   
    // Validate the result
    if (!validCalculation || isNaN(coveredDist) || !isFinite(coveredDist)) {
        console.log("   ❌ Invalid calculation result");
        coveredDistanceText.text = "0.0 km";
        return;
    }
   
    // Get total distance and cap covered distance
    var totalDistText = totalDistanceText.text.replace(" km", "");
    var totalDist = parseFloat(totalDistText) * 1000;
   
    if (!isNaN(totalDist) && totalDist > 0 && coveredDist > totalDist * 1.1) {
        // Allow 10% overage for GPS inaccuracy
        coveredDist = totalDist;
    }
   
    console.log("   ✅ Covered distance:", (coveredDist / 1000).toFixed(2), "km");
    coveredDistanceText.text = (coveredDist / 1000).toFixed(2) + " km";
   
    // Update color based on progress
    if (totalDist > 0) {
        var progress = (coveredDist / totalDist) * 100;
        if (progress >= 90) {
            coveredDistanceText.color = "#4caf50"; // Green
        } else if (progress >= 50) {
            coveredDistanceText.color = "#ff9800"; // Orange
        } else {
            coveredDistanceText.color = "#2196f3"; // Blue
        }
    } else {
        coveredDistanceText.color = theme.success;
    }
}

function updateRemainingTime() {
    if (!waypointsMap.missionActive) {
        return;
    }
   
    var markersData = waypointsMap.getAllMarkers();
    if (!markersData || markersData.length === 0) {
        estimatedTimeText.text = "0m 0s";
        return;
    }
   
    var currentWPIndex = waypointsMap.currentWaypointIndex || 0;
    var droneLat = waypointsMap.currentLat || 0;
    var droneLon = waypointsMap.currentLon || 0;
   
    // Check for valid position
    if (droneLat === 0 && droneLon === 0) {
        return;
    }
   
    // Mission completed
    if (currentWPIndex >= markersData.length) {
        estimatedTimeText.text = "0m 0s";
        estimatedTimeText.color = "#4caf50";
        return;
    }
   
    var remainingDistance = 0;
    var avgSpeed = waypointsMap.surveySpeed || 1.5;
   
    if (avgSpeed <= 0) {
        avgSpeed = 1.5; // Fallback
    }
   
    // Distance from drone to current target waypoint
    if (currentWPIndex >= 0 && currentWPIndex < markersData.length) {
        var targetWP = markersData[currentWPIndex];
        var distToTarget = calculateDistance(
            droneLat, droneLon,
            targetWP.lat, targetWP.lng
        );
        if (!isNaN(distToTarget) && isFinite(distToTarget)) {
            remainingDistance += distToTarget;
        }
    }
   
    // Add remaining waypoint segments
    for (var i = currentWPIndex; i < markersData.length - 1; i++) {
        var segDist = calculateDistance(
            markersData[i].lat, markersData[i].lng,
            markersData[i + 1].lat, markersData[i + 1].lng
        );
        if (!isNaN(segDist) && isFinite(segDist)) {
            remainingDistance += segDist;
        }
    }
   
    // Calculate time
    var remainingSeconds = remainingDistance / avgSpeed;
   
    if (isNaN(remainingSeconds) || !isFinite(remainingSeconds)) {
        estimatedTimeText.text = "0m 0s";
        return;
    }
   
    var minutes = Math.floor(remainingSeconds / 60);
    var seconds = Math.floor(remainingSeconds % 60);
   
    estimatedTimeText.text = minutes + "m " + seconds + "s";
   
    // Color coding
    if (remainingSeconds < 60) {
        estimatedTimeText.color = "#4caf50"; // Green
    } else if (remainingSeconds < 300) {
        estimatedTimeText.color = "#ff9800"; // Orange
    } else {
        estimatedTimeText.color = "#ff5722"; // Red
    }
}

// Update timers with better logging
Timer {
    id: missionStatsTimer
    interval: 1000
    running: waypointsMap.missionActive
    repeat: true
   
    onTriggered: {
        updateCoveredDistance();
        updateRemainingTime();
    }
}

Timer {
    id: staticStatsTimer
    interval: 2000
    running: !waypointsMap.missionActive
    repeat: true
   
    onTriggered: {
        updateMissionStatistics();
    }
}

// Upload Error Popup
Popup {
    id: uploadErrorPopup
    width: 300
    height: 200
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    property string errorMessage: ""
    
    background: Rectangle {
        color: "white"
        border.color: theme.error
        border.width: 2
        radius: 8
    }
    
    contentItem: Column {
        spacing: 15
        padding: 20
        
        Text {
            text: "⚠️ Upload Error"
            font.pixelSize: 18
            font.bold: true
            color: theme.error
            anchors.horizontalCenter: parent.horizontalCenter
        }
        
        Text {
            text: uploadErrorPopup.errorMessage
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 14
            color: theme.textPrimary
        }
        
        Button {
            text: "OK"
            highlighted: true
            background: Rectangle {
                color: theme.error
                radius: 4
            }
            contentItem: Text {
                text: "OK"
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: uploadErrorPopup.close()
        }
    }
}
}
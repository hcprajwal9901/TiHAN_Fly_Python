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

    minimumWidth: 1200
    minimumHeight: 700
    title: "TiHAN Fly-Drone Control Station"
    color: "#f8f9fa"  // Light background
    property var referencePoint: QtPositioning.coordinate(17.601588777182204, 78.12690006798547)
    property var lastClickedCoordinate: null
    property var waypoints: []
    property bool isDragging: false
    property var pendingWaypointData: ""  // ✅ Correct

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
            statusNotification.children[0].text = "✅ File saved: " + path;
        } else {
            console.log("❌ Save failed");
            statusNotification.color = theme.error;
            statusNotification.children[0].text = "Error saving file!";
        }
        mainWindow.statusNotification.opacity = 1;

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
            statusNotification.children[0].text = "⚠️ Failed to read file.";
            mainWindow.statusNotification.opacity = 1;

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
Rectangle {
    id: header
    width: parent.width
    height: 70
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
        spacing: 20

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
                font.pixelSize: 50
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

        Item { Layout.fillWidth: true }

        // Language Dropdown Button
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

    // Language Dropdown Menu
    }
    
    // Close dropdown when clicking outside
    MouseArea {
        anchors.fill: parent
        enabled: languageDropdown.visible
        onClicked: languageDropdown.visible = false
        z: -1
    }

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
                anchors.centerIn: parent
                text: "Parameter updated successfully!"
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
            
            // Telemetry Bindings
            currentLat: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.lat || 0 : 0
            currentLon: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.lon || 0 : 0
            currentAlt: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry) ? droneModel.telemetry.rel_alt || 0 : 0
            isDroneConnected: (typeof droneModel !== "undefined" && droneModel) ? droneModel.isConnected : false
            
            // Signal Handlers
            onMarkerAdded: {
                console.log("📍 Waypoint added at:", lat, lon)
                if (typeof onWaypointAdded === "function") {
                    // Update external state if needed
                    console.log("Calling onWaypointAdded handler if exists")
                }
            }
            
            onMarkerMoved: {
                console.log("📍 Waypoint moved:", index)
            }
            
            onMarkerDeleted: {
                console.log("🗑️ Waypoint deleted")
                 if (typeof onWaypointDeleted === "function") {
                    console.log("Calling onWaypointDeleted handler if exists")
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
                map.center = QtPositioning.coordinate(0, 0)
                map.zoomLevel = 2
            }
        }

        // Map overlay controls
Rectangle {
    id: mapControls
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 15
    width: 50
    height: 350  // Increased to accommodate all buttons
    color: "#ffffff"
    radius: 8
    border.color: theme.border
    border.width: 1
    opacity: 0.95

    Column {
        anchors.centerIn: parent
        spacing: 8

        // World View Button
        Button {
            id: worldViewBtn
            width: 35
            height: 35
            text: "🌍"
            
            background: Rectangle {
                color: worldViewBtn.pressed ? "#e9ecef" : (worldViewBtn.hovered ? "#f8f9fa" : "#ffffff")
                radius: 6
                border.color: theme.accent
                border.width: 1
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: worldViewBtn.text
                font.pixelSize: 14
                color: theme.textPrimary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: {
                waypointsMap.resetToWorldViewJS();
            }
        }

        // Weather Button
        Button {
    id: weatherControlBtn
    width: 35
    height: 35
    text: "🌤️"
    
    background: Rectangle {
        color: weatherDashboard.visible ? theme.accent : 
               (weatherControlBtn.pressed ? "#e9ecef" : (weatherControlBtn.hovered ? "#f8f9fa" : "#ffffff"))
        radius: 6
        border.color: theme.accent
        border.width: 1
    }
    
    contentItem: Text {
        text: weatherControlBtn.text
        font.pixelSize: 14
        color: weatherDashboard.visible ? "white" : theme.textPrimary
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
        property real speed: 5
        
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
                                waypointsMap.runJavaScript(`
                                    if (markers[${markerPopup.markerIndex}]) {
                                        markers[${markerPopup.markerIndex}].altitude = ${val};
                                    }
                                `);
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
                                waypointsMap.runJavaScript(`
                                    if (markers[${markerPopup.markerIndex}]) {
                                        markers[${markerPopup.markerIndex}].speed = ${val};
                                    }
                                `);
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
    WaypointDashboard {
    id: waypointDashboard
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: header.height + 20
    anchors.rightMargin: 20
    visible: false
    z: 100
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
                // Update dashboard after clearing
                Qt.callLater(function() {
                    onWaypointDeleted();
                });
            }
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
        Item { Layout.fillHeight: true }
        Text { 
            color: theme.textSecondary
            font.pixelSize: 12
            font.family: "Consolas"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight 
        }
        
    }
    
 
}
Popup {
    id: uploadSuccessPopup
    width: 400
    height: 250
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    property int waypointCount: 0
    
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
    
    contentItem: Column {
        spacing: 20
        padding: 20
        
        // Success Icon
        Rectangle {
            width: 80
            height: 80
            radius: 40
            color: "#28a74520"
            anchors.horizontalCenter: parent.horizontalCenter
            
            Text {
                text: "✓"
                font.pixelSize: 48
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
        
        // Details
        Text {
            text: uploadSuccessPopup.waypointCount + " waypoint(s) uploaded to drone"
            font.pixelSize: 14
            font.family: "Consolas"
            color: theme.textSecondary
            anchors.horizontalCenter: parent.horizontalCenter
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
    
    // Auto-close timer (optional)
    Timer {
        id: autoCloseSuccessTimer
        interval: 3000
        onTriggered: uploadSuccessPopup.close()
    }
    
    onOpened: {
        // Uncomment to enable auto-close after 3 seconds
        // autoCloseSuccessTimer.start()
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
        waypointsMap.runJavaScript(`
            if (markers[${index}]) {
                JSON.stringify({
                    index: ${index},
                    lat: markers[${index}].lat,
                    lng: markers[${index}].lng,
                    altitude: markers[${index}].altitude,
                    speed: markers[${index}].speed
                });
            } else {
                null;
            }
        `, function(result) {
            if (result) {
                try {
                    var data = JSON.parse(result);
                    markerPopup.markerIndex = data.index;
                    markerPopup.altitude = data.altitude;
                    markerPopup.speed = data.speed;
                    markerPopup.open();
                } catch (e) {
                    console.log("Error parsing marker data:", e);
                }
            }
        });
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
    console.log("=== Testing getAllMarkersJS ===");
    if (waypointsMap) {
        waypointsMap.runJavaScript("markers.length", function(result) {
            console.log("JavaScript markers.length:", result);
        });
        
        waypointsMap.runJavaScript("JSON.stringify(getAllMarkers())", function(result) {
            console.log("Direct getAllMarkers():", result);
        });
    }
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
    waypointsMap.runJavaScript("JSON.stringify(getAllMarkers());", function(result) {
        if (!result) {
            console.log("No markers to send");
            uploadErrorPopup.errorMessage = "No waypoints found to upload.\nPlease add waypoints to the map first.";
            uploadErrorPopup.open();
            return;
        }

        try {
            var markersData = JSON.parse(result);
            if (markersData.length === 0) {
                uploadErrorPopup.errorMessage = "No waypoints available.\nPlease add waypoints before uploading.";
                uploadErrorPopup.open();
                return;
            }

            var waypoints = [];
            console.log("Sending " + markersData.length + " markers as waypoints...");
            
            // Calculate distances and prepare data
            var waypointsWithDistance = [];
            for (var i = 0; i < markersData.length; i++) {
                var marker = markersData[i];
                var command = 16;
                
                switch(marker.commandType) {
                    case "takeoff": command = 22; break;
                    case "land": command = 21; break;
                    case "return": command = 20; break;
                    case "loiter": command = 17; break;
                    case "circle": command = 18; break;
                    case "follow": command = 19; break;
                    default: command = 16; break;
                }

                waypoints.push({
                    seq: i+1,
                    frame: 6,
                    command: command,
                    autocontinue: 1,
                    param1: marker.holdTime || 0,
                    param2: 0,
                    param3: 0,
                    param4: 0,
                    x: marker.lat,
                    y: marker.lng,
                    z: marker.altitude || 10
                });
                
                // Prepare waypoint display data with distance calculation
                var wpData = {
                    lat: marker.lat,
                    lng: marker.lng,
                    altitude: marker.altitude || 10,
                    speed: marker.speed || 5,
                    commandType: marker.commandType || "waypoint",
                    placeName: "Fetching...",
                    distanceToNext: ""
                };
                
                // Calculate distance to next waypoint using the helper function
                if (i < markersData.length - 1) {
                    var nextMarker = markersData[i + 1];
                    var distance = calculateDistance(
                        marker.lat, marker.lng,
                        nextMarker.lat, nextMarker.lng
                    );
                    
                    if (distance < 1000) {
                        wpData.distanceToNext = distance.toFixed(1) + " m";
                    } else {
                        wpData.distanceToNext = (distance / 1000).toFixed(2) + " km";
                    }
                }
                
                waypointsWithDistance.push(wpData);
            }

            if (typeof droneCommander === 'undefined') {
                uploadErrorPopup.errorMessage = "Drone commander not initialized.\nPlease check your drone connection.";
                uploadErrorPopup.open();
                return;
            }

            try {
                var uploadResult = droneCommander.uploadMission(waypoints);
                
                if (uploadResult === false || uploadResult === null) {
                    throw new Error("Mission upload returned false");
                }
                
                // Populate the list model and show success popup
                uploadWaypointListModel.clear();
                missionUploadSuccessPopup.waypointsData = waypointsWithDistance;

                for (var j = 0; j < waypointsWithDistance.length; j++) {
                    uploadWaypointListModel.append(waypointsWithDistance[j]);
                }
                
                missionUploadSuccessPopup.waypointCount = markersData.length;
                missionUploadSuccessPopup.open();
                
                console.log("✅ Mission uploaded successfully: " + markersData.length + " waypoints");
                
                if (typeof mapViewInstance !== 'undefined' && mapViewInstance) {
                    console.log("Sending markers to MapView...");
                    mapViewInstance.receiveMarkersFromNavigation(markersData);
                }
                
            } catch (uploadError) {
                console.log("❌ Upload failed:", uploadError);
                uploadErrorPopup.errorMessage = "Failed to upload mission to drone:\n" + 
                    (uploadError.message || uploadError.toString()) + 
                    "\n\nPlease check:\n• Drone connection\n• Telemetry link\n• Flight controller status";
                uploadErrorPopup.open();
            }
            
        } catch (e) {
            console.log("❌ Error preparing mission:", e);
            uploadErrorPopup.errorMessage = "Error preparing waypoints for upload:\n" + 
                e.toString() + "\n\nPlease check your waypoint data.";
            uploadErrorPopup.open();
        }
    });
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
    waypointsMap.runJavaScript("JSON.stringify(getAllMarkers());", function(result) {
        if (!result) {
            console.log("⚠️ No waypoints to save");
            statusNotification.color = theme.error;
            statusNotification.children[0].text = "No waypoints to save!";
            mainWindow.statusNotification.opacity = 1;

            statusNotificationTimer.restart();
            return;
        }

        try {
            var markersData = JSON.parse(result);
            var waypointsData = {
                version: "1.0",
                timestamp: new Date().toISOString(),
                filename: filename,
                totalWaypoints: markersData.length,
                waypoints: markersData
            };
            mainWindow.pendingWaypointData = JSON.stringify(waypointsData, null, 2);


            // ✅ Open Save As dialog (user chooses location)
            saveWaypointsDialog.open();

        } catch (e) {
            console.log("❌ Error preparing waypoints data:", e);
            statusNotification.color = theme.error;
            statusNotification.children[0].text = "Error preparing data";
            mainWindow.statusNotification.opacity = 1;

            statusNotificationTimer.restart();
        }
    });
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
        var waypointsData = JSON.parse(jsonString);
        if (!waypointsData.waypoints || !Array.isArray(waypointsData.waypoints))
            throw new Error("Invalid format");

        // Clear and add markers to map
        if (typeof waypointsMap !== "undefined" && waypointsMap.clearAllMarkersJS)
            waypointsMap.clearAllMarkersJS();

        if (typeof waypointsMap !== "undefined" && waypointsMap.addMarkerJS) {
            for (var i = 0; i < waypointsData.waypoints.length; i++) {
                var wp = waypointsData.waypoints[i];
                waypointsMap.addMarkerJS(
                    wp.lat,
                    wp.lng,
                    wp.altitude || 10,
                    wp.speed || 5,
                    wp.commandType || "waypoint",
                    wp.holdTime || 0
                );
            }
        }

        // Optional: refresh map display
        if (typeof waypointsMap !== "undefined")
            waypointsMap.runJavaScript("refreshMap && refreshMap();");

        console.log("✅ Loaded " + waypointsData.waypoints.length + " waypoints");
        statusNotification.color = theme.success;
        statusNotification.children[0].text = "✅ Loaded " + waypointsData.waypoints.length + " waypoints!";
        mainWindow.statusNotification.opacity = 1;

        statusNotificationTimer.restart();

    } catch (err) {
        console.log("❌ Error loading waypoints:", err);
        statusNotification.color = theme.error;
        statusNotification.children[0].text = "Invalid waypoints file.";
        mainWindow.statusNotification.opacity = 1;

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
}





import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15

Rectangle {
    id: root
    width: 350
    height: 200  // Increased height for status display
    color: "transparent"
    
    property bool geoFenceEnabled: true
    property int geoFenceRadius: 500
    property string flightMode: typeof droneModel !== 'undefined' && droneModel.telemetry ? 
                                droneModel.telemetry.mode || "UNKNOWN" : "UNKNOWN"
    
    // ✅ NEW: Status properties
    property string batteryFsStatus: "Not loaded"
    property string rcFsStatus: "Not loaded"
    
    // Background card with gradient
    Rectangle {
        id: backgroundCard
        anchors.fill: parent
        radius: 8
        border.color: "#bdc3c7"
        border.width: 1
        
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f8f9fa" }
            GradientStop { position: 0.5; color: "#e9ecef" }
            GradientStop { position: 1.0; color: "#dee2e6" }
        }
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 2
            radius: 4
            samples: 9
            color: "#20000000"
        }
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        
        // Header
        Text {
            text: "Fail-Safe Configuration"
            color: "#2c3e50"
            font.pixelSize: 14
            font.family: "Segoe UI"
            font.weight: Font.Bold
            width: parent.width
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Battery FailSafe Row
        // ═══════════════════════════════════════════════════════════════
        Rectangle {
            width: parent.width
            height: 60  // Increased for status text
            color: "#ffffff"
            radius: 6
            border.color: batteryFailSafeAction.currentIndex > 0 ? "#27ae60" : "#e74c3c"
            border.width: 2
            
            Behavior on border.color {
                ColorAnimation { duration: 200 }
            }
            
            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                
                Row {
                    width: parent.width
                    height: 32
                    spacing: 10
                    
                    // Icon
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 5
                        color: "#fee2e2"
                        border.color: "#fca5a5"
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Text {
                            anchors.centerIn: parent
                            text: "🔋"
                            font.pixelSize: 16
                        }
                    }
                    
                    // Label
                    Text {
                        text: typeof languageManager !== 'undefined' && languageManager ? 
                              languageManager.getText("Battery Fail Safe") : "Battery Fail Safe"
                        color: "#2c3e50"
                        font.pixelSize: 13
                        font.family: "Segoe UI"
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                    }
                    
                    // Spacer
                    Item {
                        width: parent.width - 280
                        height: 1
                    }
                    
                    // ComboBox
                    ComboBox {
                        id: batteryFailSafeAction
                        model: ["None", "RTL", "Land", "Hold"]
                        currentIndex: 0
                        width: 80
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        
                        // ✅ CRITICAL: Send command to DroneCommander when activated by user
                        onActivated: {
                            if (typeof droneModel !== 'undefined' && 
                                droneModel.droneCommander && 
                                droneModel.isConnected) {
                                console.log("[FailSafeCard] Setting battery FS to:", currentText)
                                droneModel.droneCommander.setBatteryFailSafe(currentText)
                            }
                        }
                        
                        contentItem: Text {
                            leftPadding: 6
                            rightPadding: 26
                            text: batteryFailSafeAction.displayText
                            font.pixelSize: 11
                            font.family: "Segoe UI"
                            color: "#000000"
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignLeft
                        }
                        
                        background: Rectangle {
                            implicitWidth: 80
                            implicitHeight: 28
                            color: "#ffffff"
                            border.color: "#7f7f7f"
                            border.width: 1
                        }
                        
                        indicator: Canvas {
                            id: batteryCanvas
                            x: batteryFailSafeAction.width - width - 6
                            y: batteryFailSafeAction.height / 2 - height / 2
                            width: 12
                            height: 8
                            contextType: "2d"
                            
                            Connections {
                                target: batteryFailSafeAction
                                function onPressedChanged() { batteryCanvas.requestPaint(); }
                            }
                            
                            onPaint: {
                                context.reset();
                                context.moveTo(0, 0);
                                context.lineTo(width, 0);
                                context.lineTo(width / 2, height);
                                context.closePath();
                                context.fillStyle = "#000000";
                                context.fill();
                            }
                        }
                        
                        popup: Popup {
                            y: batteryFailSafeAction.height - 1
                            width: batteryFailSafeAction.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 0
                            margins: 0
                            
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: batteryFailSafeAction.popup.visible ? batteryFailSafeAction.delegateModel : null
                                currentIndex: batteryFailSafeAction.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                            
                            background: Rectangle {
                                color: "#ffffff"
                                border.color: "#7f7f7f"
                                border.width: 1
                                layer.enabled: true
                                layer.effect: DropShadow {
                                    transparentBorder: true
                                    horizontalOffset: 2
                                    verticalOffset: 2
                                    radius: 4
                                    samples: 9
                                    color: "#60000000"
                                }
                            }
                        }
                        
                        delegate: ItemDelegate {
                            width: batteryFailSafeAction.width
                            height: 26
                            padding: 0
                            
                            background: Rectangle {
                                color: {
                                    if (parent.highlighted || parent.pressed) 
                                        return "#0078d7"
                                    else if (parent.hovered)
                                        return "#cce8ff"
                                    else
                                        return "#ffffff"
                                }
                            }
                            
                            contentItem: Text {
                                text: modelData
                                font.pixelSize: 11
                                font.family: "Segoe UI"
                                color: (parent.highlighted || parent.pressed) ? "#ffffff" : "#000000"
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 6
                            }
                        }
                    }
                }
                
                // ✅ NEW: Status display
               // ✅ NEW: Status display
Text {
    text: root.batteryFsStatus  // ✅ Use property binding instead
    color: "#7f8c8d"
    font.pixelSize: 10
    font.family: "Segoe UI"
    font.italic: true
    width: parent.width
    leftPadding: 40
    elide: Text.ElideRight
}
            }
        }
      
        
        // ═══════════════════════════════════════════════════════════════
        // RC FailSafe Row
        // ═══════════════════════════════════════════════════════════════
        Rectangle {
            width: parent.width
            height: 60  // Increased for status text
            color: "#ffffff"
            radius: 6
            border.color: rcFailSafeAction.currentIndex > 0 ? "#27ae60" : "#e74c3c"
            border.width: 2
            
            Behavior on border.color {
                ColorAnimation { duration: 200 }
            }
            
            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                
                Row {
                    width: parent.width
                    height: 32
                    spacing: 10
                    
                    // Icon
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 5
                        color: "#dbeafe"
                        border.color: "#93c5fd"
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Text {
                            anchors.centerIn: parent
                            text: "📡"
                            font.pixelSize: 16
                        }
                    }
                    
                    // Label
                    Text {
                        text: typeof languageManager !== 'undefined' && languageManager ? 
                              languageManager.getText("RC FailSafe") : "RC FailSafe"
                        color: "#2c3e50"
                        font.pixelSize: 13
                        font.family: "Segoe UI"
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                    }
                    
                    // Spacer
                    Item {
                        width: parent.width - 280
                        height: 1
                    }
                    
                    // ComboBox
                    ComboBox {
                        id: rcFailSafeAction
                        model: ["None", "RTL", "Land", "Hold"]
                        currentIndex: 0
                        width: 80
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        
                        // ✅ CRITICAL: Send command to DroneCommander when activated by user
                        onActivated: {
                            if (typeof droneModel !== 'undefined' && 
                                droneModel.droneCommander && 
                                droneModel.isConnected) {
                                console.log("[FailSafeCard] Setting RC FS to:", currentText)
                                droneModel.droneCommander.setRCFailSafe(currentText)
                            }
                        }
                        
                        contentItem: Text {
                            leftPadding: 6
                            rightPadding: 26
                            text: rcFailSafeAction.displayText
                            font.pixelSize: 11
                            font.family: "Segoe UI"
                            color: "#000000"
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignLeft
                        }
                        
                        background: Rectangle {
                            implicitWidth: 80
                            implicitHeight: 28
                            color: "#ffffff"
                            border.color: "#7f7f7f"
                            border.width: 1
                        }
                        
                        indicator: Canvas {
                            id: rcCanvas
                            x: rcFailSafeAction.width - width - 6
                            y: rcFailSafeAction.height / 2 - height / 2
                            width: 12
                            height: 8
                            contextType: "2d"
                            
                            Connections {
                                target: rcFailSafeAction
                                function onPressedChanged() { rcCanvas.requestPaint(); }
                            }
                            
                            onPaint: {
                                context.reset();
                                context.moveTo(0, 0);
                                context.lineTo(width, 0);
                                context.lineTo(width / 2, height);
                                context.closePath();
                                context.fillStyle = "#000000";
                                context.fill();
                            }
                        }
                        
                        popup: Popup {
                            y: rcFailSafeAction.height - 1
                            width: rcFailSafeAction.width
                            implicitHeight: contentItem.implicitHeight
                            padding: 0
                            margins: 0
                            
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: rcFailSafeAction.popup.visible ? rcFailSafeAction.delegateModel : null
                                currentIndex: rcFailSafeAction.highlightedIndex
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                            
                            background: Rectangle {
                                color: "#ffffff"
                                border.color: "#7f7f7f"
                                border.width: 1
                                layer.enabled: true
                                layer.effect: DropShadow {
                                    transparentBorder: true
                                    horizontalOffset: 2
                                    verticalOffset: 2
                                    radius: 4
                                    samples: 9
                                    color: "#60000000"
                                }
                            }
                        }
                        
                        delegate: ItemDelegate {
                            width: rcFailSafeAction.width
                            height: 26
                            padding: 0
                            
                            background: Rectangle {
                                color: {
                                    if (parent.highlighted || parent.pressed) 
                                        return "#0078d7"
                                    else if (parent.hovered)
                                        return "#cce8ff"
                                    else
                                        return "#ffffff"
                                }
                            }
                            
                            contentItem: Text {
                                text: modelData
                                font.pixelSize: 11
                                font.family: "Segoe UI"
                                color: (parent.highlighted || parent.pressed) ? "#ffffff" : "#000000"
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 6
                            }
                        }
                    }
                }
                
                // ✅ NEW: Status display
                Text {
                    text: root.rcFsStatus
                    color: "#7f8c8d"
                    font.pixelSize: 10
                    font.family: "Segoe UI"
                    font.italic: true
                    width: parent.width
                    leftPadding: 40
                    elide: Text.ElideRight
                }
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // ✅ NEW: Status Update Timer
    // ═══════════════════════════════════════════════════════════════════
    Timer {
        id: statusUpdateTimer
        interval: 2000  // Update every 2 seconds
        running: typeof droneModel !== 'undefined' && droneModel.isConnected
        repeat: true
        
        onTriggered: {
            updateFailSafeStatus()
        }
    }
    
    // ✅ NEW: Function to update status displays
// ✅ FIXED: Function to update status displays
function updateFailSafeStatus() {
    console.log("[FailSafeCard] updateFailSafeStatus called")
    
    if (typeof droneModel === 'undefined' || !droneModel) {
        console.log("[FailSafeCard] droneModel is undefined")
        root.batteryFsStatus = "DroneModel not available"
        root.rcFsStatus = "DroneModel not available"
        return
    }
    
    if (!droneModel.droneCommander) {
        console.log("[FailSafeCard] droneCommander is null")
        root.batteryFsStatus = "DroneCommander not available"
        root.rcFsStatus = "DroneCommander not available"
        return
    }
    
    if (!droneModel.isConnected) {
        console.log("[FailSafeCard] Drone not connected")
        root.batteryFsStatus = "Not connected"
        root.rcFsStatus = "Not connected"
        return
    }
    
    console.log("[FailSafeCard] Attempting to get failsafe status...")
    
    // Get battery failsafe status
    try {
        var batteryStatus = droneModel.droneCommander.getBatteryFailSafeStatus()
        console.log("[FailSafeCard] Battery FS status:", batteryStatus)
        root.batteryFsStatus = batteryStatus
    } catch (e) {
        console.log("[FailSafeCard] Error getting battery status:", e)
        root.batteryFsStatus = "Error: " + e
    }
    
    // Get RC failsafe status
    try {
        var rcStatus = droneModel.droneCommander.getRCFailSafeStatus()
        console.log("[FailSafeCard] RC FS status:", rcStatus)
        root.rcFsStatus = rcStatus
    } catch (e) {
        console.log("[FailSafeCard] Error getting RC status:", e)
        root.rcFsStatus = "Error: " + e
    }
}
    
    // ═══════════════════════════════════════════════════════════════════
    // Connection handling
    // ═══════════════════════════════════════════════════════════════════
    Connections {
        target: typeof droneModel !== 'undefined' ? droneModel : null
        ignoreUnknownSignals: true
        
        function onTelemetryChanged() {
            if (droneModel && droneModel.telemetry) {
                root.flightMode = droneModel.telemetry.mode || "UNKNOWN"
            }
        }
        
        // ✅ NEW: Update status when parameters are loaded
        function onIsConnectedChanged() {
            if (droneModel.isConnected) {
                console.log("[FailSafeCard] Drone connected - will load failsafe status")
                updateFailSafeStatus()
            } else {
                root.batteryFsStatus = "Not connected"
                root.rcFsStatus = "Not connected"
            }
        }
    }
    
    // ✅ NEW: Update status when DroneCommander parameters are updated
    Connections {
        target: typeof droneModel !== 'undefined' && droneModel.droneCommander ? 
                droneModel.droneCommander : null
        ignoreUnknownSignals: true
        
        function onParametersUpdated() {
            console.log("[FailSafeCard] Parameters updated - refreshing status")
            updateFailSafeStatus()
        }
    }
    
    // ✅ Initialize status on component load
    Component.onCompleted: {
        console.log("[FailSafeCard] Component loaded")
        updateFailSafeStatus()
    }
}
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs 1.3

Row {
    id: root
    spacing: 10
   
    // Track which tab is currently active
    property string currentView: "statusPanel"  // Default to Panel
   
    // Connection status property
    property bool isConnected: (typeof droneModel !== "undefined" && droneModel) ? droneModel.isConnected : false
   
    // Font properties for ComboBox styling
    property int standardFontSize: 14
    property string standardFontFamily: "Arial"
    property int standardFontWeight: Font.Normal
   
    // ✅ CRITICAL: Bind directly to drone's armed status - auto-updates!
    property bool isArmed: typeof droneModel !== "undefined" && droneModel ? droneModel.isDroneArmed : false
   
    // ✅ CRITICAL: Bind to drone's current mode to sync the combobox
    property string currentFlightMode: typeof droneModel !== "undefined" && droneModel ? droneModel.droneMode : ""
    
    onCurrentFlightModeChanged: {
        if (currentFlightMode) {
            var idx = modeComboBox.find(currentFlightMode)
            if (idx !== -1 && modeComboBox.currentIndex !== idx) {
                modeComboBox.currentIndex = idx
            }
        }
    }
   
    MessageDialog {
        id: modeChangeDialog
        title: "Mode Changed"
        standardButtons: StandardButton.Ok
    }
   
    MessageDialog {
        id: armError
        title: "ERROR"
    }
   
    MessageDialog {
        id: armSuccess
        title: "Success"
    }
   
    // Timer to check arm/disarm status after command
    Timer {
        id: statusCheckTimer
        interval: 1500  // Wait 1.5 seconds for telemetry update
        repeat: false
        property bool wasArming: false
       
       
       
    }
   
    // ARM/DISARM Button - Always visible for quick access
    Button {
        id: armButton
        width: 150
        height: 40
       
        // Color matches the ACTION: Green for ARM, Red for DISARM
        background: Rectangle {
            color: parent.parent.isArmed ? "#F44336" : "#4CAF50"
            radius: 8
        }
       
        // Text shows the ACTION that will be performed when clicked
        Label {
            anchors.centerIn: parent
            text: parent.parent.isArmed ? "DISARM" : "ARM"
            color: "white"
            font.bold: true
        }
       
        onClicked: {
            if (parent.isArmed) {
                // Currently armed, try to disarm
                console.log("[StatusBar] Disarming drone...")
                droneCommander.disarm()
                statusCheckTimer.wasArming = false
                statusCheckTimer.start()
            } else {
                // Currently disarmed, try to arm
                console.log("[StatusBar] Arming drone...")
                droneCommander.arm()
                statusCheckTimer.wasArming = true
                statusCheckTimer.start()
            }
        }
    }
   
    // Helper function to safely get last status text
    function getLastStatusText() {
        if (droneModel.statusTexts && droneModel.statusTexts.length > 0) {
            return droneModel.statusTexts[droneModel.statusTexts.length - 1]
        }
        return "No status message available"
    }

    // Flight Mode Selector - Always visible for quick access
    ComboBox {
        id: modeComboBox
        width: 200
        height: 40
        model: [
            "STABILIZE", "ACRO", "ALT_HOLD", "AUTO", "GUIDED", "LOITER", "RTL", "CIRCLE", "POSITION", "LAND",
            "OF_LOITER", "DRIFT", "SPORT", "FLIP", "AUTOTUNE", "POSHOLD", "BRAKE", "THROW", "AVOID_ADSB",
            "GUIDED_NOGPS", "SMART_RTL", "FLOWHOLD", "FOLLOW", "ZIGZAG", "SYSTEMID", "AUTOROTATE", "AUTO_RTL"
        ]
        displayText: "Mode: " + currentText
        enabled: root.isConnected

        background: Rectangle {
            radius: 10
            border.width: 2
            border.color: enabled ? (modeComboBox.pressed ? "#4a90e2" : "#87ceeb") : "#adb5bd"
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: enabled ? (modeComboBox.pressed ? "#4a90e2" : (modeComboBox.hovered ? "#7bb3e0" : "#87ceeb")) : "#adb5bd"
                }
                GradientStop {
                    position: 1.0
                    color: enabled ? (modeComboBox.pressed ? "#357abd" : (modeComboBox.hovered ? "#4a90e2" : "#7bb3e0")) : "#868e96"
                }
            }

            Behavior on border.color {
                ColorAnimation { duration: 200 }
            }
        }

        contentItem: Text {
            text: modeComboBox.displayText
            font.pixelSize: root.standardFontSize
            font.family: root.standardFontFamily
            font.weight: root.standardFontWeight
            color: enabled ? "#2c5282" : "#6c757d"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 30
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            elide: Text.ElideRight
        }

        indicator: Canvas {
            x: modeComboBox.width - 18
            y: (modeComboBox.height - height) / 2
            width: 12
            height: 8
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.lineTo(width / 2, height);
                ctx.closePath();
                ctx.fillStyle = enabled ? "#2c5282" : "#6c757d";
                ctx.fill();
            }
        }

        popup: Popup {
            y: modeComboBox.height + 2
            width: modeComboBox.width
            height: contentItem.implicitHeight
            padding: 2
            margins: 0
           
            background: Rectangle {
                color: "#ffffff"
                border.color: Qt.rgba(0.4, 0.4, 0.4, 0.8)
                border.width: 1
                radius: 6
            }
           
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: modeComboBox.delegateModel
                currentIndex: modeComboBox.highlightedIndex
                spacing: 1
                ScrollIndicator.vertical: ScrollIndicator { }
            }
        }

        delegate: ItemDelegate {
            width: modeComboBox.width
            height: 35

            background: Rectangle {
                color: parent.hovered ? "#4c82afff" : "#ffffff"
                radius: 4
            }

            contentItem: Text {
                text: modelData
                color: parent.hovered ? "#ffffff" : "#000000"
                font.pixelSize: root.standardFontSize
                font.family: root.standardFontFamily
                font.weight: root.standardFontWeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }
        }

        onActivated: {
            modeChangeDialog.text = "Mode changed to: " + model[currentIndex]
            //console.log("Mode Changed to", model[currentIndex])
            droneCommander.setMode(model[currentIndex])
        }

        ToolTip.visible: hovered
        ToolTip.text: root.isConnected ? "Select flight mode" : "Connect to drone first"
        ToolTip.delay: 1000
    }
}
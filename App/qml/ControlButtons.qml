import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Row {
    id: controlsPanelRoot
    spacing: 10
    anchors.centerIn: parent
    
    property var mainWindowRef: null
    property var parametersWindowInstance: null
    property var navigationControlsWindowInstance: null
    property var pidTuningWindowInstance: null
    property var flightModeWindowInstance: null 
    property var userParamsWindowInstance: null
    clip: false

    Button {
        id: takeoffButton
        property bool isClicked: false
        text: languageManager ? languageManager.getText("TAKEOFF") : "TAKEOFF"
        width: 70
        height: 30
        flat: true
        background: Rectangle {
            color: takeoffButton.isClicked ? "green" : "#ADD8E6"
            radius: 4
            border.width: 0
        }
        contentItem: Text {
            text: parent.text
            color: takeoffButton.isClicked ? "white" : "black"
            font.family: "Consolas"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        hoverEnabled: false
        focusPolicy: Qt.NoFocus
        onClicked: {
            // ─── NFZ Safety Check ──────────────────────────────────────────────
            var lat = (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry)
                      ? (droneModel.telemetry.lat || 0) : 0
            var lon = (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry)
                      ? (droneModel.telemetry.lon || 0) : 0

            if (lat !== 0 && lon !== 0 &&
                typeof nfzManager !== "undefined" && nfzManager &&
                nfzManager.isDroneInNFZ(lat, lon)) {
                nfzTakeoffWarningDialog.open()
                return
            }
            // ──────────────────────────────────────────────────────────────────
            takeoffButton.isClicked = true
            landButton.isClicked = false
            rtlButton.isClicked = false
            settingsButton.isClicked = false
            tinariButton.isClicked = false
            altitudeSpeedDialog.open()
        }
    }

    Button {
        id: landButton
        property bool isClicked: false
        text: languageManager ? languageManager.getText("LAND") : "LAND"
        width: 60
        height: 30
        flat: true
        background: Rectangle {
            color: landButton.isClicked ? "green" : "#ADD8E6"
            radius: 4
            border.width: 0
        }
        contentItem: Text {
            text: parent.text
            color: landButton.isClicked ? "white" : "black"
            font.family: "Consolas"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        hoverEnabled: false
        focusPolicy: Qt.NoFocus
        onClicked: {
            landButton.isClicked = true
            takeoffButton.isClicked = false
            rtlButton.isClicked = false
            settingsButton.isClicked = false
            tinariButton.isClicked = false
            if (droneCommander) droneCommander.land()
            else console.log("DroneCommander not set.");
        }
    }

    Button {
        id: rtlButton
        property bool isClicked: false
        text: languageManager ? languageManager.getText("RTL") : "RTL"
        width: 120
        height: 30
        flat: true
        background: Rectangle {
            color: rtlButton.isClicked ? "green" : "#ADD8E6"
            radius: 4
            border.width: 0
        }
        contentItem: Text {
            text: parent.text
            color: rtlButton.isClicked ? "white" : "black"
            font.family: "Consolas"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        hoverEnabled: false
        focusPolicy: Qt.NoFocus
        onClicked: {
            rtlButton.isClicked = true
            takeoffButton.isClicked = false
            landButton.isClicked = false
            settingsButton.isClicked = false
            tinariButton.isClicked = false
            if (droneCommander) droneCommander.setMode("RTL")
            else console.log("DroneCommander not set.");
        }
    }

    Button {
        id: settingsButton
        property bool isClicked: false
        text: languageManager ? languageManager.getText("SETTINGS") + " ▼" : "SETTINGS ▼"
        width: 150
        height: 30
        flat: true
        
        background: Rectangle {
            color: settingsButton.isClicked ? "green" : "#ADD8E6"
            radius: 4
            border.width: 0
        }
        
        contentItem: Text {
            text: parent.text
            color: settingsButton.isClicked ? "white" : "black"
            font.family: "Consolas"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        
        hoverEnabled: false
        focusPolicy: Qt.NoFocus
        onClicked: {
            settingsButton.isClicked = true
            takeoffButton.isClicked = false
            landButton.isClicked = false
            rtlButton.isClicked = false
            tinariButton.isClicked = false
            settingsMenu.open()
        }

        Menu {
            id: settingsMenu
            y: -implicitHeight - 2
            width: settingsButton.width
            padding: 4
            enter: Transition {}
            exit: Transition {}
            
            background: Rectangle {
                color: "#1e1e1e"
                border.color: "#4CAF50"
                border.width: 1
                radius: 6
                clip: true
            }

            // ── Waypoints ──────────────────────────────────────────
            MenuItem {
                id: waypointsMenuItem
                property bool isClicked: false
                text: languageManager ? languageManager.getText("Waypoints") : "Waypoints"
                width: settingsButton.width
                height: 35
                ToolTip.visible: false

                background: Rectangle {
                    color: parent.hovered ? "#4CAF50" : "transparent"
                    radius: 4
                }

                contentItem: Text {
                    text: waypointsMenuItem.text
                    color: "#ffffff"
                    font.family: "Consolas"
                    font.pixelSize: 16
                    font.bold: waypointsMenuItem.isClicked
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.NativeRendering
                }

                onTriggered: {
                    waypointsMenuItem.isClicked = true
                    parametersMenuItem.isClicked = false
                    
                    if (mainWindowRef) {
                        if (!mainWindowRef.navigationControlsWindowInstance) {
                            var c = Qt.createComponent("NavigationControls.qml")
                            if (c.status === Component.Ready) {
                                var w = c.createObject(mainWindowRef, {
                                    droneCommander: droneCommander,
                                    droneModel: droneModel,
                                    mainGcsWindow: mainWindowRef
                                })
                                if (w) {
                                    mainWindowRef.navigationControlsWindowInstance = w
                                    w.show()
                                } else {
                                    console.log("❌ Failed to create Waypoints window object.")
                                }
                            } else {
                                console.log("❌ Error loading NavigationControls.qml:", c.errorString())
                            }
                        } else {
                            if (mainWindowRef.navigationControlsWindowInstance) {
                                mainWindowRef.navigationControlsWindowInstance.droneCommander = droneCommander
                                mainWindowRef.navigationControlsWindowInstance.droneModel = droneModel
                                mainWindowRef.navigationControlsWindowInstance.show()
                                mainWindowRef.navigationControlsWindowInstance.raise()
                            } else {
                                console.log("⚠️ Waypoints window exists but is not valid.")
                            }
                        }
                    } else {
                        console.log("❌ mainWindowRef is undefined.")
                    }
                }
            }
MenuItem {
    id: flightModeMenuItem
    property bool isClicked: false
    text: languageManager ? languageManager.getText("Flight Mode") : "Flight Mode"
    width: settingsButton.width
    height: 35
    ToolTip.visible: false

    background: Rectangle {
        color: parent.hovered ? "#4CAF50" : "transparent"
        radius: 4
    }

    contentItem: Text {
        text: flightModeMenuItem.text
        color: "#ffffff"
        font.family: "Consolas"
        font.pixelSize: 16
        font.bold: flightModeMenuItem.isClicked || parent.hovered
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }

    onTriggered: {
        console.log("✈️ Flight Mode menu item triggered")

        if (mainWindowRef && !mainWindowRef.flightModeWindowInstance) {
            var c = Qt.createComponent("FlightMode.qml")
            if (c.status === Component.Ready) {
                var w = c.createObject(mainWindowRef, {
                    "droneCommander": droneCommander,
                    "droneModel":     droneModel
                })
                if (w) {
                    w.show()
                    mainWindowRef.flightModeWindowInstance = w
                    console.log("✅ Flight Mode window opened")
                } else {
                    console.log("❌ Failed to create Flight Mode window")
                }
            } else if (c.status === Component.Error) {
                console.log("❌ Error loading FlightMode.qml:", c.errorString())
            }
        } else if (mainWindowRef && mainWindowRef.flightModeWindowInstance) {
            mainWindowRef.flightModeWindowInstance.droneCommander = droneCommander
            mainWindowRef.flightModeWindowInstance.droneModel = droneModel
            mainWindowRef.flightModeWindowInstance.show()
            mainWindowRef.flightModeWindowInstance.raise()
        } else {
            console.log("❌ mainWindowRef not set")
        }
    }
}
            // ── PID Tuning ─────────────────────────────────────────
            MenuItem {
                id: pidTuningMenuItem
                property bool isClicked: false
                text: languageManager ? languageManager.getText("PID_TUNING") : "PID Tuning"
                width: settingsButton.width
                height: 35
                ToolTip.visible: false

                background: Rectangle {
                    color: parent.hovered ? "#4CAF50" : "transparent"
                    radius: 4
                }

                contentItem: Text {
                    text: pidTuningMenuItem.text
                    color: "#ffffff"
                    font.family: "Consolas"
                    font.pixelSize: 16
                    font.bold: pidTuningMenuItem.isClicked || parent.hovered
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.NativeRendering
                }

                onTriggered: {
                    console.log("🎛 PID Tuning menu item triggered")

                    if (typeof droneModel === 'undefined' || !droneModel.isConnected) {
                        console.log("❌ Drone not connected - cannot open PID Tuning")
                        var errorDialog = Qt.createQmlObject('
                            import QtQuick 2.15
                            import QtQuick.Controls 2.15
                            Dialog {
                                title: "Connection Required"
                                modal: true
                                standardButtons: Dialog.Close
                                Label {
                                    text: "Please connect to the drone before opening PID Tuning."
                                    wrapMode: Text.WordWrap
                                }
                                onRejected: destroy()
                            }
                        ', mainWindowRef)
                        errorDialog.open()
                        return
                    }

                    var actualDroneCommander = droneModel.droneCommander
                    if (!actualDroneCommander) {
                        console.log("❌ DroneCommander not ready")
                        return
                    }

                    if (mainWindowRef && !mainWindowRef.pidTuningWindowInstance) {
                        var c = Qt.createComponent("PIDTuning.qml")
                        if (c.status === Component.Ready) {
                            var w = c.createObject(mainWindowRef, {
                                "droneCommander": actualDroneCommander,
                                "droneModel": droneModel
                            })
                            if (w) {
                                w.visible = true
                                mainWindowRef.pidTuningWindowInstance = w
                                console.log("✅ PID Tuning window opened")
                            } else {
                                console.log("❌ Failed to create PID Tuning window")
                            }
                        }
                    } else if (mainWindowRef && mainWindowRef.pidTuningWindowInstance) {
                        mainWindowRef.pidTuningWindowInstance.droneCommander = actualDroneCommander
                        mainWindowRef.pidTuningWindowInstance.droneModel = droneModel
                        mainWindowRef.pidTuningWindowInstance.visible = true
                    }
                }
            }

            // ── Parameters ─────────────────────────────────────────
            MenuItem {
                id: parametersMenuItem
                property bool isClicked: false
                text: languageManager ? languageManager.getText("Parameters") : "Parameters"
                width: settingsButton.width
                height: 35
                ToolTip.visible: false

                background: Rectangle {
                    color: parent.hovered ? "#4CAF50" : "transparent"
                    radius: 4
                }

                contentItem: Text {
                    text: parametersMenuItem.text
                    color: "#ffffff"
                    font.family: "Consolas"
                    font.pixelSize: 16
                    font.bold: parametersMenuItem.isClicked || parent.hovered
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.NativeRendering
                }

                onTriggered: {
                    console.log("📋 Parameters menu item triggered")
                    
                    if (typeof droneModel === 'undefined' || !droneModel.isConnected) {
                        console.log("❌ Drone not connected - cannot open Parameters")
                        if (typeof messageLogger !== 'undefined') {
                            messageLogger.logMessage("❌ Connect to drone before opening Parameters", "error")
                        }
                        var errorDialog = Qt.createQmlObject('
                            import QtQuick 2.15
                            import QtQuick.Controls 2.15
                            Dialog {
                                title: "Connection Required"
                                modal: true
                                x: (parent.width - width) / 2   
                                y: (parent.height - height) / 2
                                standardButtons: Dialog.Close   
                                Label {
                                    text: "Please connect to the drone before opening Parameters window."
                                    wrapMode: Text.WordWrap
                                }
                                onRejected: destroy()
                            }
                        ', mainWindowRef)
                        errorDialog.open()
                        return
                    }
                    
                    console.log("✅ Drone is connected")
                    
                    if (typeof droneCommander === 'undefined' || droneCommander === null) {
                        console.log("❌ droneCommander not available")
                        if (typeof messageLogger !== 'undefined') {
                            messageLogger.logMessage("❌ DroneCommander not available - try reconnecting", "error")
                        }
                        var errorDialog2 = Qt.createQmlObject('
                            import QtQuick 2.15
                            import QtQuick.Controls 2.15
                            Dialog {
                                title: "Not Ready"
                                modal: true
                                x: (parent.width - width) / 2
                                y: (parent.height - height) / 2
                                standardButtons: Dialog.Close
                                Label {
                                    text: "DroneCommander not ready. Please wait a moment after connecting."
                                    wrapMode: Text.WordWrap
                                }
                                onRejected: destroy()
                            }
                        ', mainWindowRef)
                        errorDialog2.open()
                        return
                    }
                    
                    console.log("✅ droneCommander available:", droneCommander)
                    
                    var actualDroneCommander = droneModel.droneCommander
                    if (actualDroneCommander === null || typeof actualDroneCommander === 'undefined') {
                        console.log("❌ droneModel.droneCommander is null")
                        if (typeof messageLogger !== 'undefined') {
                            messageLogger.logMessage("❌ DroneCommander not initialized - reconnect drone", "error")
                        }
                        return
                    }
                    
                    console.log("✅ Got droneCommander from droneModel:", actualDroneCommander)
                    
                    if (mainWindowRef && !mainWindowRef.parametersWindowInstance) {
                        console.log("📋 Creating new Parameters window...")
                        var c = Qt.createComponent("Parameters.qml")
                        if (c.status === Component.Ready) {
                            console.log("✅ Parameters.qml component ready")
                            var w = c.createObject(mainWindowRef, {
                                "droneCommander": actualDroneCommander,
                                "droneModel": droneModel
                            })
                            if (w) {
                                console.log("✅ Parameters window created successfully")
                                w.show()
                                mainWindowRef.parametersWindowInstance = w
                                if (typeof messageLogger !== 'undefined') {
                                    messageLogger.logMessage("📋 Parameters window opened", "info")
                                }
                            } else {
                                console.log("❌ Failed to create Parameters window object")
                            }
                        } else if (c.status === Component.Error) {
                            console.log("❌ Error loading Parameters.qml:", c.errorString())
                        } else {
                            console.log("⏳ Parameters.qml loading...")
                        }
                    } else if (mainWindowRef && mainWindowRef.parametersWindowInstance) {
                        console.log("📋 Parameters window already exists - showing it")
                        mainWindowRef.parametersWindowInstance.droneCommander = actualDroneCommander
                        mainWindowRef.parametersWindowInstance.droneModel = droneModel
                        mainWindowRef.parametersWindowInstance.visible = true
                        mainWindowRef.parametersWindowInstance.raise()
                    } else {
                        console.log("❌ mainWindowRef not set")
                    }
                }
            }

            // ── User Params ────────────────────────────────────────
            MenuItem {
                id: userParamsMenuItem
                property bool isClicked: false
                property var windowInstance: null
                text: languageManager ? languageManager.getText("User Params") : "User Params"
                width: settingsButton.width
                height: 35
                ToolTip.visible: false

                background: Rectangle {
                    color: parent.hovered ? "#4CAF50" : "transparent"
                    radius: 4
                }

                contentItem: Text {
                    text: userParamsMenuItem.text
                    color: "#ffffff"
                    font.family: "Consolas"
                    font.pixelSize: 16
                    font.bold: userParamsMenuItem.isClicked || parent.hovered
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.NativeRendering
                }

                onTriggered: {
                    console.log("📋 User Params menu item triggered")
                    
                    if (typeof droneModel === 'undefined' || !droneModel.isConnected) {
                        console.log("❌ Drone not connected - cannot open User Params")
                        var errorDialog = Qt.createQmlObject('\
                            import QtQuick 2.15\n\
                            import QtQuick.Controls 2.15\n\
                            Dialog {\n\
                                title: "Connection Required"\n\
                                modal: true\n\
                                x: (parent.width - width) / 2\n\
                                y: (parent.height - height) / 2\n\
                                standardButtons: Dialog.Close\n\
                                Label {\n\
                                    text: "Please connect to the drone before opening User Params window."\n\
                                    wrapMode: Text.WordWrap\n\
                                }\n\
                                onRejected: destroy()\n\
                            }\n\
                        ', mainWindowRef)
                        errorDialog.open()
                        return
                    }
                    
                    var actualDroneCommander = droneModel.droneCommander
                    if (actualDroneCommander === null || typeof actualDroneCommander === 'undefined') {
                        console.log("❌ droneModel.droneCommander is null")
                        return
                    }
                    
                    if (!userParamsMenuItem.windowInstance) {
                        console.log("📋 Creating new User Params window...")
                        var c = Qt.createComponent("UserParams.qml")
                        if (c.status === Component.Ready) {
                            var w = c.createObject(mainWindowRef, {
                                "droneCommander": actualDroneCommander,
                                "droneModel": droneModel
                            })
                            if (w) {
                                w.show()
                                userParamsMenuItem.windowInstance = w
                            }
                        }
                    } else if (userParamsMenuItem.windowInstance) {
                        userParamsMenuItem.windowInstance.droneCommander = actualDroneCommander
                        userParamsMenuItem.windowInstance.droneModel = droneModel
                        userParamsMenuItem.windowInstance.visible = true
                        userParamsMenuItem.windowInstance.raise()
                    }
                }
            }
        }
    }

    Button {
        id: tinariButton
        property bool isClicked: false
        text: languageManager ? languageManager.getText("Ti-NARI") : "Ti-NARI"
        width: 80
        height: 30
        flat: true
        background: Rectangle {
            color: tinariButton.isClicked ? "green" : "#ADD8E6"
            radius: 4
            border.width: 0
        }
        contentItem: Text {
            text: parent.text
            color: tinariButton.isClicked ? "white" : "black"
            font.family: "Consolas"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        hoverEnabled: false
        focusPolicy: Qt.NoFocus
        
        property var tinariWindowInstance: null
        
        onClicked: {
            if (!tinariWindowInstance) {
                var component = Qt.createComponent("TiNariWindow.qml")
                if (component.status === Component.Ready) {
                    tinariWindowInstance = component.createObject(null, {
                        "portDetector": portDetector,
                        "messageLogger": messageLogger
                    })
                    if (tinariWindowInstance) {
                        isClicked = true
                        console.log("✅ Ti-NARI window opened successfully")
                        tinariWindowInstance.closing.connect(function() {
                            isClicked = false
                            tinariWindowInstance.destroy()
                            tinariWindowInstance = null
                            console.log("🔒 Ti-NARI window closed")
                        })
                    } else {
                        console.error("❌ Failed to create Ti-NARI window instance")
                    }
                } else if (component.status === Component.Error) {
                    console.error("❌ Error loading Ti-NARI window:", component.errorString())
                } else {
                    console.log("⏳ Ti-NARI window loading...")
                }
            } else {
                tinariWindowInstance.raise()
                tinariWindowInstance.requestActivate()
            }
        }
        
        Connections {
            target: tinariButton.tinariWindowInstance
            function onVisibleChanged() {
                if (tinariButton.tinariWindowInstance && !tinariButton.tinariWindowInstance.visible) {
                    tinariButton.isClicked = false
                }
            }
        }
    }

    Button {
        id: levelButton
        property bool isClicked: false
        text: languageManager ? languageManager.getText("LEVEL") : "LEVEL"
        width: 60
        height: 30
        flat: true
        background: Rectangle {
            color: levelButton.isClicked ? "green" : "#32CD32"
            radius: 4
            border.width: 0
        }
        contentItem: Text {
            text: parent.text
            color: "white"
            font.family: "Consolas"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        hoverEnabled: false
        focusPolicy: Qt.NoFocus
        onClicked: {
            levelButton.isClicked = !levelButton.isClicked
            droneModel.triggerLevelCalibration()
            console.log("Drone Leveled")
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ALTITUDE DIALOG  (climb speed hardcoded to 1.5 m/s)
    // ═══════════════════════════════════════════════════════════
    Dialog {
        id: altitudeSpeedDialog
        width: 450
        height: 360
        parent: ApplicationWindow.overlay
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnEscape

        Overlay.modal: Rectangle {
            color: "#80000000"
        }

        background: Rectangle {
            color: "#ffffff"
            radius: 12
            border.width: 0

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: "transparent"
                border.color: "#20000000"
                border.width: 1
                radius: parent.radius + 2
                z: -1
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                color: "transparent"
                border.color: "#10000000"
                border.width: 1
                radius: parent.radius + 4
                z: -2
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            // Header section
            Rectangle {
                width: parent.width
                height: 60
                color: "#f8f9fa"
                radius: 12

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.radius
                    color: parent.color
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        width: 32
                        height: 32
                        color: "#4A90E2"
                        radius: 16

                        Text {
                            anchors.centerIn: parent
                            text: "✈"
                            font.family: "Consolas"
                            font.pixelSize: 16
                            color: "white"
                        }
                    }

                    Text {
                        text: languageManager ? languageManager.getText("Automated Takeoff") : "Automated Takeoff"
                        font.family: "Consolas"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: "#2c3e50"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Content section
            Item {
                width: parent.width
                height: parent.height - 60 - 80

                Column {
                    anchors.centerIn: parent
                    spacing: 16
                    width: parent.width - 60

                    Text {
                        text: languageManager ? languageManager.getText("Configure takeoff parameters") : "Configure takeoff parameters"
                        font.family: "Consolas"
                        font.pixelSize: 14
                        color: "#5a6c7d"
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Altitude Input
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Text {
                            text: languageManager ? languageManager.getText("Target Altitude (meters)") : "Target Altitude (meters)"
                            font.family: "Consolas"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: "#34495e"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Rectangle {
                            width: 200
                            height: 45
                            color: "#ffffff"
                            border.color: altitudeInput.activeFocus ? "#4A90E2" : "#e1e8ed"
                            border.width: 2
                            radius: 8
                            anchors.horizontalCenter: parent.horizontalCenter

                            TextField {
                                id: altitudeInput
                                anchors.fill: parent
                                anchors.margins: 2
                                text: "10"
                                placeholderText: "Enter altitude..."
                                font.family: "Consolas"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                horizontalAlignment: TextInput.AlignHCenter
                                color: "#2c3e50"

                                validator: DoubleValidator {
                                    bottom: 1.0
                                    top: 500.0
                                    decimals: 1
                                }

                                background: Rectangle {
                                    color: "transparent"
                                }

                                Keys.onReturnPressed: {
                                    if (startTakeoffButton.enabled) {
                                        startTakeoffButton.clicked()
                                    }
                                }
                            }
                        }

                        Text {
                            text: languageManager ? languageManager.getText("Range: 1.0 - 500.0 m") : "Range: 1.0 - 500.0 m"
                            font.family: "Consolas"
                            font.pixelSize: 11
                            color: "#95a5a6"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    // Info message
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: "#e8f5e9"
                        radius: 6
                        border.color: "#4CAF50"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "🤖 Auto: ARM → GUIDED → TAKEOFF  |  Climb: 1.5 m/s"
                            font.family: "Consolas"
                            font.pixelSize: 12
                            color: "#2e7d32"
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            // Footer with buttons
            Rectangle {
                width: parent.width
                height: 80
                color: "#ffffff"

                Rectangle {
                    width: parent.width - 40
                    height: 1
                    color: "#ecf0f1"
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 15

                    Button {
                        text: languageManager ? languageManager.getText("Cancel") : "Cancel"
                        width: 100
                        height: 40

                        background: Rectangle {
                            color: parent.hovered ? "#e74c3c" : "#ecf0f1"
                            radius: 8
                            border.width: 0
                        }

                        contentItem: Text {
                            text: parent.text
                            color: parent.hovered ? "white" : "#7f8c8d"
                            font.family: "Consolas"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        hoverEnabled: true
                        onClicked: altitudeSpeedDialog.close()
                    }

                    Button {
                        id: startTakeoffButton
                        text: languageManager ? languageManager.getText("Start Takeoff") : "Start Takeoff"
                        width: 140
                        height: 40
                        enabled: altitudeInput.text !== "" && altitudeInput.acceptableInput

                        background: Rectangle {
                            color: {
                                if (!parent.enabled) return "#bdc3c7"
                                return parent.hovered ? "#27ae60" : "#2ecc71"
                            }
                            radius: 8
                            border.width: 0
                        }

                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? "white" : "#95a5a6"
                            font.family: "Consolas"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        hoverEnabled: true

                        onClicked: {
                            var altitude = parseFloat(altitudeInput.text)
                            var speed = 1.5   // hardcoded default climb speed

                            // ─── NFZ Safety Check (second gate) ───────────────
                            var lat2 = (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry)
                                       ? (droneModel.telemetry.lat || 0) : 0
                            var lon2 = (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry)
                                       ? (droneModel.telemetry.lon || 0) : 0

                            if (lat2 !== 0 && lon2 !== 0 &&
                                typeof nfzManager !== "undefined" && nfzManager &&
                                nfzManager.isDroneInNFZ(lat2, lon2)) {
                                altitudeSpeedDialog.close()
                                nfzTakeoffWarningDialog.open()
                                return
                            }
                            // ──────────────────────────────────────────────────

                            console.log("🚁 Starting automated takeoff:")
                            console.log("  - Altitude:", altitude, "m")
                            console.log("  - Speed:", speed, "m/s (default)")
                            console.log("  - altitude isNaN:", isNaN(altitude))
                            console.log("  - droneCommander exists:", droneCommander !== undefined && droneCommander !== null)

                            if (!isNaN(altitude) && altitude > 0) {
                                if (droneCommander) {
                                    try {
                                        console.log("📞 Calling droneCommander.takeoff(" + altitude + ", " + speed + ")")
                                        var result = droneCommander.takeoff(altitude, speed)
                                        console.log("✅ Takeoff command result:", result)
                                    } catch (error) {
                                        console.log("❌ Error calling takeoff:", error)
                                        console.log("❌ Error details:", JSON.stringify(error))
                                    }
                                } else {
                                    console.log("❌ DroneCommander not set for takeoff.")
                                }
                                altitudeSpeedDialog.close()
                            } else {
                                console.log("❌ Invalid altitude value:", altitude)
                            }
                        }
                    }
                }
            }
        }

        onOpened: {
            altitudeInput.forceActiveFocus()
            altitudeInput.selectAll()
        }
    }

    // ═══════════════════════════════════════════════════════════
    // NFZ TAKEOFF WARNING DIALOG
    // ═══════════════════════════════════════════════════════════
    Dialog {
        id: nfzTakeoffWarningDialog
        width: 420
        height: 280
        parent: ApplicationWindow.overlay
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle {
            color: "#cc000000"
        }

        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
            border.color: "#e74c3c"
            border.width: 2
        }

        Rectangle {
            id: nfzWarningHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 64
            color: "#e74c3c"
            radius: 10

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.radius
                color: parent.color
            }

            Row {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    text: "⛔"
                    font.pixelSize: 28
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "NO FLY ZONE DETECTED"
                    font.family: "Consolas"
                    font.pixelSize: 18
                    font.bold: true
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Column {
            anchors.top: nfzWarningHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
            spacing: 18

            Text {
                width: parent.width
                text: "🚁 Takeoff is BLOCKED!"
                font.family: "Consolas"
                font.pixelSize: 15
                font.bold: true
                color: "#e74c3c"
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "The drone is currently located inside a\nNo Fly Zone (NFZ) area.\n\nTakeoff is not permitted from this location."
                font.family: "Consolas"
                font.pixelSize: 13
                color: "#cccccc"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
                wrapMode: Text.WordWrap
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 140
                height: 40
                text: "OK — I Understand"

                background: Rectangle {
                    color: parent.hovered ? "#c0392b" : "#e74c3c"
                    radius: 8
                }
                contentItem: Text {
                    text: parent.text
                    font.family: "Consolas"
                    font.pixelSize: 13
                    font.bold: true
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                hoverEnabled: true
                onClicked: nfzTakeoffWarningDialog.close()
            }
        }
    }
}

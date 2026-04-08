import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10

Rectangle {
    id: root
    height: 80
    color: "#fcfcfcff"
    border.color: "#fffefeff"
    border.width: 2

    property bool showConnectButton: true
    property var calibrationWindow: null

    // Enhanced connection state properties
    property bool isConnected: droneModel ? droneModel.isConnected : false
    property bool isReconnecting: false
    property bool autoReconnectEnabled: true
    property int  reconnectionAttempts: 0
    property var  languageManager: null
    property bool isAutoConnecting: false   // true while AUTO scan is running
    property bool hotplugTriggered: false   // true when scan was started by USB hotplug

    // Track popup open time for minimum display duration
    property real popupOpenTime: 0

    // Font properties
    readonly property string standardFontFamily: "Consolas"
    readonly property int    standardFontSize:   16
    readonly property int    standardFontWeight: Font.Bold

    // Signals
    signal connectionStateChanged(bool connected)
    signal parametersRequested()
    signal parametersReceived(var parameters)

    // ─────────────────────────────────────────────────────────────────────────
    //  CONNECTION LOADING POPUP
    // ─────────────────────────────────────────────────────────────────────────
    Popup {
        id: connectionLoadingPopup
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        visible: false

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 400
        height: 300

        property string connectionString: ""
        property bool   isConnecting:     false
        property int    dotsCount:        0

        background: Rectangle {
            color: "#ffffff"
            radius: 16
            border.color: "#dee2e6"
            border.width: 2

            layer.enabled: true
            layer.effect: DropShadow {
                horizontalOffset: 0
                verticalOffset: 8
                radius: 16
                samples: 33
                color: "#40000000"
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 30
            width: parent.width - 60

            Rectangle {
                width: 80; height: 80; radius: 40
                color: "#e3f2fd"
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    anchors.centerIn: parent
                    text: "📡"
                    font.pixelSize: 40
                    RotationAnimation on rotation {
                        running: connectionLoadingPopup.isConnecting
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 2000
                    }
                }
            }

            Column {
                width: parent.width; spacing: 10
                Text {
                    width: parent.width
                    text: "Connecting to Drone"
                    font.pixelSize: 22; font.weight: Font.Bold; font.family: "Consolas"
                    color: "#212529"; horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: "Please wait" + ".".repeat(connectionLoadingPopup.dotsCount)
                    font.pixelSize: 16; font.family: "Consolas"
                    color: "#6c757d"; horizontalAlignment: Text.AlignHCenter
                }
            }

            Rectangle {
                width: parent.width; height: 60; radius: 8
                color: "#f8f9fa"; border.color: "#dee2e6"; border.width: 1
                Column {
                    anchors.centerIn: parent; spacing: 5
                    Text {
                        text: "Connection String:"
                        font.pixelSize: 12; font.family: "Consolas"
                        color: "#6c757d"; anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: connectionLoadingPopup.connectionString
                        font.pixelSize: 14; font.weight: Font.DemiBold; font.family: "Consolas"
                        color: "#0066cc"; anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 4; radius: 2; color: "#e9ecef"
                Rectangle {
                    id: progressBar
                    height: parent.height; radius: parent.radius
                    color: "#0066cc"; width: 0
                    SequentialAnimation on width {
                        running: connectionLoadingPopup.isConnecting
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: progressBar.parent.width; duration: 1500; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: progressBar.parent.width; to: 0;  duration: 1500; easing.type: Easing.InOutQuad }
                    }
                }
            }

            Button {
                width: 120; height: 35
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Cancel"
                background: Rectangle {
                    radius: 8
                    color: parent.pressed ? "#bd2130" : (parent.hovered ? "#c82333" : "#dc3545")
                    border.color: "#bd2130"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text
                    font.pixelSize: 14; font.weight: Font.DemiBold; font.family: "Consolas"
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    console.log("❌ Connection cancelled by user")
                    connectionLoadingPopup.isConnecting = false
                    if (root.isAutoConnecting) {
                        root.isAutoConnecting = false
                        if (typeof droneModel !== 'undefined') droneModel.cancelAutoConnect()
                    } else {
                        if (typeof droneModel !== 'undefined') droneModel.disconnectDrone()
                    }
                    connectionLoadingPopup.close()
                }
            }
        }

        Timer {
            id: dotsTimer
            interval: 500
            running: connectionLoadingPopup.isConnecting
            repeat: true
            onTriggered: { connectionLoadingPopup.dotsCount = (connectionLoadingPopup.dotsCount + 1) % 4 }
        }

        onOpened: {
            console.log("🔄 Loading popup OPENED")
            isConnecting = true; dotsCount = 0
            dotsTimer.restart()
            root.popupOpenTime = Date.now()
        }
        onClosed: {
            console.log("ℹ️ Loading popup CLOSED")
            isConnecting = false; dotsTimer.stop()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  POPUP HELPERS
    // ─────────────────────────────────────────────────────────────────────────
    function showConnectionLoading(connectionStr) {
        console.log("🔄 showConnectionLoading called with:", connectionStr)
        connectionLoadingPopup.connectionString = connectionStr
        connectionLoadingPopup.open()
    }

    function hideConnectionLoading() {
        console.log("ℹ️ hideConnectionLoading called")
        var elapsedTime = Date.now() - popupOpenTime
        var minimumDisplayTime = 1000
        if (elapsedTime < minimumDisplayTime) {
            var remainingTime = minimumDisplayTime - elapsedTime
            console.log("⏰ Delaying popup close by", remainingTime, "ms for visibility")
            var delayTimer = Qt.createQmlObject(
                'import QtQuick 2.15; Timer { interval: ' + remainingTime + '; running: true; repeat: false }',
                root, "delayTimer")
            delayTimer.triggered.connect(function() {
                console.log("✅ Closing loading popup (after minimum display time)")
                connectionLoadingPopup.close()
                delayTimer.destroy()
            })
        } else {
            console.log("✅ Closing loading popup immediately")
            connectionLoadingPopup.close()
        }
    }

    function showHotplugToast(portName) {
        hotplugSubtitle.text = portName ? portName + " — Device ready" : "Device ready"
        hotplugToast.opacity = 0
        hotplugToast.visible = true
        toastFadeIn.start()
        toastDismissTimer.restart()
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  CALIBRATION WINDOW LAUNCHERS
    // ─────────────────────────────────────────────────────────────────────────
    function _closeExistingCalibrationWindow() {
        if (root.calibrationWindow) {
            root.calibrationWindow.close()
            root.calibrationWindow = null
        }
    }

    function openAccelCalibration() {
        console.log("Opening AccelCalibration.qml...")
        _closeExistingCalibrationWindow()
        var component = Qt.createComponent("AccelCalibration.qml")
        if (component.status === Component.Ready) {
            root.calibrationWindow = component.createObject(null, {
                "calibrationModel": calibrationModel,
                "languageManager": root.languageManager
            })
            if (root.calibrationWindow) {
                root.calibrationWindow.closing.connect(function() { root.calibrationWindow = null })
                root.calibrationWindow.show()
            }
        } else if (component.status === Component.Error) {
            console.log("❌ AccelCalibration load error:", component.errorString())
        }
    }

    function openESCCalibration() {
        if (!root.isConnected) return
        _closeExistingCalibrationWindow()
        var component = Qt.createComponent("esc_calibration.qml")
        if (component.status === Component.Ready) {
            root.calibrationWindow = component.createObject(null, {
                "droneModel":          droneModel,
                "droneCommander":      droneCommander,
                "escCalibrationModel": escCalibrationModel,
                 "languageManager": root.languageManager
            })
            if (root.calibrationWindow) {
                root.calibrationWindow.closing.connect(function() { root.calibrationWindow = null })
                root.calibrationWindow.show()
            }
        } else if (component.status === Component.Error) {
            console.log("❌ ESC Calibration load error:", component.errorString())
        }
    }

    function openRadioCalibration() {
        if (!root.isConnected) return
        _closeExistingCalibrationWindow()
        var component = Qt.createComponent("radio.qml")
        if (component.status === Component.Ready) {
            root.calibrationWindow = component.createObject(null, {
                "radioCalibrationModel": radioCalibrationModel,
                 "languageManager": root.languageManager
            })
            if (root.calibrationWindow) {
                root.calibrationWindow.closing.connect(function() { root.calibrationWindow = null })
                root.calibrationWindow.show()
            }
        } else if (component.status === Component.Error) {
            console.log("❌ Radio Calibration load error:", component.errorString())
        }
    }

    function openCompassCalibration() {
        if (!root.isConnected) {
            console.log("⚠️ Cannot open compass calibration - drone not connected")
            return
        }
        console.log("🧭 Opening compass calibration window...")
        _closeExistingCalibrationWindow()

        var component = Qt.createComponent("compass.qml")

        // FIX: handle asynchronous component loading (e.g. if QML engine hasn't
        //      compiled compass.qml yet) to avoid silent failures
        if (component.status === Component.Loading) {
            component.statusChanged.connect(function() {
                if (component.status === Component.Ready) {
                    _createCompassWindow(component)
                } else if (component.status === Component.Error) {
                    console.log("❌ compass.qml load error:", component.errorString())
                }
            })
        } else if (component.status === Component.Ready) {
            _createCompassWindow(component)
        } else {
            console.log("❌ compass.qml failed to load:", component.errorString())
        }
    }

    function _createCompassWindow(component) {
        root.calibrationWindow = component.createObject(null, {
            "compassCalibrationModel": compassCalibrationModel,
            "droneModel":              droneModel,
            "droneCommander":          droneCommander,
             "languageManager": root.languageManager
        })
        if (root.calibrationWindow) {
            root.calibrationWindow.closing.connect(function() { root.calibrationWindow = null })
            root.calibrationWindow.show()
            console.log("✅ Compass calibration window opened")
        } else {
            console.log("❌ Failed to create compass calibration window instance")
        }
    }

    function addCustomConnection(connectionString) {
        for (let i = 0; i < portModel.count; i++) {
            if (portModel.get(i).port === connectionString) {
                portSelector.currentIndex = i
                connectionStringInput.text = ""
                return
            }
        }
        const customId = "custom-" + Math.random().toString(36).substring(2, 8)
        portModel.append({ id: customId, port: connectionString, display: "Custom (" + connectionString + ")" })
        portSelector.currentIndex = portModel.count - 1
        connectionStringInput.text = ""
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  SIGNAL CONNECTIONS
    // ─────────────────────────────────────────────────────────────────────────
    Connections {
        target: droneModel
        function onIsConnectedChanged() {
            root.isConnected = droneModel.isConnected
            root.isAutoConnecting = false   // scan is over (success or fail)
            root.connectionStateChanged(root.isConnected)

            if (root.isConnected) {
                console.log("✅ Connection successful - hiding loading popup")
                root.hideConnectionLoading()
            } else {
                console.log("❌ Connection failed/disconnected - hiding loading popup")
                root.hideConnectionLoading()
            }

            if (root.isConnected && calibrationModel) {
                if (droneModel.current_connection_string) {
                    console.log("Storing connection info:", droneModel.current_connection_string)
                }
            }
        }
    }

    // ── Auto-connect signal handlers ─────────────────────────────────────────
    Connections {
        target: droneModel

        // Live progress: update the subtitle text in the loading popup
        function onAutoConnectProgress(msg) {
            connectionLoadingPopup.connectionString = msg
        }

        // Worker found a device → connectToDrone() is called automatically;
        // update the popup text so the user sees the found port
        function onAutoConnectFound(port, baud) {
            console.log("🎯 AUTO: device found on", port, "@", baud)
            connectionLoadingPopup.connectionString = "✅ Found: " + port + " @ " + baud + " baud"
        }

        // Scan finished with nothing found → close popup
        function onAutoConnectFailed() {
            console.log("❌ AUTO: no MAVLink device found")
            root.isAutoConnecting = false
            root.hotplugTriggered = false
            root.hideConnectionLoading()
        }

        // USB device plugged in → show toast + open loading popup automatically
        function onAutoConnectHotplug(port) {
            console.log("🔌 USB hotplug event on", port)
            root.hotplugTriggered = true
            root.showHotplugToast(port)
        }
    }



    Connections {
        target: droneCommander
        function onParametersUpdated(parameters) {
            root.parametersReceived(parameters)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  BOTTOM ACCENT LINE
    // ─────────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -5
        width: parent.width; height: 3
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#0066cc" }
            GradientStop { position: 0.5; color: "#28a745" }
            GradientStop { position: 1.0; color: "#17a2b8" }
        }
        opacity: 0.8
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  USB HOTPLUG TOAST  (Mission Planner-style USB arrival notification)
    // ─────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: hotplugToast
        visible: false
        opacity: 0
        width: 300
        height: 50
        radius: 12
        color: "#1a1a2e"
        border.color: "#0066cc"
        border.width: 2
        z: 9999

        // Float above the bar at top-centre
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 6

        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 4
            radius: 14
            samples: 29
            color: "#700066cc"
        }

        Row {
            anchors.centerIn: parent
            spacing: 10

            Text {
                text: "🔌"
                font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: "USB Device Detected"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.family: "Consolas"
                    color: "#ffffff"
                }

                Text {
                    id: hotplugSubtitle
                    text: "Ready to connect"
                    font.pixelSize: 11
                    font.family: "Consolas"
                    color: "#87ceeb"
                }
            }
        }

        NumberAnimation {
            id: toastFadeIn
            target: hotplugToast
            property: "opacity"
            from: 0; to: 1
            duration: 250
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            id: toastFadeOut
            target: hotplugToast
            property: "opacity"
            from: 1; to: 0
            duration: 400
            easing.type: Easing.InQuad
            onStopped: hotplugToast.visible = false
        }

        Timer {
            id: toastDismissTimer
            interval: 3500
            repeat: false
            onTriggered: toastFadeOut.start()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  MAIN UI ROW
    // ─────────────────────────────────────────────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 25
        spacing: 15

        // ── Port selector ──────────────────────────────────────────────────
        ComboBox {
            id: portSelector
            width: 200; height: 40
            model: ListModel { id: portModel }
            property var selectedPort: portModel.count > 0 && currentIndex >= 0
                                       ? portModel.get(currentIndex) : null

            background: Rectangle {
                radius: 8
                border.color: portSelector.activeFocus ? "#4a90e2" : "#e0e0e0"
                border.width: portSelector.activeFocus ? 2 : 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: portSelector.currentIndex >= 0 ? "#b8dff0" : "#ffffff" }
                    GradientStop { position: 1.0; color: portSelector.currentIndex >= 0 ? "#9dd0e6" : "#f0f8ff" }
                }
            }

            contentItem: Text {
                text: (portSelector.currentIndex >= 0 && portSelector.currentIndex < portModel.count)
                      ? portModel.get(portSelector.currentIndex).display
                      : "Select Port"
                font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                font.weight: Font.Medium
                color: portSelector.currentIndex >= 0 ? "#2c3e50" : "#7f8c8d"
                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                clip: true; leftPadding: 12; rightPadding: 35
            }

            delegate: ItemDelegate {
                width: portSelector.width; height: 38
                ToolTip.visible: false
                background: Rectangle {
                    color: parent.pressed ? "#5a9fd4" : (parent.hovered ? "#87ceeb" : "transparent"); radius: 4
                }
                contentItem: Text {
                    text: model.display
                    color: (parent.pressed || parent.hovered) ? "#ffffff" : "#2c3e50"
                    font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; leftPadding: 12
                }
                onClicked: { portSelector.currentIndex = index; portSelector.popup.close() }
            }

            popup: Popup {
                y: portSelector.height
                width: portSelector.width
                implicitHeight: contentItem.implicitHeight + 2
                padding: 1
                enter: Transition {}
                exit: Transition {}
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: portSelector.popup.visible ? portSelector.delegateModel : null
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
                background: Rectangle {
                    color: "#f0f8ff"
                    border.color: "#87ceeb"
                    border.width: 1
                    radius: 6
                    clip: true
                }
            }
        }

        // ── Custom connection string input ─────────────────────────────────
        Rectangle {
            id: connectionStringContainer
            width: 250; height: 40; radius: 10
            color: "#f8f9fa"
            border.color: connectionStringInput.activeFocus ? "#0066cc" : "#dee2e6"
            border.width: 2

            TextInput {
                id: connectionStringInput
                anchors.fill: parent
                anchors.leftMargin: 15; anchors.rightMargin: 15
                font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                color: "#212529"; verticalAlignment: Text.AlignVCenter
                selectByMouse: true; clip: true

                Text {
                    anchors.fill: parent
                    text: "Enter connection string..."
                    font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                    color: "#6c757d"; verticalAlignment: Text.AlignVCenter
                    visible: !connectionStringInput.text && !connectionStringInput.activeFocus
                }
            }
        }

        // ── Connect / Disconnect button ────────────────────────────────────
        Button {
            id: toggleConnectBtn
            visible: showConnectButton
            text: {
                if (isReconnecting) return "Reconnecting..."
                return languageManager
                    ? languageManager.getText(root.isConnected ? "DISCONNECT" : "CONNECT")
                    : (root.isConnected ? "DISCONNECT" : "CONNECT")
            }
            width: 290; height: 40
            enabled: !isReconnecting

            onClicked: {
                if (!root.isConnected) {
                    let connectionString = ""
                    let connectionId     = ""

                    if (connectionStringInput.text.trim() !== "") {
                        connectionString = connectionStringInput.text.trim()
                        connectionId     = "custom-" + Math.random().toString(36).substring(2, 8)
                    } else {
                        const sel = portSelector.selectedPort
                        if (sel) { connectionString = sel.port; connectionId = sel.id }
                    }

                    // ── AUTO DETECT branch ──────────────────────────────────
                    if (connectionString === "AUTO") {
                        console.log("🔍 AUTO DETECT: starting MAVLink scan…")
                        root.isAutoConnecting = true
                        root.showConnectionLoading("AUTO — Scanning ports…")
                        Qt.callLater(function() { droneModel.autoConnectMavlink() })
                        return
                    }

                    // ── Manual port branch ──────────────────────────────────
                    if (connectionString) {
                        console.log("🔌 CONNECTING to:", connectionId, connectionString)
                        root.showConnectionLoading(connectionString)
                        Qt.callLater(function() {
                            droneModel.current_connection_string = connectionString
                            droneModel.current_connection_id     = connectionId
                            droneModel.connectToDrone(connectionId, connectionString, 57600)
                        })
                    } else {
                        console.log("⚠️ No connection string provided")
                    }

                } else {
                    console.log("🔌 DISCONNECTING from drone...")
                    if (calibrationModel && typeof calibrationModel.disableAutoReconnect === 'function') {
                        try { calibrationModel.disableAutoReconnect() } catch (e) { console.log("⚠️ disableAutoReconnect:", e) }
                    }
                    if (droneModel && typeof droneModel.disconnectDrone === 'function') {
                        droneModel.disconnectDrone()
                    }
                }
            }

            background: Rectangle {
                radius: 10; border.width: 2
                border.color: isReconnecting ? "#ffc107"
                            : root.isConnected ? (toggleConnectBtn.pressed ? "#a71d2a" : "#dc3545")
                            : (toggleConnectBtn.pressed ? "#1e7e34" : "#28a745")
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: isReconnecting ? "#ffc107"
                             : root.isConnected
                               ? (toggleConnectBtn.pressed ? "#a71d2a" : toggleConnectBtn.hovered ? "#bd2130" : "#dc3545")
                               : (toggleConnectBtn.pressed ? "#1e7e34" : toggleConnectBtn.hovered ? "#218838" : "#28a745")
                    }
                    GradientStop {
                        position: 1.0
                        color: isReconnecting ? "#e0a800"
                             : root.isConnected
                               ? (toggleConnectBtn.pressed ? "#7f1d1d" : toggleConnectBtn.hovered ? "#a71d2a" : "#bd2130")
                               : (toggleConnectBtn.pressed ? "#155d27" : toggleConnectBtn.hovered ? "#1e7e34" : "#218838")
                    }
                }
            }
            contentItem: Text {
                text: toggleConnectBtn.text
                font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                font.weight: root.standardFontWeight; color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
        }

        // ── Calibration selector ───────────────────────────────────────────
        ComboBox {
            id: calibrationSelector
            width: 200; height: 40
            enabled: root.isConnected
            model: ListModel {
                ListElement { text: "🔧 Accelerometer";   value: 1 }
                ListElement { text: "🧭 Compass"; value: 2 }
                ListElement { text: "📻 Radio";   value: 3 }
                ListElement { text: "⚡ ESC";     value: 4 }
            }
            textRole: "text"
            currentIndex: -1
            displayText: "Calibrate"

            onActivated: function(index) {
                var selectedValue = model.get(index).value
                Qt.callLater(function() { calibrationSelector.currentIndex = -1 })
                if      (selectedValue === 1) root.openAccelCalibration()
                else if (selectedValue === 2) root.openCompassCalibration()
                else if (selectedValue === 3) root.openRadioCalibration()
                else if (selectedValue === 4) root.openESCCalibration()
            }

            background: Rectangle {
                radius: 10; border.width: 2
                border.color: enabled ? (calibrationSelector.pressed ? "#4a90e2" : "#87ceeb") : "#adb5bd"
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: enabled ? (calibrationSelector.pressed ? "#4a90e2"
                                        : calibrationSelector.hovered ? "#7bb3e0" : "#87ceeb") : "#adb5bd"
                    }
                    GradientStop {
                        position: 1.0
                        color: enabled ? (calibrationSelector.pressed ? "#357abd"
                                        : calibrationSelector.hovered ? "#4a90e2" : "#7bb3e0") : "#868e96"
                    }
                }
            }
            contentItem: Text {
                text: calibrationSelector.displayText
                font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                font.weight: root.standardFontWeight
                color: enabled ? "#2c5282" : "#6c757d"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
            delegate: ItemDelegate {
                width: calibrationSelector.width; height: 35
                ToolTip.visible: false
                background: Rectangle { color: parent.hovered ? "#4CAF50" : "transparent"; radius: 4 }
                contentItem: Text {
                    text: model.text
                    color: parent.hovered ? "#ffffff" : "#000000"
                    font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                }
                onClicked: { calibrationSelector.activated(index); calibrationSelector.popup.close() }
            }

            popup: Popup {
                y: calibrationSelector.height
                width: calibrationSelector.width
                implicitHeight: contentItem.implicitHeight + 2
                padding: 1
                enter: Transition {}
                exit: Transition {}
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: calibrationSelector.popup.visible ? calibrationSelector.delegateModel : null
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
                background: Rectangle {
                    color: "#ffffff"
                    border.color: "#87ceeb"
                    border.width: 1
                    radius: 6
                    clip: true
                }
            }
        }

        // ── Language selector ──────────────────────────────────────────────
        ComboBox {
            id: languageSelector
            width: 170; height: 40
            model: ["English", "हिंदी", "தமிழ்", "తెలుగు"]
            currentIndex: 0
            property var languageCodes: ["en", "hi", "ta", "te"]

            onCurrentIndexChanged: {
                if (languageManager) languageManager.changeLanguage(languageCodes[currentIndex])
            }

            background: Rectangle {
                radius: 10; border.width: 2
                border.color: enabled ? (languageSelector.pressed ? "#4a90e2" : "#87ceeb") : "#adb5bd"
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: enabled ? (languageSelector.pressed ? "#4a90e2"
                                        : languageSelector.hovered ? "#7bb3e0" : "#87ceeb") : "#adb5bd"
                    }
                    GradientStop {
                        position: 1.0
                        color: enabled ? (languageSelector.pressed ? "#357abd"
                                        : languageSelector.hovered ? "#4a90e2" : "#7bb3e0") : "#868e96"
                    }
                }
            }
            contentItem: Text {
                text: languageSelector.displayText
                font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                font.weight: root.standardFontWeight
                color: enabled ? "#2c5282" : "#6c757d"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
            delegate: ItemDelegate {
                width: languageSelector.width; height: 35
                ToolTip.visible: false
                background: Rectangle { color: parent.hovered ? "#4CAF50" : "transparent"; radius: 4 }
                contentItem: Text {
                    text: modelData; color: parent.hovered ? "#ffffff" : "#000000"
                    font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                }
                onClicked: { languageSelector.currentIndex = index; languageSelector.popup.close() }
            }

            popup: Popup {
                y: languageSelector.height
                width: languageSelector.width
                implicitHeight: contentItem.implicitHeight + 2
                padding: 1
                enter: Transition {}
                exit: Transition {}
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: languageSelector.popup.visible ? languageSelector.delegateModel : null
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
                background: Rectangle {
                    color: "#ffffff"
                    border.color: "#87ceeb"
                    border.width: 1
                    radius: 6
                    clip: true
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  LOGO
    // ─────────────────────────────────────────────────────────────────────────
    Item {
        id: logoContainer
        width: 120; height: 40
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 25

        Image {
            id: logoImage
            anchors.centerIn: parent
            width: 100; height: 40
            source: "../images/tihan.png"
            fillMode: Image.PreserveAspectFit
            smooth: true; antialiasing: true

            onStatusChanged: {
                if (status === Image.Error) console.log("Failed to load image from:", source)
                else if (status === Image.Ready) console.log("Successfully loaded image from:", source)
            }

            Text {
                anchors.centerIn: parent; text: "TIHAN FLY"
                color: "#0066cc"
                font.pixelSize: root.standardFontSize; font.family: root.standardFontFamily
                font.weight: root.standardFontWeight
                visible: logoImage.status !== Image.Ready
            }

            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                onEntered: logoImage.scale = 1.05
                onExited:  logoImage.scale = 1.0
                onClicked: {
                    var component = Qt.createComponent("AboutTihan.qml")
                    if (component.status === Component.Ready) {
                        var window = component.createObject(null)
                        window.show()
                    } else if (component.status === Component.Error) {
                        console.log("Error loading AboutTihan.qml:", component.errorString())
                    }
                }
            }

            Behavior on scale { NumberAnimation { duration: 200 } }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  INIT
    // ─────────────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        portModel.clear()

        // ── AUTO DETECT — always first so it's the default selection ─────────
        portModel.append({ id: "auto", port: "AUTO", display: "🔍 AUTO Detect" })

        // SITL second
        const sitlPort = "udp:127.0.0.1:14550"
        const randomId = "sitl-" + Math.random().toString(36).substring(2, 8)
        portModel.append({ id: randomId, port: sitlPort, display: "SITL (" + sitlPort + ")" })

        // Physical serial ports from portManager
        var ports = []
        if (typeof portManager !== 'undefined' && portManager !== null) {
            if (typeof portManager.availablePorts !== 'undefined') {
                ports = portManager.availablePorts
            } else if (typeof portManager.ports !== 'undefined') {
                ports = portManager.ports
            } else {
                console.log("⚠️ portManager found but no known ports property — scanning fallback disabled")
            }
        } else {
            console.log("⚠️ portManager not available at startup")
        }

        for (let i = 0; i < ports.length; ++i) {
            const p = ports[i]
            const portStr     = (typeof p === 'string') ? p : (p.port || p.portName || String(p))
            const displayStr  = (typeof p === 'string') ? p : (p.display || p.description || portStr)
            if (portStr !== sitlPort) {
                portModel.append({ id: "port-" + i, port: portStr, display: displayStr })
            }
        }

        portSelector.currentIndex = 0   // defaults to AUTO

        if (typeof portManager !== 'undefined' && typeof portManager.enableAutoReconnect === 'function') {
            portManager.enableAutoReconnect()
        }
    }

    Component.onDestruction: {
        if (root.calibrationWindow) {
            root.calibrationWindow.close()
            root.calibrationWindow = null
        }
    }
}

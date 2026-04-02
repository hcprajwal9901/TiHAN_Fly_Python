import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtPositioning 5.15

ApplicationWindow {
    id: simulationWindow
    visible: true
    flags: Qt.Window
    color: "#121212"
    title: "TiHAN FLY - Simulation Mode"
    width:  Math.min(Screen.width  * 0.95, 1920)
    height: Math.min(Screen.height * 0.95, 1080)
    minimumWidth: 1280
    minimumHeight: 720

    // ── SCREEN TOOLS ────────────────────────────────────────────────
    QtObject {
        id: screenTools
        readonly property real dpiScale:               Math.max(1.0, Math.min(Screen.pixelDensity / 160, 2.0))
        readonly property real defaultFontPixelHeight: 14 * dpiScale
        readonly property real defaultFontPixelWidth:  defaultFontPixelHeight * 0.55
        readonly property real smallFontPointSize:     defaultFontPixelHeight * 0.75
        readonly property real mediumFontPointSize:    defaultFontPixelHeight * 0.85
        readonly property real largeFontPointSize:     defaultFontPixelHeight
        readonly property real toolbarHeight:          defaultFontPixelHeight * 3
        readonly property real defaultSpacing:         defaultFontPixelHeight * 0.5
        readonly property real smallSpacing:           defaultFontPixelHeight * 0.25
        readonly property real largeSpacing:           defaultFontPixelHeight
        readonly property real defaultMargins:         defaultFontPixelHeight * 0.5
        readonly property real smallMargins:           defaultFontPixelHeight * 0.25
        readonly property real defaultRadius:          defaultFontPixelHeight * 0.5
    }

    // ── LIVE TELEMETRY ───────────────────────────────────────────────
    property var    telem:          droneModel.telemetry
    property real   droneHeading:   telem ? telem.heading             : 0
    property real   currentYaw:     telem ? telem.yaw                 : 0
    property real   liveAlt:        telem ? telem.rel_alt             : 0
    property real   liveSpeed:      telem ? telem.groundspeed         : 0
    property real   liveClimb:      telem ? telem.climb_rate          : 0
    property int    batteryPercent: telem ? Math.round(telem.battery_remaining) : 100
    property string droneMode:      telem ? telem.mode                : "READY"
    property bool   droneArmed:     telem ? telem.armed               : false
    property real   droneLat:       telem ? telem.lat                 : homeLat
    property real   droneLon:       telem ? telem.lon                 : homeLon

    // ── SIMULATOR STATE ──────────────────────────────────────────────
    property bool   simLinked:  typeof simulator !== "undefined" && simulator.isConnected
    property string simStatus:  simLinked ? (droneArmed ? droneMode : "CONNECTED") : "OFFLINE"

    // ── STATIC CONFIG ────────────────────────────────────────────────
    property string simTime:        "00:00:00"
    property int    satelliteCount: simLinked ? 14 : 0
    property string linkStatus:     simLinked ? "SIM LINK ●" : "NO LINK ○"
    readonly property real homeLat: 17.4486
    readonly property real homeLon: 78.3908
    property string vehicleType:    "Multirotor"
    property string airframeType:   "Quadrotor X"
    property string autopilotType:  "ArduPilot"
    property real   takeoffAlt:     30.0

    // ── TELEMETRY CHANGE ─────────────────────────────────────────────
    Connections {
        target: droneModel
        function onTelemetryChanged() {
            if (simLinked && typeof simulationMap !== "undefined") {
                simulationMap.updateDronePosition(droneLat, droneLon, droneHeading)
            }
        }
    }

    // ── SIMULATOR SIGNALS ────────────────────────────────────────────
    Connections {
        target: (typeof simulator !== "undefined") ? simulator : null
        function onSimConnected()    { simTimer.start() }
        function onSimDisconnected() { simTimer.stop(); simTime = "00:00:00" }
        function onModeChanged(m)    { console.log("[QML] Sim mode →", m) }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── HEADER BAR ──────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: screenTools.toolbarHeight
            color: "#1c1c1c"

            RowLayout {
                anchors.fill: parent
                anchors.margins: screenTools.defaultMargins
                spacing: screenTools.largeSpacing

                RowLayout {
                    spacing: screenTools.defaultSpacing
                    Text { text: "TIHANFLY"; color: "white"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                    Rectangle {
                        color: "#00c853"
                        radius: screenTools.defaultRadius * 0.5
                        height: screenTools.defaultFontPixelHeight * 1.6
                        width:  screenTools.defaultFontPixelWidth  * 12
                        Text { anchors.centerIn: parent; text: "SIMULATION"; color: "black"; font.family: "Consolas"; font.pixelSize: 12; font.bold: true }
                    }
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: simLinked ? "lime" : "#555555"
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                    Text { text: simStatus; color: "white"; font.family: "Consolas"; font.pixelSize: 14 }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: simTime; color: "#00e5ff"
                    font.family: "Consolas"; font.pixelSize: 14; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: screenTools.largeSpacing
                    Text { text: "🔋 " + batteryPercent + "%"; color: batteryPercent < 20 ? "#ff4444" : "white"; font.family: "Consolas"; font.pixelSize: 14 }
                    Text { text: "📡 " + satelliteCount; color: "white"; font.family: "Consolas"; font.pixelSize: 14 }
                    Text { text: "📶 " + linkStatus; color: simLinked ? "lime" : "#888888"; font.family: "Consolas"; font.pixelSize: 14 }
                    Button {
                        text: "✖"
                        onClicked: {
                            if (typeof simulator !== "undefined" && simulator.isConnected)
                                simulator.disconnectSim()
                            simulationWindow.close()
                        }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#333333" }
        }

        // ── MAIN ROW ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── LEFT PANEL ──────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                color: "#0f1a24"
                opacity: 0.95

                // Right border accent
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: 2
                    color: "#00e5ff"
                    opacity: 0.6
                }

                // Top gradient bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00e5ff" }
                        GradientStop { position: 1.0; color: "#00c85388" }
                    }
                }

                Flickable {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    contentHeight: panelCol.implicitHeight
                    clip: true
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { radius: 3; color: "#00e5ff44" }
                    }

                    ColumnLayout {
                        id: panelCol
                        width: parent.width
                        spacing: 0

                        // ═══════════════════════════════════════════
                        // SECTION 1 — CONNECT TO SIMULATOR
                        // ═══════════════════════════════════════════
                        Item { Layout.preferredHeight: 14; Layout.fillWidth: true }
                        SectionHeader { title: "SIMULATOR CONNECTION"; accentColor: "#00e5ff" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            Layout.topMargin: 14
                            Layout.bottomMargin: 14
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true; height: 72; radius: 6
                                color: "#0a1520"; border.color: "#1e3a4a"; border.width: 1
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 4
                                    Text { text: "No port address needed."; color: "#778899"; font.family: "Consolas"; font.pixelSize: 13; font.italic: true }
                                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e3a4a" }
                                    Text { text: "Press CONNECT SIM below to"; color: "#556677"; font.family: "Consolas"; font.pixelSize: 12 }
                                    Text { text: "activate the physics engine."; color: "#556677"; font.family: "Consolas"; font.pixelSize: 12 }
                                }
                            }

                            // CONNECT SIM button
                            Rectangle {
                                Layout.fillWidth: true; height: 52; radius: 6
                                visible: !simLinked
                                color: connectMA.pressed ? "#0099bb" : connectMA.containsMouse ? "#00ccee" : "#00b0cc"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: "🔌"; font.family: "Consolas"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "CONNECT SIM"; color: "#002233"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2 }
                                        Text { text: "simulator.connectSim()"; color: "#003344"; font.family: "Consolas"; font.pixelSize: 11 }
                                    }
                                }
                                MouseArea {
                                    id: connectMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof simulator !== "undefined")
                                            simulator.connectSim()
                                        else
                                            console.warn("simulator context property not set")
                                    }
                                }
                            }

                            // DISCONNECT button
                            Rectangle {
                                Layout.fillWidth: true; height: 40; radius: 6
                                visible: simLinked
                                color: dcMA.pressed ? "#aa0000" : dcMA.containsMouse ? "#cc3333" : "#991111"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: "🔌"; font.family: "Consolas"; font.pixelSize: 16 }
                                    Text { text: "DISCONNECT"; color: "white"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                                }
                                MouseArea {
                                    id: dcMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (typeof simulator !== "undefined") simulator.disconnectSim()
                                }
                            }

                            // Status badge
                            Rectangle {
                                Layout.fillWidth: true; height: 30; radius: 4
                                color: simLinked ? "#0d2010" : "#1a0a0a"
                                border.width: 1
                                border.color: simLinked ? "#00c853" : "#441111"
                                Behavior on color        { ColorAnimation { duration: 300 } }
                                Behavior on border.color { ColorAnimation { duration: 300 } }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: simLinked ? "#00ff88" : "#cc2222"
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                    Text {
                                        text: simLinked ? "Physics engine running" : "Engine offline"
                                        color: simLinked ? "#00c853" : "#aa3333"
                                        font.family: "Consolas"; font.pixelSize: 13
                                    }
                                }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // SECTION 2 — VEHICLE SETUP
                        // ═══════════════════════════════════════════
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }
                        Item { Layout.preferredHeight: 10; Layout.fillWidth: true }
                        SectionHeader { title: "VEHICLE SETUP"; accentColor: "#00e5ff" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }

                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 14
                            Layout.topMargin: 12; Layout.bottomMargin: 12; spacing: 10
                            ColumnLayout { Layout.fillWidth: true; spacing: 4
                                Text { text: "Vehicle Type"; color: "#8899aa"; font.family: "Consolas"; font.pixelSize: 14 }
                                SimComboBox { Layout.fillWidth: true; model: ["Multirotor","Fixed Wing","VTOL","Rover"]; onCurrentTextChanged: vehicleType = currentText }
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 4
                                Text { text: "Airframe Type"; color: "#8899aa"; font.family: "Consolas"; font.pixelSize: 14 }
                                SimComboBox { Layout.fillWidth: true; model: ["Quadrotor X","Hexarotor X","Octorotor X"]; onCurrentTextChanged: airframeType = currentText }
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 4
                                Text { text: "Autopilot Type"; color: "#8899aa"; font.family: "Consolas"; font.pixelSize: 14 }
                                SimComboBox { Layout.fillWidth: true; model: ["ArduPilot","PX4","iNAV"]; onCurrentTextChanged: autopilotType = currentText }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // SECTION 3 — FLIGHT CONTROLS
                        // ═══════════════════════════════════════════
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }
                        Item { Layout.preferredHeight: 10; Layout.fillWidth: true }
                        SectionHeader { title: "FLIGHT CONTROLS"; accentColor: "#ff9800" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }

                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 14
                            Layout.topMargin: 12; Layout.bottomMargin: 12; spacing: 8

                            Rectangle {
                                Layout.fillWidth: true; height: 24; radius: 4; visible: !simLinked
                                color: "#1a1000"; border.color: "#443300"; border.width: 1
                                Text { anchors.centerIn: parent; text: "Connect simulator first"; color: "#886633"; font.family: "Consolas"; font.pixelSize: 12 }
                            }

                            // State indicator
                            Rectangle {
                                Layout.fillWidth: true; height: 30; radius: 4
                                color: "#0d1a24"; border.width: 1
                                border.color: droneArmed ? "#ff9800" : simLinked ? "#00c853" : "#243344"
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                    Rectangle {
                                        width: 7; height: 7; radius: 4
                                        color: droneArmed ? "#ff9800" : simLinked ? "#00ff88" : "#445566"
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    Text { text: "Mode:"; color: "#556677"; font.family: "Consolas"; font.pixelSize: 14 }
                                    Text {
                                        text: droneMode; font.bold: true; font.family: "Consolas"; font.pixelSize: 14
                                        color: droneArmed ? "#ff9800" : simLinked ? "#00ff88" : "#778899"
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }
                            }

                            // Takeoff altitude slider
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                opacity: simLinked ? 1.0 : 0.4
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Takeoff Alt:"; color: "#8899aa"; font.family: "Consolas"; font.pixelSize: 13 }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 48; height: 20; radius: 4
                                        color: "#1c2c3c"; border.color: "#ff9800"; border.width: 1
                                        Text { anchors.centerIn: parent; text: Math.round(takeoffAlt)+"m"; color: "#ff9800"; font.family: "Consolas"; font.pixelSize: 13; font.bold: true }
                                    }
                                }
                                Slider {
                                    id: altSlider; Layout.fillWidth: true
                                    from: 5; to: 100; stepSize: 5; value: 30; enabled: simLinked
                                    onValueChanged: takeoffAlt = value
                                    background: Rectangle {
                                        x: altSlider.leftPadding
                                        y: altSlider.topPadding + altSlider.availableHeight/2 - height/2
                                        width: altSlider.availableWidth; height: 4; radius: 2; color: "#1c2c3c"
                                        Rectangle { width: altSlider.visualPosition*parent.width; height: parent.height; radius: 2; color: "#ff9800" }
                                    }
                                    handle: Rectangle {
                                        x: altSlider.leftPadding + altSlider.visualPosition*(altSlider.availableWidth-width)
                                        y: altSlider.topPadding + altSlider.availableHeight/2 - height/2
                                        width: 18; height: 18; radius: 9; color: "#ff9800"; border.color: "#003344"; border.width: 2
                                    }
                                }
                            }

                            // TAKEOFF
                            Rectangle {
                                Layout.fillWidth: true; height: 50; radius: 6
                                enabled: simLinked && !droneArmed
                                opacity: enabled ? 1.0 : 0.35
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                color: toMA.pressed ? "#00b848" : toMA.containsMouse ? "#00e070" : "#00c853"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: "🚁"; font.family: "Consolas"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "TAKEOFF"; color: "#003320"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2 }
                                        Text { text: "simulator.takeoff("+Math.round(takeoffAlt)+")"; color: "#004430"; font.family: "Consolas"; font.pixelSize: 11 }
                                    }
                                }
                                MouseArea {
                                    id: toMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (typeof simulator !== "undefined") simulator.takeoff(takeoffAlt)
                                }
                            }

                            // LOITER | FORWARD
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Rectangle {
                                    Layout.fillWidth: true; height: 42; radius: 6
                                    enabled: simLinked && droneArmed
                                    opacity: enabled ? 1.0 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    color: loitMA.pressed ? "#0055aa" : loitMA.containsMouse ? "#0077cc" : "#005588"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    ColumnLayout {
                                        anchors.centerIn: parent; spacing: 1
                                        Text { text: "⏸ LOITER"; color: "white"; font.family: "Consolas"; font.pixelSize: 13; font.bold: true }
                                        Text { text: "set_mode()"; color: "#aaccff"; font.family: "Consolas"; font.pixelSize: 10 }
                                    }
                                    MouseArea {
                                        id: loitMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (typeof simulator !== "undefined") simulator.set_mode("LOITER")
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; height: 42; radius: 6
                                    enabled: simLinked && droneArmed
                                    opacity: enabled ? 1.0 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    color: fwdMA.pressed ? "#774400" : fwdMA.containsMouse ? "#aa6600" : "#885500"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    ColumnLayout {
                                        anchors.centerIn: parent; spacing: 1
                                        Text { text: "▶ FORWARD"; color: "white"; font.family: "Consolas"; font.pixelSize: 13; font.bold: true }
                                        Text { text: "set_mode()"; color: "#ffddaa"; font.family: "Consolas"; font.pixelSize: 10 }
                                    }
                                    MouseArea {
                                        id: fwdMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (typeof simulator !== "undefined") simulator.set_mode("FORWARD")
                                    }
                                }
                            }

                            // RTL
                            Rectangle {
                                Layout.fillWidth: true; height: 42; radius: 6
                                enabled: simLinked && droneArmed
                                opacity: enabled ? 1.0 : 0.35
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                color: rtlMA.pressed ? "#5500aa" : rtlMA.containsMouse ? "#7722cc" : "#661199"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: "🏠"; font.family: "Consolas"; font.pixelSize: 18 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "RTL — Return Home"; color: "white"; font.family: "Consolas"; font.pixelSize: 13; font.bold: true }
                                        Text { text: "simulator.rtl()"; color: "#ddaaff"; font.family: "Consolas"; font.pixelSize: 11 }
                                    }
                                }
                                MouseArea {
                                    id: rtlMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (typeof simulator !== "undefined") simulator.rtl()
                                }
                            }

                            // LAND
                            Rectangle {
                                Layout.fillWidth: true; height: 48; radius: 6
                                enabled: simLinked && droneArmed
                                opacity: enabled ? 1.0 : 0.35
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                color: landMA.pressed ? "#aa2200" : landMA.containsMouse ? "#dd3300" : "#bb2200"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: "🛬"; font.family: "Consolas"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "LAND"; color: "white"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2 }
                                        Text { text: "simulator.land()"; color: "#ffaaaa"; font.family: "Consolas"; font.pixelSize: 11 }
                                    }
                                }
                                MouseArea {
                                    id: landMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (typeof simulator !== "undefined") simulator.land()
                                }
                            }
                        }

                        // ═══════════════════════════════════════════
                        // SECTION 4 — LIVE TELEMETRY
                        // ═══════════════════════════════════════════
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }
                        Item { Layout.preferredHeight: 10; Layout.fillWidth: true }
                        SectionHeader { title: "LIVE TELEMETRY"; accentColor: "#00c853" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }

                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 14
                            Layout.topMargin: 12; Layout.bottomMargin: 12; spacing: 6

                            component TRow: RowLayout {
                                property string label: ""
                                property string value: ""
                                property color  vc:    "#00e5ff"
                                Layout.fillWidth: true
                                Text { text: label; color: "#556677"; font.family: "Consolas"; font.pixelSize: 13; Layout.preferredWidth: 90 }
                                Item { Layout.fillWidth: true }
                                Text { text: value; color: vc; font.family: "Consolas"; font.pixelSize: 13; font.bold: true }
                            }

                            TRow { label: "Altitude"; value: liveAlt.toFixed(1)+" m";     vc: "#00e5ff" }
                            TRow { label: "Speed";    value: liveSpeed.toFixed(1)+" m/s";  vc: "#00c853" }
                            TRow { label: "Climb";    value: liveClimb.toFixed(2)+" m/s";  vc: liveClimb > 0 ? "#00ff88" : liveClimb < 0 ? "#ff6644" : "#778899" }
                            TRow { label: "Heading";  value: Math.round(droneHeading)+"°"; vc: "#ff9800" }
                            TRow { label: "Battery";  value: batteryPercent+"%";            vc: batteryPercent < 20 ? "#ff4444" : batteryPercent < 40 ? "#ffaa00" : "#00c853" }
                            TRow { label: "Mode";     value: droneMode;                    vc: "#aa80ff" }
                            TRow { label: "Armed";    value: droneArmed ? "YES" : "NO";    vc: droneArmed ? "#ff9800" : "#00c853" }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346" }
                            TRow { label: "Lat"; value: droneLat.toFixed(5)+"°"; vc: "#8899aa" }
                            TRow { label: "Lon"; value: droneLon.toFixed(5)+"°"; vc: "#8899aa" }
                        }

                        // ═══════════════════════════════════════════
                        // SECTION 5 — HOME CONTROLS
                        // ═══════════════════════════════════════════
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }
                        Item { Layout.preferredHeight: 10; Layout.fillWidth: true }
                        SectionHeader { title: "HOME CONTROLS"; accentColor: "#aa80ff" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1a3346"; opacity: 0.8 }

                        ColumnLayout {
                            Layout.fillWidth: true; Layout.margins: 14
                            Layout.topMargin: 12; Layout.bottomMargin: 12; spacing: 10

                            Rectangle {
                                Layout.fillWidth: true; height: 60; radius: 6
                                color: "#111a22"; border.color: "#1e3a4a"; border.width: 1
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "LAT"; color: "#556677"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Text { text: homeLat.toFixed(4)+"°"; color: "#aa80ff"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                                    }
                                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e3a4a" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "LON"; color: "#556677"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Text { text: homeLon.toFixed(4)+"°"; color: "#aa80ff"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 40; radius: 6; border.width: 1
                                color: centerMA.containsMouse ? "#1a2e42" : "#101c28"
                                border.color: centerMA.containsMouse ? "#00e5ff" : "#1e4060"
                                Behavior on color { ColorAnimation { duration: 150 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text { text: "🗺️"; font.family: "Consolas"; font.pixelSize: 14 }
                                    Text { text: "Center Map"; color: "#00e5ff"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                                }
                                MouseArea {
                                    id: centerMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: simulationMap.centerOnDrone()
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 16; Layout.fillWidth: true }
                    } // panelCol
                } // Flickable
            } // leftPanel

            // ── MAP AREA ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0a0a0a"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: screenTools.defaultMargins
                    color: "#0a0a0a"
                    radius: screenTools.defaultRadius
                    border.color: "#404040"
                    border.width: 2

                    MapViewQML { id: simulationMap; anchors.fill: parent; anchors.margins: 2 }

                    // Drone icon overlay
                    Item {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -30
                        width: 150; height: 150; z: 200
                        Image {
                            anchors.centerIn: parent; width: 50; height: 50
                            source: "images/drone.png"; fillMode: Image.PreserveAspectFit
                            rotation: currentYaw; transformOrigin: Item.Center; smooth: true
                            Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }

                    // Compass
                    Rectangle {
                        id: compassOverlay
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: screenTools.defaultMargins * 2
                        width: 90; height: 90; radius: 45
                        color: "#1c1c1c"; border.color: "#00e5ff"; border.width: 2; opacity: 0.95; z: 100
                        Repeater {
                            model: ["N","E","S","W"]
                            Text {
                                property real ang: index * 90
                                property real r:   32
                                x: compassOverlay.width/2  - width/2  + Math.sin(ang*Math.PI/180)*r
                                y: compassOverlay.height/2 - height/2 - Math.cos(ang*Math.PI/180)*r
                                text: modelData
                                color: modelData === "N" ? "#00e5ff" : "#888888"
                                font.family: "Consolas"
                                font.pixelSize: modelData === "N" ? 16 : 12
                                font.bold: modelData === "N"
                            }
                        }
                        Canvas {
                            anchors.fill: parent
                            rotation: droneHeading
                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0,0,width,height)
                                var cx = width/2, cy = height/2
                                ctx.shadowColor = "rgba(255,68,68,0.8)"; ctx.shadowBlur = 12
                                ctx.beginPath(); ctx.moveTo(cx,cy-28); ctx.lineTo(cx-6,cy+8); ctx.lineTo(cx+6,cy+8)
                                ctx.closePath(); ctx.fillStyle = "#ff4444"; ctx.fill()
                                ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.stroke(); ctx.shadowBlur = 0
                                ctx.beginPath(); ctx.moveTo(cx,cy+20); ctx.lineTo(cx-4,cy); ctx.lineTo(cx+4,cy)
                                ctx.closePath(); ctx.fillStyle = "#555555"; ctx.fill()
                            }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            width: degText.width + 8; height: 18; radius: 4
                            color: "#2c3e50"; border.color: "#00e5ff"; border.width: 1
                            Text { id: degText; anchors.centerIn: parent; text: Math.round(droneHeading)+"°"; color: "#00e5ff"; font.family: "Consolas"; font.pixelSize: 14; font.bold: true }
                        }
                    }

                    // Zoom controls
                    Column {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: screenTools.defaultMargins * 2
                        spacing: screenTools.smallSpacing
                        z: 100
                        Repeater {
                            model: [{label:"+",action:"zoomIn"},{label:"−",action:"zoomOut"},{label:"🎯",action:"centerOnDrone"}]
                            Rectangle {
                                width: 50; height: 50; radius: 25
                                color: "#1c1c1c"; border.color: "#00e5ff"; border.width: 4; opacity: 0.9
                                Text {
                                    anchors.centerIn: parent; text: modelData.label; color: "#00e5ff"; font.family: "Consolas"
                                    font.pixelSize: modelData.label === "🎯" ? screenTools.largeFontPointSize*1.5 : screenTools.largeFontPointSize*2
                                    font.bold: modelData.label !== "🎯"
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: {
                                        if      (modelData.action === "zoomIn")  simulationMap.zoomIn()
                                        else if (modelData.action === "zoomOut") simulationMap.zoomOut()
                                        else                                      simulationMap.centerOnDrone()
                                    }
                                }
                                Behavior on scale        { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation  { duration: 200 } }
                            }
                        }
                    }

                    // SIM status overlay
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: screenTools.defaultMargins * 2
                        width: 200; height: 68; radius: screenTools.defaultRadius
                        color: "#1c1c1c"
                        border.color: simLinked ? "#00c853" : "#444444"
                        border.width: 2; opacity: 0.9; z: 100
                        Behavior on border.color { ColorAnimation { duration: 300 } }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: screenTools.smallMargins * 2
                            spacing: screenTools.smallSpacing * 0.5
                            Text {
                                text: "SIMULATION MODE"
                                color: simLinked ? "#00c853" : "#666666"
                                font.family: "Consolas"; font.pixelSize: 13; font.bold: true
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#333333" }
                            Row {
                                spacing: screenTools.smallSpacing
                                Text { text: "Status:"; color: "#999999"; font.family: "Consolas"; font.pixelSize: 13 }
                                Text {
                                    text: simStatus
                                    color: simLinked ? (droneArmed ? "#ff9800" : "lime") : "#888888"
                                    font.family: "Consolas"; font.pixelSize: 13; font.bold: true
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                            Row {
                                spacing: screenTools.smallSpacing
                                visible: simLinked
                                Text { text: "Alt:"; color: "#999999"; font.family: "Consolas"; font.pixelSize: 12 }
                                Text { text: liveAlt.toFixed(1)+" m"; color: "#00e5ff"; font.family: "Consolas"; font.pixelSize: 12; font.bold: true }
                                Item { width: 8 }
                                Text { text: "Spd:"; color: "#999999"; font.family: "Consolas"; font.pixelSize: 12 }
                                Text { text: liveSpeed.toFixed(1)+" m/s"; color: "#00c853"; font.family: "Consolas"; font.pixelSize: 12; font.bold: true }
                            }
                        }
                    }
                } // inner Rectangle
            } // map area
        } // RowLayout

        // ── BOTTOM STATUS BAR ────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: screenTools.defaultFontPixelHeight * 2
            color: "#1c1c1c"
            Row {
                anchors.centerIn: parent
                spacing: screenTools.largeSpacing
                Text { text: "GPS: " + (simLinked ? "3D FIX" : "NO FIX"); color: simLinked ? "lime" : "#888888"; font.family: "Consolas"; font.pixelSize: 14 }
                Text { text: "EKF: " + (simLinked ? "OK" : "--");          color: simLinked ? "lime" : "#888888"; font.family: "Consolas"; font.pixelSize: 14 }
                Text { text: "Battery: " + batteryPercent + "%";            color: "white"; font.family: "Consolas"; font.pixelSize: 14 }
                Text { text: "Link: " + linkStatus;                         color: simLinked ? "lime" : "#888888"; font.family: "Consolas"; font.pixelSize: 14 }
                Text { text: "Mode: " + droneMode;                          color: "#aa80ff"; font.family: "Consolas"; font.pixelSize: 14 }
            }
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#333333" }
        }
    }

    // ── MISSION TIMER ────────────────────────────────────────────────
    Timer {
        id: simTimer
        interval: 1000
        repeat: true
        onTriggered: {
            var parts = simTime.split(":")
            var h = parseInt(parts[0]), m = parseInt(parts[1]), s = parseInt(parts[2])
            s++; if (s >= 60) { s = 0; m++ } if (m >= 60) { m = 0; h++ }
            simTime = (h<10?"0"+h:h)+":"+(m<10?"0"+m:m)+":"+(s<10?"0"+s:s)
        }
    }

    // ── INIT ─────────────────────────────────────────────────────────
    Component.onCompleted: {
        var coord = QtPositioning.coordinate(homeLat, homeLon)
        simulationMap.mapObject.center    = coord
        simulationMap.mapObject.zoomLevel = 16
        console.log("✅ Simulation window ready")
        console.log("   Click 'CONNECT SIM' to start the physics engine")
        console.log("   No port address required for TFlySimulator")
    }
}

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Window {
    id: pidWindow
    title: "PID Tuning - TihanFly GCS"

    // ── Size matching screenshot exactly ─────────────────────────────────────
// ── Size matching main window ─────────────────────────────────────────────
width:  Math.min(Screen.width * 0.95, 1920)
height: Math.min(Screen.height * 0.95, 1080)
minimumWidth:  1280
minimumHeight: 720

    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowMinMaxButtonsHint

    property var droneCommander: undefined
    property var droneModel:     undefined
    property var lastChanges: []
    onClosing: {
        close.accepted = false
        pidWindow.visible = false
        if (typeof mainWindowRef !== 'undefined' && mainWindowRef)
            mainWindowRef.pidTuningWindowInstance = null
        pidWindow.destroy()
    }

    // ════════════════════════════════════════════════════════════════════════
    // LIGHT THEME PALETTE  (matches ConnectionBar)
    // ════════════════════════════════════════════════════════════════════════
    readonly property color clrBg:         "#f4f5f7"
    readonly property color clrSurface:    "#fcfcfc"       // ConnectionBar exact bg
    readonly property color clrCard:       "#ffffff"
    readonly property color clrCardBorder: "#e0e4ea"
    readonly property color clrBorder:     "#dee2e6"
    readonly property color clrAccent:     "#0066cc"       // ConnectionBar accent blue
    readonly property color clrGreen:      "#28a745"       // ConnectionBar success green
    readonly property color clrTeal:       "#17a2b8"       // ConnectionBar teal
    readonly property color clrText:       "#212529"       // ConnectionBar text dark
    readonly property color clrTextMuted:  "#6c757d"       // ConnectionBar muted
    readonly property color clrInput:      "#f8f9fa"
    readonly property color clrInputBorder:"#dee2e6"
    readonly property color clrDanger:     "#dc3545"
    readonly property color clrSuccess:    "#28a745"
    readonly property string fontFamily:   "Consolas"      // ConnectionBar font

    // ── State ────────────────────────────────────────────────────────────────
    property int    activeTab: 0
    property string statusMsg: ""
    property bool   statusOk:  true

    property var rollPid:    ({ p: "0.150", i: "0.050", d: "0.0040" })
    property var pitchPid:   ({ p: "0.150", i: "0.050", d: "0.0040" })
    property var yawPid:     ({ p: "0.200", i: "0.020", d: "0.0000" })
    property var ratePid:    ({ p: "0.135", i: "0.090", d: "0.0036" })
    property var anglePid:   ({ p: "4.500", i: "0.000", d: "0.0000" })
    property var loiterPid:  ({ p: "1.000", i: "0.500", d: "0.0000" })
    property var altHoldPid: ({ p: "1.000", i: "0.000", d: "0.0000" })

    Connections {
        target: pidWindow.droneCommander ? pidWindow.droneCommander : null
function onCommandFeedback(msg, success) {
    pidWindow.statusMsg = msg
    pidWindow.statusOk  = (success !== undefined) ? success : true
    statusClearTimer.restart()
}
    }
    Timer { id: statusClearTimer; interval: 5000; onTriggered: pidWindow.statusMsg = "" }

   function collectBasic() {
    return {
        "pid_parameters": {
            "roll":  { "kp": parseFloat(rollPField.text),  "ki": parseFloat(rollIField.text),  "kd": parseFloat(rollDField.text)  },
            "pitch": { "kp": parseFloat(pitchPField.text), "ki": parseFloat(pitchIField.text), "kd": parseFloat(pitchDField.text) },
            "yaw":   { "kp": parseFloat(yawPField.text),   "ki": parseFloat(yawIField.text),   "kd": parseFloat(yawDField.text)   }
        }
    }
}
function collectAdvanced() {
    return {
        "pid_parameters": {
            "roll":     { "kp": parseFloat(ratePField.text),    "ki": parseFloat(rateIField.text),    "kd": parseFloat(rateDField.text)    },
            "altitude": { "kp": parseFloat(altHoldPField.text), "ki": parseFloat(altHoldIField.text), "kd": parseFloat(altHoldDField.text) }
        }
    }
}
function doLoad() {
    var dc = pidWindow.droneCommander
    if (dc) {
        var jsonStr = dc.readPIDAsJSON()
        if (jsonStr && jsonStr !== "{}") {
            var parsed = JSON.parse(jsonStr)
            var pid = parsed.pid_parameters

            if (pid.roll) {
                pidWindow.rollPid  = { p: pid.roll.kp.toFixed(4),  i: pid.roll.ki.toFixed(4),  d: pid.roll.kd.toFixed(4)  }
            }
            if (pid.pitch) {
                pidWindow.pitchPid = { p: pid.pitch.kp.toFixed(4), i: pid.pitch.ki.toFixed(4), d: pid.pitch.kd.toFixed(4) }
            }
            if (pid.yaw) {
                pidWindow.yawPid   = { p: pid.yaw.kp.toFixed(4),   i: pid.yaw.ki.toFixed(4),   d: pid.yaw.kd.toFixed(4)   }
            }
            if (pid.altitude) {
                pidWindow.altHoldPid = { p: pid.altitude.kp.toFixed(4), i: pid.altitude.ki.toFixed(4), d: pid.altitude.kd.toFixed(4) }
            }
            pidWindow.statusMsg = "✓ Parameters loaded from drone."
        } else {
            dc.requestAllParameters()
            pidWindow.statusMsg = "⟳ Loading parameters from drone..."
        }
    } else {
        pidWindow.statusMsg = "✓ Simulation: Parameters loaded."
    }
    pidWindow.statusOk = true
    statusClearTimer.restart()
}
function doWrite() {
    var params = activeTab === 0 ? collectBasic() : collectAdvanced()
    var dc = pidWindow.droneCommander

    var changes = []

    if (activeTab === 0) {
        var checks = [
            { axis: "Roll",  gain: "P (kp)", paramName: "ATC_RAT_RLL_P", newVal: rollPField.text  },
            { axis: "Roll",  gain: "I (ki)", paramName: "ATC_RAT_RLL_I", newVal: rollIField.text  },
            { axis: "Roll",  gain: "D (kd)", paramName: "ATC_RAT_RLL_D", newVal: rollDField.text  },
            { axis: "Pitch", gain: "P (kp)", paramName: "ATC_RAT_PIT_P", newVal: pitchPField.text },
            { axis: "Pitch", gain: "I (ki)", paramName: "ATC_RAT_PIT_I", newVal: pitchIField.text },
            { axis: "Pitch", gain: "D (kd)", paramName: "ATC_RAT_PIT_D", newVal: pitchDField.text },
            { axis: "Yaw",   gain: "P (kp)", paramName: "ATC_RAT_YAW_P", newVal: yawPField.text   },
            { axis: "Yaw",   gain: "I (ki)", paramName: "ATC_RAT_YAW_I", newVal: yawIField.text   },
            { axis: "Yaw",   gain: "D (kd)", paramName: "ATC_RAT_YAW_D", newVal: yawDField.text   }
        ]
        for (var i = 0; i < checks.length; i++) {
            var c = checks[i]
            var droneVal = dc ? dc.getParameterValue(c.paramName) : null
            var oldVal   = (droneVal !== null && droneVal !== undefined)
                           ? parseFloat(droneVal).toFixed(4)
                           : "N/A"
            changes.push({
                axis:    c.axis,
                gain:    c.gain,
                oldVal:  oldVal,
                newVal:  parseFloat(c.newVal).toFixed(4),
                changed: oldVal !== "N/A" && Math.abs(parseFloat(oldVal) - parseFloat(c.newVal)) > 0.00001
            })
        }
    } else {
        var checksAdv = [
            { axis: "Rate",    gain: "P (kp)", paramName: "ATC_RAT_RLL_P", newVal: ratePField.text    },
            { axis: "Rate",    gain: "I (ki)", paramName: "ATC_RAT_RLL_I", newVal: rateIField.text    },
            { axis: "Rate",    gain: "D (kd)", paramName: "ATC_RAT_RLL_D", newVal: rateDField.text    },
            { axis: "AltHold", gain: "P (kp)", paramName: "PSC_POSZ_P",    newVal: altHoldPField.text },
            { axis: "AltHold", gain: "I (ki)", paramName: "PSC_VELZ_P",    newVal: altHoldIField.text },
            { axis: "AltHold", gain: "D (kd)", paramName: "PSC_VELZ_D",    newVal: altHoldDField.text }
        ]
        for (var j = 0; j < checksAdv.length; j++) {
            var d = checksAdv[j]
            var droneValAdv = dc ? dc.getParameterValue(d.paramName) : null
            var oldValAdv   = (droneValAdv !== null && droneValAdv !== undefined)
                              ? parseFloat(droneValAdv).toFixed(4)
                              : "N/A"
            changes.push({
                axis:    d.axis,
                gain:    d.gain,
                oldVal:  oldValAdv,
                newVal:  parseFloat(d.newVal).toFixed(4),
                changed: oldValAdv !== "N/A" && Math.abs(parseFloat(oldValAdv) - parseFloat(d.newVal)) > 0.00001
            })
        }
    }

    pidWindow.lastChanges = changes

    if (dc) {
        dc.writeParameters(JSON.stringify(params))
    }

    writeConfirmPopup.open()

    pidWindow.statusMsg = "✓ Parameters written to drone!"
    pidWindow.statusOk  = true
    statusClearTimer.restart()
}
    function doReset() {
        rollPid    = ({ p: "0.150", i: "0.050", d: "0.0040" })
        pitchPid   = ({ p: "0.150", i: "0.050", d: "0.0040" })
        yawPid     = ({ p: "0.200", i: "0.020", d: "0.0000" })
        ratePid    = ({ p: "0.135", i: "0.090", d: "0.0036" })
        anglePid   = ({ p: "4.500", i: "0.000", d: "0.0000" })
        loiterPid  = ({ p: "1.000", i: "0.500", d: "0.0000" })
        altHoldPid = ({ p: "1.000", i: "0.000", d: "0.0000" })
        pidWindow.statusMsg = "✓ All parameters reset to defaults."
        pidWindow.statusOk = true; statusClearTimer.restart()
    }

    // ════════════════════════════════════════════════════════════════════════
    // ROOT
    // ════════════════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        color: clrBg

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ════════════════════════════════════════════════════════════════
            // HEADER  — exact ConnectionBar style
            // height: 80, bg: #fcfcfc, border bottom + gradient stripe
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                height: 80
                color: clrSurface
                border.color: "#fffefeff"
                border.width: 2

                // Left side: icon + text (same pattern as ConnectionBar items)
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 20
                    spacing: 14

                    // Gear icon badge — matches ConnectionBar button style
                    Rectangle {
                        width: 40; height: 40; radius: 10
                        color: "#e3f2fd"
                        border.color: "#87ceeb"; border.width: 2
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "⚙"
                            font.pixelSize: 20
                            color: clrAccent
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "PID Tuning"
                            font.pixelSize: 16
                            font.bold: true
                            font.family: fontFamily
                            color: clrText
                        }
                        Text {
                            text: "Advanced Flight Control Parameters"
                            font.pixelSize: 11
                            font.family: fontFamily
                            color: clrTextMuted
                        }
                    }
                }

                // Right side: Close button + TiHAN logo
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 16
                    spacing: 12

                    // ── Close Button ──────────────────────────────────────────
                    Rectangle {
                        id: closeBtn
                        width: 32; height: 32; radius: 8
                        color: closeMa.pressed ? "#c0392b"
                             : closeMa.containsMouse ? "#e74c3c" : "#f8d7da"
                        border.color: closeMa.containsMouse ? "#c0392b" : "#f5c6cb"
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 14
                            font.bold: true
                            color: closeMa.containsMouse ? "#ffffff" : "#c0392b"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pidWindow.visible = false
                                pidWindow.destroy()
                            }
                        }

                        ToolTip.visible: closeMa.containsMouse
                        ToolTip.text: "Close"
                        ToolTip.delay: 500
                    }

                    // ── TiHAN logo ────────────────────────────────────────────
                    Item {
                    id: logoContainer
                    width: 100; height: 40
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: logoImage
                        anchors.centerIn: parent
                        width: 100; height: 40
                        source: "../images/tihan.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: true; antialiasing: true

                        // Fallback text if image missing
                        Text {
                            anchors.centerIn: parent
                            text: "TiHAN FLY"
                            color: clrAccent
                            font.pixelSize: 14
                            font.bold: true
                            font.family: fontFamily
                            visible: logoImage.status !== Image.Ready
                        }
                    }
                }
                } // end Row (close button + logo)

                // Bottom gradient stripe — exact copy from ConnectionBar
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 0
                    width: parent.width
                    height: 3
                    opacity: 0.8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: clrAccent }
                        GradientStop { position: 0.5; color: clrGreen  }
                        GradientStop { position: 1.0; color: clrTeal   }
                    }
                }
            }

            // ── TAB BAR ───────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 38
                color: clrSurface
                border.color: clrBorder; border.width: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    spacing: 0

                    Repeater {
                        model: ["Basic", "Advanced"]
                        delegate: Item {
                            height: 38
                            width: tLbl.implicitWidth + 36

                            Rectangle {
                                anchors.fill: parent
                                color: pidWindow.activeTab === index ? clrBg : "transparent"

                                // Active underline using accent blue
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left; anchors.right: parent.right
                                    height: 2
                                    color: pidWindow.activeTab === index ? clrAccent : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    id: tLbl
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 13
                                    font.bold: pidWindow.activeTab === index
                                    font.family: fontFamily
                                    color: pidWindow.activeTab === index ? clrAccent : clrTextMuted
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pidWindow.activeTab = index
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // Separator line under tabs
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left; anchors.right: parent.right
                    height: 1; color: clrBorder
                }
            }

            // ── SCROLLABLE CONTENT ────────────────────────────────────────────
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                // ── BASIC TAB ─────────────────────────────────────────────────
                ColumnLayout {
                    width: pidWindow.width
                    spacing: 0
                    visible: pidWindow.activeTab === 0

                    Item { height: 12 }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12; Layout.rightMargin: 12
                        spacing: 10

                        PidCard { Layout.fillWidth: true; cardTitle: "Roll PID";  cardIcon: "R"; iconColor: "#1565c0"; pFieldId: rollPField;  iFieldId: rollIField;  dFieldId: rollDField;  pDefault: pidWindow.rollPid.p;  iDefault: pidWindow.rollPid.i;  dDefault: pidWindow.rollPid.d  }
                        PidCard { Layout.fillWidth: true; cardTitle: "Pitch PID"; cardIcon: "P"; iconColor: "#e65100"; pFieldId: pitchPField; iFieldId: pitchIField; dFieldId: pitchDField; pDefault: pidWindow.pitchPid.p; iDefault: pidWindow.pitchPid.i; dDefault: pidWindow.pitchPid.d }
                        PidCard { Layout.fillWidth: true; cardTitle: "Yaw PID";   cardIcon: "Y"; iconColor: "#2e7d32"; pFieldId: yawPField;   iFieldId: yawIField;   dFieldId: yawDField;   pDefault: pidWindow.yawPid.p;   iDefault: pidWindow.yawPid.i;   dDefault: pidWindow.yawPid.d   }
                    }

                    Item { height: 12 }
                }

                // ── ADVANCED TAB ──────────────────────────────────────────────
                ColumnLayout {
                    width: pidWindow.width
                    spacing: 0
                    visible: pidWindow.activeTab === 1

                    Item { height: 12 }

                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 10
                        PidCard { Layout.fillWidth: true; cardTitle: "Rate PID";  cardIcon: "RT"; iconColor: "#b71c1c"; pFieldId: ratePField;    iFieldId: rateIField;    dFieldId: rateDField;    pDefault: pidWindow.ratePid.p;    iDefault: pidWindow.ratePid.i;    dDefault: pidWindow.ratePid.d    }
                        PidCard { Layout.fillWidth: true; cardTitle: "Angle PID"; cardIcon: "AG"; iconColor: "#6a1b9a"; pFieldId: anglePField;   iFieldId: angleIField;   dFieldId: angleDField;   pDefault: pidWindow.anglePid.p;   iDefault: pidWindow.anglePid.i;   dDefault: pidWindow.anglePid.d   }
                    }

                    Item { height: 8 }

                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 10
                        PidCard { Layout.fillWidth: true; cardTitle: "Loiter PID";  cardIcon: "LT"; iconColor: "#00695c"; pFieldId: loiterPField;  iFieldId: loiterIField;  dFieldId: loiterDField;  pDefault: pidWindow.loiterPid.p;  iDefault: pidWindow.loiterPid.i;  dDefault: pidWindow.loiterPid.d  }
                        PidCard { Layout.fillWidth: true; cardTitle: "AltHold PID"; cardIcon: "AH"; iconColor: "#e65100"; pFieldId: altHoldPField; iFieldId: altHoldIField; dFieldId: altHoldDField; pDefault: pidWindow.altHoldPid.p; iDefault: pidWindow.altHoldPid.i; dDefault: pidWindow.altHoldPid.d }
                    }

                    Item { height: 12 }
                }
            }

            // ════════════════════════════════════════════════════════════════
            // BOTTOM ACTION BAR — light, matches ConnectionBar footer feel
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                height: 60
                color: clrSurface
                border.color: clrBorder; border.width: 0

                // Top separator
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left; anchors.right: parent.right
                    height: 1; color: clrBorder
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    spacing: 10

                    // Status indicator
                    RowLayout {
                        spacing: 6; visible: pidWindow.statusMsg !== ""; Layout.fillWidth: true
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            color: pidWindow.statusOk ? clrSuccess : clrDanger
                            SequentialAnimation on opacity {
                                running: pidWindow.statusMsg !== ""; loops: 3
                                NumberAnimation { to: 0.2; duration: 350 }
                                NumberAnimation { to: 1.0; duration: 350 }
                            }
                        }
                        Text {
                            text: pidWindow.statusMsg
                            color: pidWindow.statusOk ? clrSuccess : clrDanger
                            font.pixelSize: 12; font.family: fontFamily
                            elide: Text.ElideRight
                        }
                    }
                    Item { Layout.fillWidth: true; visible: pidWindow.statusMsg === "" }

                    // ── LOAD BUTTON — light blue, matches ConnectionBar combo style ──
                    Rectangle {
                        width: 140; height: 36; radius: 10
                        border.width: 2
                        border.color: loadMa.containsMouse ? "#4a90e2" : "#87ceeb"
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: loadMa.pressed ? "#4a90e2" : (loadMa.containsMouse ? "#7bb3e0" : "#87ceeb") }
                            GradientStop { position: 1.0; color: loadMa.pressed ? "#357abd" : (loadMa.containsMouse ? "#4a90e2" : "#7bb3e0") }
                        }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.centerIn: parent; spacing: 6
                            Text { text: "↓"; color: "#1a3a5c"; font.pixelSize: 15; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Load Parameters"; color: "#2c5282"; font.pixelSize: 12; font.bold: true; font.family: fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        }

                        MouseArea { id: loadMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pidWindow.doLoad() }
                    }

                    // ── RESET BUTTON — red, matches DISCONNECT button style ──
                    Rectangle {
                        width: 148; height: 36; radius: 10
                        border.width: 2
                        border.color: resetMa.pressed ? "#a71d2a" : "#dc3545"
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: resetMa.pressed ? "#a71d2a" : (resetMa.containsMouse ? "#bd2130" : "#dc3545") }
                            GradientStop { position: 1.0; color: resetMa.pressed ? "#7f1d1d" : (resetMa.containsMouse ? "#a71d2a" : "#bd2130") }
                        }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.centerIn: parent; spacing: 6
                            Text { text: "↺"; color: "#ffffff"; font.pixelSize: 15; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Reset to Default"; color: "#ffffff"; font.pixelSize: 12; font.bold: true; font.family: fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        }

                        MouseArea { id: resetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: resetConfirm.open() }
                    }

                    // ── WRITE BUTTON — green, matches CONNECT button style ──
                    Rectangle {
                        width: 150; height: 36; radius: 10
                        border.width: 2
                        border.color: writeMa.pressed ? "#1e7e34" : "#28a745"
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: writeMa.pressed ? "#1e7e34" : (writeMa.containsMouse ? "#218838" : "#28a745") }
                            GradientStop { position: 1.0; color: writeMa.pressed ? "#155d27" : (writeMa.containsMouse ? "#1e7e34" : "#218838") }
                        }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.centerIn: parent; spacing: 6
                            Text { text: "↑"; color: "#ffffff"; font.pixelSize: 15; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Write Parameters"; color: "#ffffff"; font.pixelSize: 12; font.bold: true; font.family: fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        }

                        MouseArea { id: writeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pidWindow.doWrite() }
                    }
                }
            }
        }
    }

    // ── Reset Confirm ────────────────────────────────────────────────────────
    Popup {
        id: resetConfirm
        anchors.centerIn: parent
        width: 340; height: 162
        modal: true
        background: Rectangle {
            color: "#ffffff"; radius: 10
            border.color: clrDanger; border.width: 2
            layer.enabled: true
        }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 12
            Text { text: "⚠  Reset All Parameters?"; color: clrDanger; font.pixelSize: 14; font.bold: true; font.family: fontFamily; Layout.fillWidth: true }
            Text {
                text: "Resets all values to factory defaults.\nYou can reload from the drone afterwards."
                color: clrTextMuted; font.pixelSize: 11; font.family: fontFamily
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            RowLayout {
                spacing: 10; Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                // Cancel
                Rectangle {
                    width: 90; height: 34; radius: 8
                    color: cMa2.containsMouse ? "#e9ecef" : "#f8f9fa"
                    border.color: clrBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "Cancel"; color: clrText; font.pixelSize: 12; font.family: fontFamily; font.bold: true }
                    MouseArea { id: cMa2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: resetConfirm.close() }
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                // Confirm
                Rectangle {
                    width: 110; height: 34; radius: 8
                    border.color: clrDanger; border.width: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: rMa2.containsMouse ? "#bd2130" : "#dc3545" }
                        GradientStop { position: 1.0; color: rMa2.containsMouse ? "#a71d2a" : "#bd2130" }
                    }
                    Text { anchors.centerIn: parent; text: "Yes, Reset"; color: "#ffffff"; font.pixelSize: 12; font.bold: true; font.family: fontFamily }
                    MouseArea { id: rMa2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { resetConfirm.close(); pidWindow.doReset() } }
                }
            }
        }
    }

    // ── Hidden field references ──────────────────────────────────────────────
    TextField { id: rollPField;    visible: false; text: pidWindow.rollPid.p }
    TextField { id: rollIField;    visible: false; text: pidWindow.rollPid.i }
    TextField { id: rollDField;    visible: false; text: pidWindow.rollPid.d }
    TextField { id: pitchPField;   visible: false; text: pidWindow.pitchPid.p }
    TextField { id: pitchIField;   visible: false; text: pidWindow.pitchPid.i }
    TextField { id: pitchDField;   visible: false; text: pidWindow.pitchPid.d }
    TextField { id: yawPField;     visible: false; text: pidWindow.yawPid.p }
    TextField { id: yawIField;     visible: false; text: pidWindow.yawPid.i }
    TextField { id: yawDField;     visible: false; text: pidWindow.yawPid.d }
    TextField { id: ratePField;    visible: false; text: pidWindow.ratePid.p }
    TextField { id: rateIField;    visible: false; text: pidWindow.ratePid.i }
    TextField { id: rateDField;    visible: false; text: pidWindow.ratePid.d }
    TextField { id: anglePField;   visible: false; text: pidWindow.anglePid.p }
    TextField { id: angleIField;   visible: false; text: pidWindow.anglePid.i }
    TextField { id: angleDField;   visible: false; text: pidWindow.anglePid.d }
    TextField { id: loiterPField;  visible: false; text: pidWindow.loiterPid.p }
    TextField { id: loiterIField;  visible: false; text: pidWindow.loiterPid.i }
    TextField { id: loiterDField;  visible: false; text: pidWindow.loiterPid.d }
    TextField { id: altHoldPField; visible: false; text: pidWindow.altHoldPid.p }
    TextField { id: altHoldIField; visible: false; text: pidWindow.altHoldPid.i }
    TextField { id: altHoldDField; visible: false; text: pidWindow.altHoldPid.d }

    // ════════════════════════════════════════════════════════════════════════
    // COMPONENT: PidCard  — light theme
    // ════════════════════════════════════════════════════════════════════════
    component PidCard: Rectangle {
        id: card
        height: cCol.implicitHeight + 24
        radius: 8
        color: clrCard
        border.color: clrCardBorder; border.width: 1

        // Left accent stripe in icon color
        Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: 3; radius: 2; color: card.iconColor; opacity: 0.8
        }

        property string cardTitle: "PID"
        property string cardIcon:  "X"
        property color  iconColor: clrAccent
        property TextField pFieldId
        property TextField iFieldId
        property TextField dFieldId
        property string pDefault: "0.000"
        property string iDefault: "0.000"
        property string dDefault: "0.000"

        ColumnLayout {
            id: cCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: 12; anchors.rightMargin: 10; anchors.topMargin: 10
            spacing: 7

            // Card header
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: Qt.rgba(card.iconColor.r, card.iconColor.g, card.iconColor.b, 0.10)
                    border.color: Qt.rgba(card.iconColor.r, card.iconColor.g, card.iconColor.b, 0.35)
                    border.width: 1
                    Text { anchors.centerIn: parent; text: card.cardIcon; color: card.iconColor; font.pixelSize: 9; font.bold: true; font.family: fontFamily }
                }
                Text {
                    text: card.cardTitle
                    color: clrText; font.pixelSize: 12; font.bold: true; font.family: fontFamily
                    Layout.fillWidth: true
                }
            }

            // Divider
            Rectangle { Layout.fillWidth: true; height: 1; color: clrCardBorder }

            // P row
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Rectangle {
                    width: 18; height: 18; radius: 3
                    color: Qt.rgba(card.iconColor.r, card.iconColor.g, card.iconColor.b, 0.10)
                    Text { anchors.centerIn: parent; text: "P"; color: card.iconColor; font.pixelSize: 9; font.bold: true; font.family: fontFamily }
                }
                Text { text: "Proportional"; color: clrTextMuted; font.pixelSize: 10; font.family: fontFamily; Layout.preferredWidth: 72 }
                TextField {
                    id: pF; Layout.fillWidth: true; text: card.pDefault
                    font.pixelSize: 11; font.family: fontFamily; color: clrText
                    horizontalAlignment: TextInput.AlignHCenter; selectByMouse: true
                    leftPadding: 4; rightPadding: 4; topPadding: 3; bottomPadding: 3
                    validator: RegExpValidator { regExp: /^\d{0,4}(\.\d{0,6})?$/ }
                    background: Rectangle {
                        radius: 5
                        color: pF.activeFocus ? "#e8f4fd" : clrInput
                        border.color: pF.activeFocus ? clrAccent : clrInputBorder
                        border.width: pF.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }
                    onTextChanged: { if (card.pFieldId) card.pFieldId.text = text }
                }
            }

            // I row
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Rectangle {
                    width: 18; height: 18; radius: 3
                    color: Qt.rgba(card.iconColor.r, card.iconColor.g, card.iconColor.b, 0.10)
                    Text { anchors.centerIn: parent; text: "I"; color: card.iconColor; font.pixelSize: 9; font.bold: true; font.family: fontFamily }
                }
                Text { text: "Integral"; color: clrTextMuted; font.pixelSize: 10; font.family: fontFamily; Layout.preferredWidth: 72 }
                TextField {
                    id: iF; Layout.fillWidth: true; text: card.iDefault
                    font.pixelSize: 11; font.family: fontFamily; color: clrText
                    horizontalAlignment: TextInput.AlignHCenter; selectByMouse: true
                    leftPadding: 4; rightPadding: 4; topPadding: 3; bottomPadding: 3
                    validator: RegExpValidator { regExp: /^\d{0,4}(\.\d{0,6})?$/ }
                    background: Rectangle {
                        radius: 5
                        color: iF.activeFocus ? "#e8f4fd" : clrInput
                        border.color: iF.activeFocus ? clrAccent : clrInputBorder
                        border.width: iF.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }
                    onTextChanged: { if (card.iFieldId) card.iFieldId.text = text }
                }
            }

            // D row
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Rectangle {
                    width: 18; height: 18; radius: 3
                    color: Qt.rgba(card.iconColor.r, card.iconColor.g, card.iconColor.b, 0.10)
                    Text { anchors.centerIn: parent; text: "D"; color: card.iconColor; font.pixelSize: 9; font.bold: true; font.family: fontFamily }
                }
                Text { text: "Derivative"; color: clrTextMuted; font.pixelSize: 10; font.family: fontFamily; Layout.preferredWidth: 72 }
                TextField {
                    id: dF; Layout.fillWidth: true; text: card.dDefault
                    font.pixelSize: 11; font.family: fontFamily; color: clrText
                    horizontalAlignment: TextInput.AlignHCenter; selectByMouse: true
                    leftPadding: 4; rightPadding: 4; topPadding: 3; bottomPadding: 3
                    validator: RegExpValidator { regExp: /^\d{0,4}(\.\d{0,6})?$/ }
                    background: Rectangle {
                        radius: 5
                        color: dF.activeFocus ? "#e8f4fd" : clrInput
                        border.color: dF.activeFocus ? clrAccent : clrInputBorder
                        border.width: dF.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                    }
                    onTextChanged: { if (card.dFieldId) card.dFieldId.text = text }
                }
            }

            Item { height: 2 }
        }
    }
    // ── Write Summary Popup ───────────────────────────────────────────────────
Popup {
    id: writeConfirmPopup
    anchors.centerIn: parent
    width: 440
    height: Math.min(120 + pidWindow.lastChanges.length * 34 + 60, 520)
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: "#ffffff"
        radius: 10
        border.color: clrGreen
        border.width: 2
        layer.enabled: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // ── Header ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                width: 28; height: 28; radius: 6
                color: "#e8f5e9"
                border.color: clrGreen; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "✓"; color: clrGreen
                    font.pixelSize: 16; font.bold: true
                }
            }
            Text {
                text: "Parameters Written to Drone"
                font.pixelSize: 14; font.bold: true
                font.family: fontFamily; color: clrText
                Layout.fillWidth: true
            }
        }

        // ── Divider ───────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: clrBorder }

        // ── No changes message ────────────────────────────────────────
        Text {
            visible: pidWindow.lastChanges.length === 0
            text: "No values were changed from defaults."
            color: clrTextMuted; font.pixelSize: 12
            font.family: fontFamily
            Layout.fillWidth: true
        }

        // ── Column headers ────────────────────────────────────────────
        RowLayout {
            visible: pidWindow.lastChanges.length > 0
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: "Axis / Gain"
                font.pixelSize: 11; font.bold: true
                color: clrTextMuted; font.family: fontFamily
                Layout.preferredWidth: 120
            }
            Text {
                text: "Default (Drone)"
                font.pixelSize: 11; font.bold: true
                color: clrTextMuted; font.family: fontFamily
                Layout.preferredWidth: 120
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                text: "→"
                font.pixelSize: 11; color: clrTextMuted
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                text: "New Value"
                font.pixelSize: 11; font.bold: true
                color: clrGreen; font.family: fontFamily
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ── Rows ──────────────────────────────────────────────────────
        ScrollView {
            visible: pidWindow.lastChanges.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: writeConfirmPopup.width - 32
                spacing: 3

                Repeater {
                    model: pidWindow.lastChanges

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 5
                        color:        modelData.changed ? "#f0fff4" : "#fafafa"
                        border.color: modelData.changed ? "#b2dfdb" : "#eeeeee"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 0

                            // Axis + Gain
                            Text {
                                text: modelData.axis + " " + modelData.gain
                                font.pixelSize: 11; font.family: fontFamily
                                color: clrText
                                Layout.preferredWidth: 120
                            }

                            // Old value from drone
                            Text {
                                text: modelData.oldVal
                                font.pixelSize: 11; font.family: fontFamily
                                color: modelData.changed ? "#e53935" : clrTextMuted
                                font.strikeout: modelData.changed
                                Layout.preferredWidth: 120
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Arrow
                            Text {
                                text: modelData.changed ? "→" : " "
                                font.pixelSize: 12
                                color: clrAccent
                                Layout.preferredWidth: 24
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // New value
                            Text {
                                text: modelData.newVal
                                font.pixelSize: 11; font.family: fontFamily
                                font.bold: modelData.changed
                                color: modelData.changed ? clrGreen : clrTextMuted
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }

        // ── OK Button ─────────────────────────────────────────────────
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 100; height: 32; radius: 8
            color: okMa.containsMouse ? "#218838" : clrGreen
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: "OK"; color: "#ffffff"
                font.pixelSize: 13; font.bold: true
                font.family: fontFamily
            }
            MouseArea {
                id: okMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: writeConfirmPopup.close()
            }
        }
    }
}
}
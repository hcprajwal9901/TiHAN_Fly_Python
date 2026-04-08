import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: flightModeWindow
    title: "Flight Modes"

    width:  620
    height: 560
    minimumWidth: 400
    minimumHeight: 400

    color: "#1a1a1a"

    // ── Properties ────────────────────────────────────────────────────────
    property var droneCommander: null
    property var droneModel: null
    property var flightModeWindowInstance: null

    property int    activeRowIndex: 0
    property string currentMode:    flightModes[0].mode
    property int    currentPwmLow:  pwmRanges[0][0]
    property int    currentPwmHigh: pwmRanges[0][1]

    property string liveActiveMode: "—"
    property int    liveRCPwm: 0

    // ── Palette (matches UserParams.qml) ──────────────────────────────────
    property color gridColor:   "#3a3a3a"
    property color headerBg:    "#252525"
    property color accentColor: "#9acd32"
    property color textMuted:   "#888888"
    property color textPrimary: "#ffffff"
    property color textSub:     "#cccccc"
    property color rowEven:     "#1a1a1a"
    property color rowOdd:      "#1e1e1e"
    property color activeRowBg: "#1e2e1e"

    readonly property var modeOptions: [
        "Stabilize", "AltHold", "Loiter", "Auto", "Guided",
        "RTL", "Land", "PosHold", "Brake", "Acro", "Sport",
        "Drift", "Flip", "Circle", "Follow"
    ]

    readonly property var pwmRanges: [
        [0,    1230],
        [1231, 1360],
        [1361, 1490],
        [1491, 1620],
        [1621, 1749],
        [1750, 2006]
    ]

    property var flightModes: [
        { mode: "Stabilize", simple: false, superSimple: false },
        { mode: "Stabilize", simple: false, superSimple: false },
        { mode: "Stabilize", simple: false, superSimple: false },
        { mode: "Stabilize", simple: false, superSimple: false },
        { mode: "Stabilize", simple: false, superSimple: false },
        { mode: "Stabilize", simple: false, superSimple: false }
    ]

    Connections {
        target: flightModeWindow.droneCommander
        ignoreUnknownSignals: true
        function onFlightModesConfirmed(modeNames) { flightModeWindow.applyConfirmedModes(modeNames) }
        function onParametersUpdated() { flightModeWindow.loadModesFromBackend() }
    }

    Connections {
        target: flightModeWindow.droneModel
        ignoreUnknownSignals: true
        function onFltModePwmChanged() {
            var p = flightModeWindow.droneModel ? flightModeWindow.droneModel.fltModePwm : 0
            if (p > 800) {
                flightModeWindow.liveRCPwm = p
                flightModeWindow.liveActiveMode = flightModeWindow.getModeFromPwm(p)
            }
        }
    }

    Timer {
        interval: 500
        running: flightModeWindow.visible && flightModeWindow.droneModel !== null
        repeat: true
        onTriggered: {
            if (!flightModeWindow.droneModel) return
            var p = flightModeWindow.droneModel.fltModePwm
            if (p && p > 800) {
                if (p !== flightModeWindow.liveRCPwm) flightModeWindow.liveRCPwm = p
                var m = flightModeWindow.getModeFromPwm(p)
                if (m !== flightModeWindow.liveActiveMode) flightModeWindow.liveActiveMode = m
            }
        }
    }

    Component.onCompleted: {
        if (droneModel) {
            var p = droneModel.fltModePwm
            if (p && p > 800) {
                liveRCPwm = p
                liveActiveMode = getModeFromPwm(p)
            }
        }
        if (droneCommander) {
            loadModesFromBackend()
            droneCommander.requestAllParameters() // Refresh parameters to be up to date
        }
    }

    onDroneCommanderChanged: {
        if (droneCommander) {
            loadModesFromBackend()
        }
    }

    function getModeFromPwm(pwm) {
        if (pwm <= 0) return "—"
        for (var i = 0; i < 6; i++) {
            var lo = flightModeWindow.pwmRanges[i][0]
            var hi = flightModeWindow.pwmRanges[i][1]
            if (i === 5) {
                if (pwm >= lo) return flightModeWindow.flightModes[i].mode
            } else {
                if (pwm >= lo && pwm <= hi) return flightModeWindow.flightModes[i].mode
            }
        }
        return "—"
    }

    function loadModesFromBackend() {
        if (!droneCommander || !droneCommander.parameters) return
        var params = droneCommander.parameters
        
        var idMap = {
            0: "Stabilize", 1: "Acro",     2: "AltHold",  3: "Auto",
            4: "Guided",    5: "Loiter",   6: "RTL",      7: "Circle",
            9: "Land",     11: "Drift",   13: "Sport",   14: "Flip",
            15: "Autotune", 16: "PosHold", 17: "Brake",   18: "Throw",
            23: "Follow"
        }

        var names = []
        var foundAny = false
        for (var i = 1; i <= 6; i++) {
            var pName = "FLTMODE" + i
            if (params[pName] !== undefined && params[pName].value !== undefined) {
                var modeId = Math.round(parseFloat(params[pName].value))
                var mName = idMap[modeId]
                names.push(mName ? mName : "Stabilize")
                foundAny = true
            } else {
                names.push(flightModes[i-1].mode)
            }
        }

        if (foundAny) {
            applyConfirmedModes(names)
        }
    }

    // ── Functions ─────────────────────────────────────────────────────────
    function applyConfirmedModes(modeNames) {
        var updated = []
        for (var i = 0; i < 6; i++) {
            var name = (i < modeNames.length) ? modeNames[i] : "Stabilize"
            updated.push({ mode: name, simple: flightModes[i].simple, superSimple: flightModes[i].superSimple })
        }
        flightModes = updated
        updateActiveRow(activeRowIndex)
    }

    function updateActiveRow(index) {
        activeRowIndex = index
        currentMode    = flightModes[index].mode
        currentPwmLow  = pwmRanges[index][0]
        currentPwmHigh = pwmRanges[index][1]
    }

    function pwmLabel(index) {
        if (index === 5) return "PWM " + pwmRanges[5][0] + " +"
        return "PWM " + pwmRanges[index][0] + " \u2014 " + pwmRanges[index][1]
    }

    function doClose() {
        try {
            if (typeof mainWindowRef !== "undefined" && mainWindowRef !== null
                    && "flightModeWindowInstance" in mainWindowRef)
                mainWindowRef.flightModeWindowInstance = null
        } catch(e) {}
        flightModeWindow.close()
    }

    // ── UI ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── HEADER ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: "#1f1f1f"
            border.color: gridColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Rectangle { width: 4; height: 22; color: accentColor; radius: 2 }

                Text {
                    text: "Flight Modes"
                    color: textPrimary
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "Consolas"
                    Layout.fillWidth: true
                }

                // Live status pill
                Rectangle {
                    visible: liveActiveMode !== "—"
                    height: 24; width: liveModeText.width + 20; radius: 12
                    color: "#1a3a1a"; border.color: accentColor; border.width: 1
                    Text {
                        id: liveModeText
                        anchors.centerIn: parent
                        text: "LIVE: " + liveActiveMode
                        font.family: "Consolas"; font.pixelSize: 11; font.bold: true
                        color: accentColor
                    }
                }

                // PWM pill
                Rectangle {
                    height: 24; width: pwmText.width + 20; radius: 12
                    color: "#252525"; border.color: gridColor; border.width: 1
                    Text {
                        id: pwmText
                        anchors.centerIn: parent
                        text: flightModeWindow.liveRCPwm > 800 ? (flightModeWindow.droneModel ? flightModeWindow.droneModel.fltModeChannel : 5) + ":" + flightModeWindow.liveRCPwm : (flightModeWindow.droneModel ? flightModeWindow.droneModel.fltModeChannel : 5) + ":—"
                        font.family: "Consolas"; font.pixelSize: 11
                        color: accentColor
                    }
                }

                /* // Close button
                Button {
                    text: "✕ Close"
                    font.pixelSize: 12
                    implicitWidth: 80
                    implicitHeight: 30
                    background: Rectangle {
                        color: parent.pressed ? "#3a1a1a" : (parent.hovered ? "#4a1c1c" : "#2a1010")
                        border.color: "#e24b4a"
                        border.width: 1; radius: 4
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e24b4a"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12; font.family: "Consolas"
                    }
                    onClicked: flightModeWindow.doClose()
                } */
            }
        }

        // ── COLUMN HEADERS ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 34
            color: headerBg
            border.color: gridColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 0

                Text { Layout.preferredWidth: 140; text: "Flight Mode";   color: textMuted; font.pixelSize: 11; font.bold: true; font.family: "Consolas" }
                Text { Layout.preferredWidth: 150; text: "Mode";          color: textMuted; font.pixelSize: 11; font.bold: true; font.family: "Consolas" }
                Text { Layout.preferredWidth: 75;  text: "Simple";        color: textMuted; font.pixelSize: 11; font.bold: true; font.family: "Consolas" }
                Text { Layout.preferredWidth: 115; text: "Super Simple";  color: textMuted; font.pixelSize: 11; font.bold: true; font.family: "Consolas" }
                Text { Layout.fillWidth: true;     text: "PWM Range";     color: textMuted; font.pixelSize: 11; font.bold: true; font.family: "Consolas" }
            }
        }

        // ── MODE ROWS ────────────────────────────────────────────────────
        Repeater {
            model: 6
            delegate: Rectangle {
                id: modeRow
                property int rowIndex: index

                property bool isLiveActive: {
                    var pwm = flightModeWindow.liveRCPwm
                    if (pwm > 800) {
                        var lo = flightModeWindow.pwmRanges[rowIndex][0]
                        var hi = flightModeWindow.pwmRanges[rowIndex][1]
                        if (rowIndex === 5) return pwm >= lo
                        return pwm >= lo && pwm <= hi
                    }
                    if (rowIndex === 0) {
                        var live = flightModeWindow.liveActiveMode.toLowerCase()
                        var slot = flightModes[rowIndex].mode.toLowerCase()
                        return live === slot && live !== "—"
                    }
                    return false
                }

                Layout.fillWidth: true
                height: 46

                color: flightModeWindow.activeRowIndex === rowIndex ? activeRowBg
                     : (isLiveActive ? "#1c2a1c" : (rowIndex % 2 === 0 ? rowEven : rowOdd))
                border.color: gridColor
                border.width: 1

                // Active left bar
                Rectangle {
                    width: 4; height: parent.height; anchors.left: parent.left
                    color: flightModeWindow.activeRowIndex === rowIndex ? accentColor
                         : (isLiveActive ? "#6fa020" : "transparent")
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 0

                    // Label
                    Item {
                        Layout.preferredWidth: 140
                        height: parent.height
                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                text: "Flight Mode " + (rowIndex + 1)
                                font.family: "Consolas"; font.pixelSize: 13
                                font.bold: flightModeWindow.activeRowIndex === rowIndex
                                color: flightModeWindow.activeRowIndex === rowIndex ? textPrimary : textSub
                            }
                            Rectangle {
                                visible: isLiveActive
                                width: 32; height: 16; radius: 8
                                color: "#1a3a1a"; border.color: accentColor; border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "LIVE"; font.family: "Consolas"
                                    font.pixelSize: 9; font.bold: true; color: accentColor
                                }
                            }
                        }
                    }

                    // ComboBox
                    Item {
                        Layout.preferredWidth: 150
                        height: parent.height

                        ComboBox {
                            id: modeCombo
                            anchors.verticalCenter: parent.verticalCenter
                            width: 138; height: 30
                            model: flightModeWindow.modeOptions

                            Component.onCompleted: {
                                currentIndex = flightModeWindow.modeOptions.indexOf(flightModes[rowIndex].mode)
                                if (currentIndex < 0) currentIndex = 0
                            }
                            Connections {
                                target: flightModeWindow
                                function onFlightModesChanged() {
                                    var idx = flightModeWindow.modeOptions.indexOf(flightModes[rowIndex].mode)
                                    if (idx >= 0 && modeCombo.currentIndex !== idx) modeCombo.currentIndex = idx
                                }
                            }
                            background: Rectangle {
                                color: "#2a2a2a"
                                border.color: flightModeWindow.activeRowIndex === rowIndex ? accentColor : gridColor
                                border.width: 1; radius: 4
                            }
                            contentItem: Text {
                                leftPadding: 8; text: modeCombo.displayText
                                font.family: "Consolas"; font.pixelSize: 12
                                color: flightModeWindow.activeRowIndex === rowIndex ? accentColor : textSub
                                verticalAlignment: Text.AlignVCenter
                            }
                            indicator: Text {
                                x: modeCombo.width - width - 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u25BE"; color: textMuted; font.pixelSize: 12
                            }
                            popup: Popup {
                                y: modeCombo.height + 2; width: modeCombo.width; padding: 2
                                background: Rectangle { color: "#222"; border.color: gridColor; border.width: 1; radius: 4 }
                                contentItem: ListView {
                                    implicitHeight: contentHeight; model: modeCombo.delegateModel; clip: true
                                }
                            }
                            delegate: ItemDelegate {
                                id: cDel; width: modeCombo.width
                                highlighted: modeCombo.highlightedIndex === model.index
                                contentItem: Text {
                                    text: modelData; font.family: "Consolas"; font.pixelSize: 12
                                    color: cDel.highlighted ? accentColor : textSub
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { color: cDel.highlighted ? "#1e3a1e" : "transparent" }
                            }
                            onActivated: {
                                var updated = flightModes.slice()
                                updated[rowIndex] = { mode: modeOptions[currentIndex], simple: updated[rowIndex].simple, superSimple: updated[rowIndex].superSimple }
                                flightModes = updated
                                flightModeWindow.updateActiveRow(rowIndex)
                            }
                        }
                    }

                    // Simple
                    Item {
                        Layout.preferredWidth: 75; height: parent.height
                        CheckBox {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Simple"; checked: flightModes[rowIndex].simple
                            font.family: "Consolas"; font.pixelSize: 12
                            contentItem: Text {
                                leftPadding: parent.indicator.width + 6
                                text: parent.text; font: parent.font; color: textMuted
                                verticalAlignment: Text.AlignVCenter
                            }
                            indicator: Rectangle {
                                width: 16; height: 16; radius: 3
                                border.color: parent.checked ? accentColor : gridColor
                                border.width: 1; color: "#2a2a2a"
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { width: 8; height: 8; radius: 2; color: accentColor; anchors.centerIn: parent; visible: parent.parent.checked }
                            }
                            onCheckedChanged: {
                                var u = flightModes.slice()
                                u[rowIndex] = { mode: u[rowIndex].mode, simple: checked, superSimple: u[rowIndex].superSimple }
                                flightModes = u
                            }
                        }
                    }

                    // Super Simple
                    Item {
                        Layout.preferredWidth: 115; height: parent.height
                        CheckBox {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Super Simple"; checked: flightModes[rowIndex].superSimple
                            font.family: "Consolas"; font.pixelSize: 12
                            contentItem: Text {
                                leftPadding: parent.indicator.width + 6
                                text: parent.text; font: parent.font; color: textMuted
                                verticalAlignment: Text.AlignVCenter
                            }
                            indicator: Rectangle {
                                width: 16; height: 16; radius: 3
                                border.color: parent.checked ? accentColor : gridColor
                                border.width: 1; color: "#2a2a2a"
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { width: 8; height: 8; radius: 2; color: accentColor; anchors.centerIn: parent; visible: parent.parent.checked }
                            }
                            onCheckedChanged: {
                                var u = flightModes.slice()
                                u[rowIndex] = { mode: u[rowIndex].mode, simple: u[rowIndex].simple, superSimple: checked }
                                flightModes = u
                            }
                        }
                    }

                    // PWM
                    Text {
                        Layout.fillWidth: true
                        text: flightModeWindow.pwmLabel(rowIndex)
                        font.family: "Consolas"; font.pixelSize: 12
                        font.bold: flightModeWindow.activeRowIndex === rowIndex
                        color: flightModeWindow.activeRowIndex === rowIndex ? accentColor : textMuted
                        verticalAlignment: Text.AlignVCenter; height: parent.height
                    }
                }

                MouseArea { anchors.fill: parent; z: -1; onClicked: flightModeWindow.updateActiveRow(rowIndex) }
            }
        }

        // ── SAVE ROW ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: "#1f1f1f"
            border.color: gridColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Button {
                    id: saveBtn
                    text: "💾 Write Modes"
                    font.pixelSize: 12
                    implicitWidth: 130; implicitHeight: 36
                    enabled: droneCommander !== null
                    background: Rectangle {
                        color: parent.pressed ? "#1a3a0a" : (parent.hovered ? "#2a4a1a" : "#1a3a1a")
                        border.color: accentColor; border.width: 1; radius: 4
                        opacity: parent.enabled ? 1.0 : 0.4
                    }
                    contentItem: Text {
                        text: parent.text; color: "white"; font.bold: true
                        font.pixelSize: 12; font.family: "Consolas"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (!droneCommander) {
                            saveHint.text = "❌ Not connected!"; saveHint.color = "#e24b4a"; saveTimer.restart(); return
                        }
                        var names = []
                        for (var i = 0; i < 6; i++) names.push(flightModes[i].mode)
                        droneCommander.saveAllFlightModes(names)
                        saveHint.text = "✅ Saving to drone..."; saveHint.color = accentColor; saveTimer.restart()
                    }
                }

                Text {
                    id: saveHint
                    text: "Changes take effect after saving."
                    font.family: "Consolas"; font.pixelSize: 12; color: textMuted
                }

                Item { Layout.fillWidth: true }

                Timer { id: saveTimer; interval: 3000; onTriggered: { saveHint.text = "Changes take effect after saving."; saveHint.color = textMuted } }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: flightModeWindow.doClose() }
}
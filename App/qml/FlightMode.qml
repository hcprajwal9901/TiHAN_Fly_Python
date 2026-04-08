import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Window {
    id: flightModeWindow
    title: "Flight Modes"


    minimumWidth:  1000
    minimumHeight: 600



    flags: Qt.Window | Qt.WindowStaysOnTopHint

    property var droneCommander: null
    property var droneModel: null
    property var flightModeWindowInstance: null

    property int    activeRowIndex: 0
    property string currentMode:    flightModes[0].mode
    property int    currentPwmLow:  pwmRanges[0][0]
    property int    currentPwmHigh: pwmRanges[0][1]

    property string liveActiveMode: "—"
    property int    liveRCPwm: 0

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

    // ── Color palette ─────────────────────────────────────────────────────
    readonly property color bgPage:        "#f5f7fa"
    readonly property color bgCard:        "#ffffff"
    readonly property color bgActiveRow:   "#f0fdf7"
    readonly property color bgHeader:      "#f8fafc"
    readonly property color borderColor:   "#d1d9e0"
    readonly property color borderLight:   "#eef0f3"
    readonly property color accentGreen:   "#1D9E75"
    readonly property color accentDark:    "#0f6e56"
    readonly property color textPrimary:   "#111827"
    readonly property color textSecondary: "#6b7280"
    readonly property color textMuted:     "#9ca3af"
    readonly property color saveBtnBg:     "#1D9E75"
    readonly property color saveBtnPress:  "#0f6e56"
    readonly property color closeBtnBg:    "#ffffff"
    readonly property color closeBtnHover: "#fef2f2"
    readonly property color closeBtnText:  "#6b7280"
    readonly property color closeBtnDanger:"#e24b4a"

    // ── Connections ───────────────────────────────────────────────────────
    Connections {
        target: flightModeWindow.droneCommander
        ignoreUnknownSignals: true

        function onFlightModesConfirmed(modeNames) {
            flightModeWindow.applyConfirmedModes(modeNames)
        }
        function onCurrentFlightModeChanged(modeName) {
            if (modeName && modeName !== "")
                flightModeWindow.liveActiveMode = modeName
        }
    }

    Connections {
        target: flightModeWindow.droneModel
        ignoreUnknownSignals: true

        function onFlightModeChanged() {
            var mode = flightModeWindow.droneModel
                       ? flightModeWindow.droneModel.flightMode : ""
            if (mode && mode !== "")
                flightModeWindow.liveActiveMode = mode
        }
        function onRcChannel5Changed() {
            var pwm = flightModeWindow.droneModel
                      ? flightModeWindow.droneModel.rcChannel5 : 0
            if (pwm > 800)
                flightModeWindow.liveRCPwm = pwm
        }
    }

    Timer {
        id: liveModePoller
        interval: 500
        running: flightModeWindow.visible && flightModeWindow.droneModel !== null
        repeat: true
        onTriggered: {
            if (!flightModeWindow.droneModel) return
            var mode = flightModeWindow.droneModel.flightMode
            if (mode && mode !== "" && mode !== flightModeWindow.liveActiveMode)
                flightModeWindow.liveActiveMode = mode
            var pwm = flightModeWindow.droneModel.rcChannel5
            if (pwm && pwm > 800 && pwm !== flightModeWindow.liveRCPwm)
                flightModeWindow.liveRCPwm = pwm
        }
    }

    Component.onCompleted: {
        if (droneModel) {
            var mode = droneModel.flightMode
            if (mode && mode !== "") liveActiveMode = mode
            var pwm = droneModel.rcChannel5
            if (pwm && pwm > 800) liveRCPwm = pwm
        }
    }

    function applyConfirmedModes(modeNames) {
        var updated = []
        for (var i = 0; i < 6; i++) {
            var name = (i < modeNames.length) ? modeNames[i] : "Stabilize"
            updated.push({
                mode: name,
                simple: flightModes[i].simple,
                superSimple: flightModes[i].superSimple
            })
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
                    && "flightModeWindowInstance" in mainWindowRef) {
                mainWindowRef.flightModeWindowInstance = null
            }
        } catch (e) {}
        flightModeWindow.visible = false
        flightModeWindow.close()
    }

    // ── Root ──────────────────────────────────────────────────────────────
    Rectangle {
        id: contentRoot
        width:  implicitWidth
        height: implicitHeight
        color: bgPage

        implicitWidth:  20 + 220 + 210 + 130 + 240 + 180 + 40
        implicitHeight: topBar.height + 16 + statusBar.height + 16
                        + tableContainer.height + 20 + saveRow.height + 24

        // ── TOP BAR ───────────────────────────────────────────────────────
        Rectangle {
            id: topBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 64
            color: bgCard
            border.color: borderLight
            border.width: 1

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 24
                spacing: 12

                Rectangle {
                    width: 5; height: 26
                    color: accentGreen; radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "\u25BA FLIGHT MODES"
                    font.family: "Consolas"
                    font.pixelSize: 16
                    font.bold: true
                    color: accentGreen
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                id: closeBtnRect
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 20
                width: 100; height: 40
                radius: 8
                color: closeMouse.pressed       ? closeBtnHover
                     : closeMouse.containsMouse ? closeBtnHover
                     : closeBtnBg
                border.color: closeMouse.containsMouse ? "#f09595" : borderColor
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "\u2715"
                        font.family: "Consolas"
                        font.pixelSize: 13
                        color: closeMouse.containsMouse ? closeBtnDanger : closeBtnText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Close"
                        font.family: "Consolas"
                        font.pixelSize: 14
                        color: closeMouse.containsMouse ? closeBtnDanger : closeBtnText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: flightModeWindow.doClose()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left; anchors.right: parent.right
                height: 1; color: borderLight
            }
        }

        // ── STATUS BAR ────────────────────────────────────────────────────
        Rectangle {
            id: statusBar
            anchors.top: topBar.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            height: 64
            color: bgCard
            border.color: borderColor
            border.width: 1
            radius: 12

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 24
                spacing: 0

                Row {
                    spacing: 10
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: flightModeWindow.liveActiveMode !== "—"
                               ? accentGreen : "#d1d9e0"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "ACTIVE MODE"
                            font.family: "Consolas"; font.pixelSize: 10
                            color: textMuted
                        }
                        Text {
                            text: flightModeWindow.liveActiveMode
                            font.family: "Consolas"; font.pixelSize: 15
                            font.bold: true; color: textPrimary
                        }
                    }
                }

                Item { width: 28; height: 1 }
                Rectangle { width: 1; height: 32; color: borderColor; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 28; height: 1 }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "SELECTED SLOT"
                        font.family: "Consolas"; font.pixelSize: 10
                        color: textMuted
                    }
                    Text {
                        text: flightModeWindow.currentMode
                        font.family: "Consolas"; font.pixelSize: 15
                        font.bold: true; color: textPrimary
                    }
                }

                Item { width: 28; height: 1 }
                Rectangle { width: 1; height: 32; color: borderColor; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 28; height: 1 }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "CURRENT PWM"
                        font.family: "Consolas"; font.pixelSize: 10
                        color: textMuted
                    }
                    Text {
                        text: flightModeWindow.activeRowIndex === 5
                              ? flightModeWindow.currentPwmLow + "+"
                              : flightModeWindow.currentPwmLow + " \u2014 " + flightModeWindow.currentPwmHigh
                        font.family: "Consolas"; font.pixelSize: 15
                        font.bold: true; color: textPrimary
                    }
                }
            }
        }

        // ── TABLE ─────────────────────────────────────────────────────────
        Rectangle {
            id: tableContainer
            anchors.top: statusBar.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            height: tableColumn.implicitHeight + 1
            color: bgCard
            border.color: borderColor
            border.width: 1
            radius: 12
            clip: true

            Column {
                id: tableColumn
                anchors.left: parent.left
                anchors.right: parent.right

                Rectangle {
                    width: parent.width; height: 44
                    color: bgHeader

                    Row {
                        anchors.fill: parent; anchors.leftMargin: 20

                        Item  { width: 220; height: parent.height }
                        Text  { width: 210; height: parent.height; text: "MODE";              font.family: "Consolas"; font.pixelSize: 11; color: textMuted; verticalAlignment: Text.AlignVCenter }
                        Text  { width: 130; height: parent.height; text: "SIMPLE";            font.family: "Consolas"; font.pixelSize: 11; color: textMuted; verticalAlignment: Text.AlignVCenter }
                        Text  { width: 240; height: parent.height; text: "SUPER SIMPLE MODE"; font.family: "Consolas"; font.pixelSize: 11; color: textMuted; verticalAlignment: Text.AlignVCenter }
                        Text  { width: 180; height: parent.height; text: "PWM RANGE";         font.family: "Consolas"; font.pixelSize: 11; color: textMuted; verticalAlignment: Text.AlignVCenter }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        height: 1; color: borderLight
                    }
                }

                Repeater {
                    id: modeRepeater
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
                                var aliases = {
                                    "althold": "althold", "alt_hold": "althold",
                                    "poshold": "poshold", "pos_hold": "poshold"
                                }
                                live = aliases[live] || live
                                slot = aliases[slot] || slot
                                return live === slot && live !== "—"
                            }
                            return false
                        }

                        width: tableColumn.width
                        height: 66
                        color: flightModeWindow.activeRowIndex === rowIndex
                               ? bgActiveRow
                               : (isLiveActive ? "#f0fff8" : "transparent")

                        Rectangle {
                            width: 4; height: parent.height
                            color: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                   ? accentGreen
                                   : (modeRow.isLiveActive ? "#22c55e" : "transparent")
                            anchors.left: parent.left
                        }

                        Row {
                            anchors.fill: parent; anchors.leftMargin: 20

                            Item {
                                width: 220; height: parent.height

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Text {
                                        text: "Flight Mode " + (modeRow.rowIndex + 1)
                                        font.family: "Consolas"
                                        font.pixelSize: 14
                                        font.bold: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                        color: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                               ? textPrimary : textSecondary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        visible: modeRow.isLiveActive
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: liveLbl.width + 12; height: 20; radius: 10
                                        color: "#dcfce7"
                                        Text {
                                            id: liveLbl
                                            anchors.centerIn: parent
                                            text: "LIVE"
                                            font.family: "Consolas"; font.pixelSize: 10
                                            font.bold: true; color: "#15803d"
                                        }
                                    }
                                }
                            }

                            Item {
                                width: 210; height: parent.height

                                ComboBox {
                                    id: modeCombo
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 170; height: 38
                                    model: flightModeWindow.modeOptions

                                    Component.onCompleted: {
                                        currentIndex = flightModeWindow.modeOptions.indexOf(
                                            flightModes[modeRow.rowIndex].mode)
                                        if (currentIndex < 0) currentIndex = 0
                                    }

                                    Connections {
                                        target: flightModeWindow
                                        function onFlightModesChanged() {
                                            var wanted = flightModes[modeRow.rowIndex].mode
                                            var idx    = flightModeWindow.modeOptions.indexOf(wanted)
                                            if (idx >= 0 && modeCombo.currentIndex !== idx)
                                                modeCombo.currentIndex = idx
                                        }
                                    }

                                    background: Rectangle {
                                        color: bgCard
                                        border.color: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                                      ? accentGreen : borderColor
                                        border.width: 1; radius: 8
                                    }
                                    contentItem: Text {
                                        leftPadding: 12
                                        text: modeCombo.displayText
                                        font.family: "Consolas"; font.pixelSize: 14
                                        font.bold: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                        color: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                               ? accentDark : "#374151"
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    indicator: Text {
                                        x: modeCombo.width - width - 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u25BE"; color: textMuted; font.pixelSize: 14
                                    }
                                    popup: Popup {
                                        y: modeCombo.height + 4
                                        width: modeCombo.width; padding: 6
                                        background: Rectangle { color: bgCard; border.color: borderColor; radius: 8 }
                                        contentItem: ListView {
                                            implicitHeight: contentHeight
                                            model: modeCombo.delegateModel; clip: true
                                        }
                                    }
                                    delegate: ItemDelegate {
                                        id: comboDelegate
                                        width: modeCombo.width
                                        highlighted: modeCombo.highlightedIndex === model.index
                                        contentItem: Text {
                                            text: modelData
                                            font.family: "Consolas"; font.pixelSize: 13
                                            color: comboDelegate.highlighted ? accentDark : "#374151"
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            color: comboDelegate.highlighted ? "#f0fdf7" : "transparent"
                                        }
                                    }
                                    onActivated: {
                                        var updated = flightModes.slice()
                                        updated[modeRow.rowIndex] = {
                                            mode: flightModeWindow.modeOptions[currentIndex],
                                            simple: updated[modeRow.rowIndex].simple,
                                            superSimple: updated[modeRow.rowIndex].superSimple
                                        }
                                        flightModes = updated
                                        flightModeWindow.updateActiveRow(modeRow.rowIndex)
                                    }
                                }
                            }

                            Item {
                                width: 130; height: parent.height

                                CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Simple"
                                    checked: flightModes[modeRow.rowIndex].simple
                                    font.family: "Consolas"; font.pixelSize: 13

                                    contentItem: Text {
                                        leftPadding: parent.indicator.width + 8
                                        text: parent.text; font: parent.font
                                        color: textMuted; verticalAlignment: Text.AlignVCenter
                                    }
                                    indicator: Rectangle {
                                        width: 18; height: 18; radius: 4
                                        border.color: parent.checked ? accentGreen : borderColor
                                        border.width: 1; color: "transparent"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            width: 10; height: 10; radius: 2; color: accentGreen
                                            anchors.centerIn: parent
                                            visible: parent.parent.checked
                                        }
                                    }
                                    onCheckedChanged: {
                                        var updated = flightModes.slice()
                                        updated[modeRow.rowIndex] = {
                                            mode: updated[modeRow.rowIndex].mode,
                                            simple: checked,
                                            superSimple: updated[modeRow.rowIndex].superSimple
                                        }
                                        flightModes = updated
                                    }
                                }
                            }

                            Item {
                                width: 240; height: parent.height

                                CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Super Simple Mode"
                                    checked: flightModes[modeRow.rowIndex].superSimple
                                    font.family: "Consolas"; font.pixelSize: 13

                                    contentItem: Text {
                                        leftPadding: parent.indicator.width + 8
                                        text: parent.text; font: parent.font
                                        color: textMuted; verticalAlignment: Text.AlignVCenter
                                    }
                                    indicator: Rectangle {
                                        width: 18; height: 18; radius: 4
                                        border.color: parent.checked ? accentGreen : borderColor
                                        border.width: 1; color: "transparent"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            width: 10; height: 10; radius: 2; color: accentGreen
                                            anchors.centerIn: parent
                                            visible: parent.parent.checked
                                        }
                                    }
                                    onCheckedChanged: {
                                        var updated = flightModes.slice()
                                        updated[modeRow.rowIndex] = {
                                            mode: updated[modeRow.rowIndex].mode,
                                            simple: updated[modeRow.rowIndex].simple,
                                            superSimple: checked
                                        }
                                        flightModes = updated
                                    }
                                }
                            }

                            Text {
                                width: 180; height: parent.height
                                text: flightModeWindow.pwmLabel(modeRow.rowIndex)
                                font.family: "Consolas"; font.pixelSize: 13
                                font.bold: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                color: flightModeWindow.activeRowIndex === modeRow.rowIndex
                                       ? accentGreen : textMuted
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Rectangle {
                            visible: modeRow.rowIndex < 5
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left; anchors.right: parent.right
                            height: 1; color: borderLight
                        }

                        MouseArea {
                            anchors.fill: parent; z: -1
                            onClicked: flightModeWindow.updateActiveRow(modeRow.rowIndex)
                        }
                    }
                }
            }
        }

        // ── SAVE ROW ──────────────────────────────────────────────────────
        Row {
            id: saveRow
            anchors.top: tableContainer.bottom; anchors.topMargin: 20
            anchors.left: parent.left;          anchors.leftMargin: 20
            spacing: 16
            height: 46

            Button {
                id: saveBtn
                width: 160; height: 46
                text: "\uD83D\uDCBE  Save Modes"
                enabled: droneCommander !== null

                background: Rectangle {
                    color: saveBtn.pressed ? saveBtnPress : saveBtnBg
                    radius: 8; opacity: saveBtn.enabled ? 1.0 : 0.5
                }
                contentItem: Text {
                    text: saveBtn.text
                    font.family: "Consolas"; font.pixelSize: 14; font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                }
                onClicked: {
                    if (!droneCommander) {
                        saveHint.text  = "Not connected to drone!"
                        saveHint.color = "#e24b4a"
                        saveTimer.restart()
                        return
                    }
                    var modeNames = []
                    for (var i = 0; i < 6; i++)
                        modeNames.push(flightModes[i].mode)
                    droneCommander.saveAllFlightModes(modeNames)
                    saveHint.text  = "Saving to drone..."
                    saveHint.color = accentGreen
                    saveTimer.restart()
                }
            }

            Text {
                id: saveHint
                anchors.verticalCenter: saveBtn.verticalCenter
                text: "Changes take effect after saving."
                font.family: "Consolas"; font.pixelSize: 13; color: textMuted
            }

            Timer {
                id: saveTimer; interval: 3000
                onTriggered: {
                    saveHint.text  = "Changes take effect after saving."
                    saveHint.color = textMuted
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: flightModeWindow.doClose()
    }
}
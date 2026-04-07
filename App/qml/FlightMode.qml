import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Window {
    id: flightModeWindow
    title: "Flight Modes"
    visibility: Window.FullScreen
    flags: Qt.Window | Qt.WindowStaysOnTopHint

    property var droneCommander: null
    property var droneModel: null

    property int activeRowIndex: 0
    property string currentMode: flightModes[0].mode
    property int currentPwmLow: pwmRanges[0][0]
    property int currentPwmHigh: pwmRanges[0][1]

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

    Rectangle {
        anchors.fill: parent
        color: "#0d1117"

        // ── Header bar ────────────────────────────────────
        Rectangle {
            id: topBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 48
            color: "#0d1117"
            border.color: "#21262d"
            border.width: 0

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 20
                spacing: 10

                // Teal accent bar
                Rectangle {
                    width: 4
                    height: 24
                    color: "#00e5b0"
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "\u25BA FLIGHT MODES"
                    font.family: "Consolas"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#00e5b0"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Status bar ────────────────────────────────────
        Rectangle {
            id: statusBar
            anchors.top: topBar.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            height: 52
            color: "#161b22"
            border.color: "#21262d"
            border.width: 1
            radius: 8

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 20
                spacing: 40

                // Current Mode
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: "#00e5b0"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "CURRENT MODE"
                        font.family: "Consolas"
                        font.pixelSize: 10
                        color: "#8b949e"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: flightModeWindow.currentMode
                        font.family: "Consolas"
                        font.pixelSize: 10
                        color: "#e6edf3"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Separator
                Rectangle { width: 1; height: 20; color: "#21262d"; anchors.verticalCenter: parent.verticalCenter }

                // Current PWM
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "CURRENT PWM"
                        font.family: "Consolas"
                        font.pixelSize: 10
                        color: "#8b949e"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: flightModeWindow.activeRowIndex === 5
                              ? flightModeWindow.currentPwmLow + "+"
                              : flightModeWindow.currentPwmLow + " \u2014 " + flightModeWindow.currentPwmHigh
                        font.family: "Consolas"
                        font.pixelSize: 10
                        color: "#e6edf3"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ── Table ─────────────────────────────────────────
        Rectangle {
            id: tableContainer
            anchors.top: statusBar.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            height: tableColumn.implicitHeight + 1
            color: "#161b22"
            border.color: "#21262d"
            border.width: 1
            radius: 8
            clip: true

            Column {
                id: tableColumn
                anchors.left: parent.left
                anchors.right: parent.right

                // Table header
                Rectangle {
                    width: parent.width
                    height: 36
                    color: "transparent"
                    border.color: "#21262d"
                    border.width: 0

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16

                        Item { width: 140; height: parent.height }

                        Text {
                            width: 160; height: parent.height
                            text: "MODE"
                            font.family: "Consolas"
                            font.pixelSize: 9
                            color: "#8b949e"
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            width: 110; height: parent.height
                            text: "SIMPLE"
                            font.family: "Consolas"
                            font.pixelSize: 9
                            color: "#8b949e"
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            width: 160; height: parent.height
                            text: "SUPER SIMPLE MODE"
                            font.family: "Consolas"
                            font.pixelSize: 9
                            color: "#8b949e"
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            width: 140; height: parent.height
                            text: "PWM RANGE"
                            font.family: "Consolas"
                            font.pixelSize: 9
                            color: "#8b949e"
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: "#21262d"
                    }
                }

                // Mode rows
                Repeater {
                    model: 6

                    delegate: Rectangle {
                        id: modeRow
                        width: tableColumn.width
                        height: 52
                        color: flightModeWindow.activeRowIndex === index
                               ? "#161b22" : "transparent"

                        // Left active indicator
                        Rectangle {
                            width: 3
                            height: parent.height
                            color: "#00e5b0"
                            visible: flightModeWindow.activeRowIndex === index
                            anchors.left: parent.left
                            radius: 2
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16

                            // Row label
                            Text {
                                width: 140
                                height: parent.height
                                text: "Flight Mode " + (index + 1)
                                font.family: "Consolas"
                                font.pixelSize: 11
                                color: flightModeWindow.activeRowIndex === index
                                       ? "#e6edf3" : "#8b949e"
                                verticalAlignment: Text.AlignVCenter
                            }

                            // Mode dropdown
                            Item {
                                width: 160
                                height: parent.height

                                ComboBox {
                                    id: modeCombo
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 140
                                    height: 32
                                    model: flightModeWindow.modeOptions
                                    currentIndex: flightModeWindow.modeOptions.indexOf(
                                                      flightModes[index].mode)

                                    background: Rectangle {
                                        color: flightModeWindow.activeRowIndex === index
                                               ? "#0f2a22" : "#21262d"
                                        border.color: flightModeWindow.activeRowIndex === index
                                                      ? "#00e5b0" : "#30363d"
                                        border.width: 1
                                        radius: 6
                                    }

                                    contentItem: Text {
                                        leftPadding: 10
                                        text: modeCombo.displayText
                                        font.family: "Consolas"
                                        font.pixelSize: 11
                                        color: flightModeWindow.activeRowIndex === index
                                               ? "#00e5b0" : "#e6edf3"
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    indicator: Text {
                                        x: modeCombo.width - width - 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u25BE"
                                        color: "#8b949e"
                                        font.pixelSize: 12
                                    }

                                    popup: Popup {
                                        y: modeCombo.height + 2
                                        width: modeCombo.width
                                        padding: 4
                                        background: Rectangle {
                                            color: "#21262d"
                                            border.color: "#30363d"
                                            radius: 6
                                        }
                                        contentItem: ListView {
                                            implicitHeight: contentHeight
                                            model: modeCombo.delegateModel
                                            clip: true
                                        }
                                    }

                                    delegate: ItemDelegate {
                                        width: modeCombo.width
                                        contentItem: Text {
                                            text: modelData
                                            font.family: "Consolas"
                                            font.pixelSize: 11
                                            color: "#e6edf3"
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            color: highlighted ? "#30363d" : "transparent"
                                        }
                                        highlighted: modeCombo.highlightedIndex === index
                                    }

                                    onActivated: {
                                        var updated = flightModes.slice()
                                        updated[index] = {
                                            mode: flightModeWindow.modeOptions[currentIndex],
                                            simple: updated[index].simple,
                                            superSimple: updated[index].superSimple
                                        }
                                        flightModes = updated
                                        flightModeWindow.updateActiveRow(index)

                                        if (droneCommander)
                                            droneCommander.setMode(flightModeWindow.modeOptions[currentIndex])
                                    }
                                }
                            }

                            // Simple checkbox
                            Item {
                                width: 110
                                height: parent.height

                                CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Simple"
                                    checked: flightModes[index].simple
                                    font.family: "Consolas"
                                    font.pixelSize: 11

                                    contentItem: Text {
                                        leftPadding: parent.indicator.width + 6
                                        text: parent.text
                                        font: parent.font
                                        color: "#8b949e"
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    indicator: Rectangle {
                                        width: 14; height: 14
                                        radius: 3
                                        border.color: parent.checked ? "#00e5b0" : "#30363d"
                                        border.width: 1
                                        color: "transparent"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            width: 8; height: 8; radius: 2
                                            color: "#00e5b0"
                                            anchors.centerIn: parent
                                            visible: parent.parent.checked
                                        }
                                    }

                                    onCheckedChanged: {
                                        var updated = flightModes.slice()
                                        updated[index] = {
                                            mode: updated[index].mode,
                                            simple: checked,
                                            superSimple: updated[index].superSimple
                                        }
                                        flightModes = updated
                                    }
                                }
                            }

                            // Super Simple checkbox
                            Item {
                                width: 160
                                height: parent.height

                                CheckBox {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Super Simple Mode"
                                    checked: flightModes[index].superSimple
                                    font.family: "Consolas"
                                    font.pixelSize: 11

                                    contentItem: Text {
                                        leftPadding: parent.indicator.width + 6
                                        text: parent.text
                                        font: parent.font
                                        color: "#8b949e"
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    indicator: Rectangle {
                                        width: 14; height: 14
                                        radius: 3
                                        border.color: parent.checked ? "#00e5b0" : "#30363d"
                                        border.width: 1
                                        color: "transparent"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            width: 8; height: 8; radius: 2
                                            color: "#00e5b0"
                                            anchors.centerIn: parent
                                            visible: parent.parent.checked
                                        }
                                    }

                                    onCheckedChanged: {
                                        var updated = flightModes.slice()
                                        updated[index] = {
                                            mode: updated[index].mode,
                                            simple: updated[index].simple,
                                            superSimple: checked
                                        }
                                        flightModes = updated
                                    }
                                }
                            }

                            // PWM Range
                            Text {
                                width: 140
                                height: parent.height
                                text: flightModeWindow.pwmLabel(index)
                                font.family: "Consolas"
                                font.pixelSize: 11
                                color: flightModeWindow.activeRowIndex === index
                                       ? "#00e5b0" : "#8b949e"
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Bottom divider
                        Rectangle {
                            visible: index < 5
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#21262d"
                        }

                        // Row hover / click
                        MouseArea {
                            anchors.fill: parent
                            onClicked: flightModeWindow.updateActiveRow(index)
                        }
                    }
                }
            }
        }

        // ── Save Modes button ─────────────────────────────
        Row {
            id: saveRow
            anchors.top: tableContainer.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.leftMargin: 16
            spacing: 14
            anchors.verticalCenter: undefined

            Button {
                id: saveBtn
                width: 140
                height: 38
                text: "\uD83D\uDCBE  Save Modes"

                background: Rectangle {
                    color: saveBtn.pressed ? "#00c49a" : "#00e5b0"
                    radius: 6
                }
                contentItem: Text {
                    text: saveBtn.text
                    font.family: "Consolas"
                    font.pixelSize: 11
                    font.bold: true
                    color: "#0d1117"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    saveHint.text = "Saved successfully!"
                    saveHint.color = "#00e5b0"
                    saveTimer.restart()

                    if (droneCommander) {
                        for (var i = 0; i < 6; i++) {
                            droneCommander.setFlightMode(i, flightModes[i].mode,
                                                         flightModes[i].simple,
                                                         flightModes[i].superSimple)
                        }
                    }
                }
            }

            Text {
                id: saveHint
                anchors.verticalCenter: saveBtn.verticalCenter
                text: "Changes take effect after saving."
                font.family: "Consolas"
                font.pixelSize: 10
                color: "#8b949e"
            }

            Timer {
                id: saveTimer
                interval: 2000
                onTriggered: {
                    saveHint.text = "Changes take effect after saving."
                    saveHint.color = "#8b949e"
                }
            }
        }

        // ── Close button ──────────────────────────────────
        Button {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: 16
            anchors.rightMargin: 16
            width: 80
            height: 34
            text: "Close"

            background: Rectangle {
                color: parent.pressed ? "#30363d" : "#21262d"
                border.color: "#30363d"
                border.width: 1
                radius: 6
            }
            contentItem: Text {
                text: parent.text
                font.family: "Consolas"
                font.pixelSize: 11
                color: "#8b949e"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: {
                if (typeof mainWindowRef !== "undefined" && mainWindowRef)
                    mainWindowRef.flightModeWindowInstance = null
                flightModeWindow.close()
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (typeof mainWindowRef !== "undefined" && mainWindowRef)
                mainWindowRef.flightModeWindowInstance = null
            flightModeWindow.close()
        }
    }
}
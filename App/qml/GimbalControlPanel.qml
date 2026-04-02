import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

/**
 * GimbalControlPanel.qml
 * =======================
 * Gimbal pitch/yaw control panel with mode switching and ROI support.
 *
 * Context properties required:
 *   • gimbalManager  — GimbalManager instance
 */

Rectangle {
    id: root
    width:  320
    height: 380
    color:  "#111820"
    radius: 10
    border.color: "#1e3a55"
    border.width: 1
    clip: true

    // ── Internal state ───────────────────────────────────────────────────────
    property real   pitchDeg:    0.0
    property real   yawDeg:      0.0
    property string currentMode: "follow"
    property string feedbackMsg: "Gimbal system ready"

    // ── Header ───────────────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 42
        color:  "#0d1620"
        radius: 10
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 10; color: parent.color
        }

        Text {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: "🎯  GIMBAL CONTROLS"
            color: "#7ab4e0"
            font { pixelSize: 13; bold: true; letterSpacing: 1 }
        }

        // Mode badge
        Rectangle {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: modeBadge.width + 12; height: 18; radius: 4
            color: "#0d2535"
            border.color: "#2a5a80"; border.width: 1
            Text {
                id: modeBadge
                anchors.centerIn: parent
                text: root.currentMode.toUpperCase()
                color: "#80c0ff"; font.pixelSize: 10; font.bold: true
            }
        }
    }

    // ── Content area ─────────────────────────────────────────────────────────
    ColumnLayout {
        anchors {
            top: header.bottom; topMargin: 12
            left: parent.left; leftMargin: 14
            right: parent.right; rightMargin: 14
            bottom: parent.bottom; bottomMargin: 12
        }
        spacing: 10

        // ── Mode Selector ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text { text: "CONTROL MODE"; color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ["follow", "lock", "roi"]
                    delegate: Button {
                        Layout.fillWidth: true; height: 30
                        text: modelData.toUpperCase()
                        property bool isActive: root.currentMode === modelData

                        background: Rectangle {
                            color: isActive ? "#1a4a70"
                                   : (parent.pressed ? "#1a3050" : "#0d1e30")
                            radius: 5
                            border.color: isActive ? "#3a8abf" : "#1e3a55"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            color: isActive ? "#c0e4ff" : "#4a7090"
                            font.pixelSize: 11; font.bold: isActive
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            root.currentMode = modelData
                            if (typeof gimbalManager !== "undefined")
                                gimbalManager.setMode(modelData)
                        }
                    }
                }
            }
        }

        // ── Divider ──────────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e3a55" }

        // ── Pitch Slider ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Text { text: "PITCH"; color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.pitchDeg.toFixed(1) + "°"
                    color: "#80c0ff"; font.pixelSize: 11
                }
            }

            Slider {
                id: pitch_slider
                objectName: "pitch_slider"
                Layout.fillWidth: true
                from: -90.0; to: 45.0; stepSize: 0.5; value: root.pitchDeg

                background: Rectangle {
                    x: pitch_slider.leftPadding
                    y: pitch_slider.topPadding + pitch_slider.availableHeight / 2 - 2
                    width: pitch_slider.availableWidth; height: 4; radius: 2
                    color: "#0d1e2e"
                    Rectangle {
                        // Show negative (downward) motion distinctly
                        x: pitch_slider.visualPosition > 0.597 ? 0
                           : pitch_slider.visualPosition * parent.width
                        width: Math.abs(0.597 - pitch_slider.visualPosition) * parent.width
                        height: parent.height; color: "#3a7abf"; radius: 2
                    }
                }
                handle: Rectangle {
                    x: pitch_slider.leftPadding + pitch_slider.visualPosition * pitch_slider.availableWidth - width / 2
                    y: pitch_slider.topPadding + pitch_slider.availableHeight / 2 - height / 2
                    width: 18; height: 18; radius: 9
                    color: pitch_slider.pressed ? "#4aaaef" : "#2a8acf"
                    border.color: "#6ac0ff"; border.width: 1
                }

                onValueChanged: {
                    root.pitchDeg = value
                    if (typeof gimbalManager !== "undefined")
                        gimbalManager.setPitch(value)
                }
            }

            // Axis labels
            RowLayout {
                Layout.fillWidth: true
                Text { text: "−90° (Down)"; color: "#304555"; font.pixelSize: 9 }
                Item { Layout.fillWidth: true }
                Text { text: "0°"; color: "#304555"; font.pixelSize: 9 }
                Item { Layout.fillWidth: true }
                Text { text: "+45° (Up)"; color: "#304555"; font.pixelSize: 9 }
            }
        }

        // ── Yaw Slider ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Text { text: "YAW"; color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.yawDeg.toFixed(1) + "°"
                    color: "#80c0ff"; font.pixelSize: 11
                }
            }

            Slider {
                id: yaw_slider
                objectName: "yaw_slider"
                Layout.fillWidth: true
                from: -180.0; to: 180.0; stepSize: 1.0; value: root.yawDeg

                background: Rectangle {
                    x: yaw_slider.leftPadding
                    y: yaw_slider.topPadding + yaw_slider.availableHeight / 2 - 2
                    width: yaw_slider.availableWidth; height: 4; radius: 2
                    color: "#0d1e2e"
                    Rectangle {
                        x: yaw_slider.visualPosition > 0.5 ? 0.5 * parent.width
                           : yaw_slider.visualPosition * parent.width
                        width: Math.abs(0.5 - yaw_slider.visualPosition) * parent.width
                        height: parent.height; color: "#bf7a3a"; radius: 2
                    }
                }
                handle: Rectangle {
                    x: yaw_slider.leftPadding + yaw_slider.visualPosition * yaw_slider.availableWidth - width / 2
                    y: yaw_slider.topPadding + yaw_slider.availableHeight / 2 - height / 2
                    width: 18; height: 18; radius: 9
                    color: yaw_slider.pressed ? "#efaa4a" : "#cf8a2a"
                    border.color: "#ffca8a"; border.width: 1
                }

                onValueChanged: {
                    root.yawDeg = value
                    if (typeof gimbalManager !== "undefined")
                        gimbalManager.setYaw(value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "−180° (Left)"; color: "#304555"; font.pixelSize: 9 }
                Item { Layout.fillWidth: true }
                Text { text: "0°"; color: "#304555"; font.pixelSize: 9 }
                Item { Layout.fillWidth: true }
                Text { text: "+180° (Right)"; color: "#304555"; font.pixelSize: 9 }
            }
        }

        // ── Divider ──────────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e3a55" }

        // ── Quick Action Buttons ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                Layout.fillWidth: true; height: 32
                text: "⚫ Center"
                background: Rectangle {
                    color: parent.pressed ? "#1a3050" : "#0d1e30"
                    radius: 5; border.color: "#2a5a80"; border.width: 1
                }
                contentItem: Text {
                    text: parent.text; color: "#60a0d0"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    pitch_slider.value = 0
                    yaw_slider.value   = 0
                    if (typeof gimbalManager !== "undefined")
                        gimbalManager.centerGimbal()
                }
            }

            Button {
                Layout.fillWidth: true; height: 32
                text: "⬇ Nadir"
                background: Rectangle {
                    color: parent.pressed ? "#1a3050" : "#0d1e30"
                    radius: 5; border.color: "#2a5a80"; border.width: 1
                }
                contentItem: Text {
                    text: parent.text; color: "#60a0d0"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    pitch_slider.value = -90
                    yaw_slider.value   = 0
                    if (typeof gimbalManager !== "undefined")
                        gimbalManager.setPitchYaw(-90, 0)
                }
            }
        }

        // ── Spacer ────────────────────────────────────────────────────────────
        Item { Layout.fillHeight: true }

        // ── Feedback ──────────────────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            text:  root.feedbackMsg
            color: "#406080"; font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    // ── Python signal connections ─────────────────────────────────────────────
    Connections {
        target: typeof gimbalManager !== "undefined" ? gimbalManager : null

        function onCommandFeedback(msg) {
            root.feedbackMsg = msg
        }
        function onPitchChanged(p) {
            // Update display from MAVLink feedback (don't re-trigger slider)
            root.pitchDeg = p
        }
        function onYawChanged(y) {
            root.yawDeg = y
        }
        function onModeChanged(m) {
            root.currentMode = m
        }
    }
}

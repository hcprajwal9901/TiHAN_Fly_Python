import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

/**
 * CameraControlPanel.qml
 * =======================
 * Camera control UI: start/stop capture, zoom, focus, camera switching.
 *
 * Context properties required:
 *   • cameraManager       — CameraManager instance
 *   • videoStreamManager  — VideoStreamManager instance (for RTSP URL input)
 */

Rectangle {
    id: root
    width:  360
    height: 420
    color:  "#111820"
    radius: 10
    border.color: "#1e3a55"
    border.width: 1
    clip: true

    // ── Internal state ───────────────────────────────────────────────────────
    property bool isRecording:   false
    property bool isCapturing:   false
    property string feedbackMsg: "Camera system ready"
    property var    cameraList:  typeof cameraManager !== "undefined"
                                 ? cameraManager.cameraList : ["cam1", "cam2", "cam3"]

    // ── Header ───────────────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 42
        color:  "#0d1620"
        radius: 10

        // Round bottom edge only via clip + inner rect
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 10; color: parent.color
        }

        Text {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: "📷  CAMERA CONTROLS"
            color: "#7ab4e0"
            font { pixelSize: 13; bold: true; letterSpacing: 1 }
        }

        // Active camera indicator dot
        Rectangle {
            width: 8; height: 8; radius: 4
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            color: typeof cameraManager !== "undefined" ? "#44ff88" : "#666666"
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

        // ── Camera Selector ──────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "ACTIVE CAMERA"
                color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1
            }

            ComboBox {
                id: cameraSelector
                Layout.fillWidth: true
                height: 32
                model:  root.cameraList.length > 0 ? root.cameraList : ["cam1"]

                background: Rectangle {
                    color: "#1a2d40"; radius: 5
                    border.color: "#2a5a80"; border.width: 1
                }
                contentItem: Text {
                    leftPadding: 8
                    text:        cameraSelector.displayText
                    color:       "#c0ddf0"; font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }

                onActivated: {
                    if (typeof cameraManager !== "undefined") {
                        cameraManager.setActiveCamera(model[index])
                        if (typeof videoStreamManager !== "undefined")
                            videoStreamManager.switchActiveCamera(model[index])
                    }
                }
            }
        }

        // ── RTSP Stream Control ──────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "RTSP STREAM URL"
                color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                TextField {
                    id: rtspUrlField
                    Layout.fillWidth: true
                    height: 32
                    placeholderText: "rtsp://192.168.1.10/stream"
                    color: "#c0ddf0"
                    font.pixelSize: 11
                    background: Rectangle {
                        color: "#0d1e2e"; radius: 5
                        border.color: rtspUrlField.activeFocus ? "#3a8ac0" : "#1e3a55"
                        border.width: 1
                    }
                }

                Button {
                    id: connectBtn
                    width: 80; height: 32
                    text: typeof videoStreamManager !== "undefined"
                          && videoStreamManager.isStreaming(cameraSelector.currentText)
                          ? "Disconnect" : "Connect"

                    background: Rectangle {
                        color: connectBtn.pressed ? "#1a5a30"
                               : (connectBtn.hovered ? "#1e6a38" : "#154826")
                        radius: 5
                        border.color: "#2a9a4a"; border.width: 1
                    }
                    contentItem: Text {
                        text: connectBtn.text; color: "#60ff90"
                        font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (typeof videoStreamManager === "undefined") return
                        var camId = cameraSelector.currentText
                        if (videoStreamManager.isStreaming(camId)) {
                            videoStreamManager.stopStream(camId)
                        } else {
                            videoStreamManager.startStream(camId, rtspUrlField.text.trim())
                        }
                    }
                }
            }
        }

        // ── Divider ──────────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e3a55" }

        // ── Capture Buttons ──────────────────────────────────────────────────
        Text {
            text: "CAPTURE"
            color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Image Capture
            Button {
                id: snapBtn
                Layout.fillWidth: true; height: 36
                text: "📸  Snapshot"

                background: Rectangle {
                    color: snapBtn.pressed ? "#2a3a55" : (snapBtn.hovered ? "#1e3055" : "#162540")
                    radius: 6; border.color: "#3a6a9a"; border.width: 1
                }
                contentItem: Text {
                    text: snapBtn.text; color: "#80c0ff"
                    font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    if (typeof cameraManager !== "undefined")
                        cameraManager.startImageCapture()
                }
            }

            // Video Record toggle
            Button {
                id: recordBtn
                Layout.fillWidth: true; height: 36
                text: root.isRecording ? "⏹  Stop Rec" : "⏺  Record"

                background: Rectangle {
                    color: root.isRecording
                           ? (recordBtn.pressed ? "#5a1010" : "#3a0a0a")
                           : (recordBtn.pressed ? "#2a3a55" : "#162540")
                    radius: 6
                    border.color: root.isRecording ? "#ff4444" : "#3a6a9a"
                    border.width: 1
                }
                contentItem: Text {
                    text: recordBtn.text
                    color: root.isRecording ? "#ff8080" : "#80c0ff"
                    font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    if (typeof cameraManager === "undefined") return
                    if (root.isRecording) {
                        cameraManager.stopVideoCapture()
                        root.isRecording = false
                    } else {
                        cameraManager.startVideoCapture()
                        root.isRecording = true
                    }
                }
            }
        }

        // ── Divider ──────────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e3a55" }

        // ── Zoom Control ─────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Text { text: "ZOOM"; color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                Text { text: zoomSlider.value.toFixed(1) + "×"; color: "#80c0ff"; font.pixelSize: 11 }
            }

            Slider {
                id: zoomSlider
                Layout.fillWidth: true
                from: 1.0; to: 10.0; stepSize: 0.5; value: 1.0

                background: Rectangle {
                    x: zoomSlider.leftPadding; y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - 2
                    width: zoomSlider.availableWidth; height: 4; radius: 2
                    color: "#0d1e2e"
                    Rectangle {
                        width: zoomSlider.visualPosition * parent.width
                        height: parent.height; color: "#2a7abf"; radius: 2
                    }
                }
                handle: Rectangle {
                    x: zoomSlider.leftPadding + zoomSlider.visualPosition * zoomSlider.availableWidth - width / 2
                    y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                    width: 16; height: 16; radius: 8
                    color: zoomSlider.pressed ? "#3a9adf" : "#1e7abf"
                    border.color: "#5ab5ef"; border.width: 1
                }

                onValueChanged: {
                    if (typeof cameraManager !== "undefined")
                        cameraManager.setZoom(value)
                }
            }
        }

        // ── Focus Control ─────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Text { text: "FOCUS"; color: "#5a8aaa"; font.pixelSize: 10; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                Text { text: focusSlider.value.toFixed(1); color: "#80c0ff"; font.pixelSize: 11 }
            }

            Slider {
                id: focusSlider
                Layout.fillWidth: true
                from: 0.0; to: 10.0; stepSize: 0.5; value: 0.0

                background: Rectangle {
                    x: focusSlider.leftPadding; y: focusSlider.topPadding + focusSlider.availableHeight / 2 - 2
                    width: focusSlider.availableWidth; height: 4; radius: 2
                    color: "#0d1e2e"
                    Rectangle {
                        width: focusSlider.visualPosition * parent.width
                        height: parent.height; color: "#2a7abf"; radius: 2
                    }
                }
                handle: Rectangle {
                    x: focusSlider.leftPadding + focusSlider.visualPosition * focusSlider.availableWidth - width / 2
                    y: focusSlider.topPadding + focusSlider.availableHeight / 2 - height / 2
                    width: 16; height: 16; radius: 8
                    color: focusSlider.pressed ? "#3a9adf" : "#1e7abf"
                    border.color: "#5ab5ef"; border.width: 1
                }

                onValueChanged: {
                    if (typeof cameraManager !== "undefined")
                        cameraManager.setFocus(value)
                }
            }
        }

        // ── Spacer ────────────────────────────────────────────────────────────
        Item { Layout.fillHeight: true }

        // ── Feedback message ──────────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            text:  root.feedbackMsg
            color: "#406080"; font.pixelSize: 10
            elide: Text.ElideRight; wrapMode: Text.NoWrap
        }
    }

    // ── Python signal connections ─────────────────────────────────────────────
    Connections {
        target: typeof cameraManager !== "undefined" ? cameraManager : null

        function onCommandFeedback(msg) {
            root.feedbackMsg = msg
        }
        function onVideoStartConfirmed(cameraId) {
            root.isRecording = true
        }
        function onVideoStopConfirmed(cameraId) {
            root.isRecording = false
        }
        function onCameraRegistryChanged() {
            root.cameraList = cameraManager.cameraList
        }
    }

    Connections {
        target: typeof videoStreamManager !== "undefined" ? videoStreamManager : null

        function onConnectionStatusChanged(cameraId, status) {
            if (cameraId === cameraSelector.currentText)
                root.feedbackMsg = status
        }
    }
}

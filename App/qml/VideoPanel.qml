import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

/**
 * VideoPanel.qml
 * ==============
 * Displays the live RTSP video frame for the currently active camera.
 *
 * Context properties required:
 *   • videoStreamManager  — VideoStreamManager instance
 *   • videoFrameProvider  — Python-side image provider (optional direct binding)
 *
 * The Python VideoStreamManager emits frameReady(camera_id, QImage).
 * We expose a frameImage property that QML updates via signal connection.
 */

Rectangle {
    id: root

    // ── Dimensions & style ──────────────────────────────────────────────────
    width:  640
    height: 480
    color:  "#0a0a0a"
    radius: 8
    clip:   true

    // ── Public interface ─────────────────────────────────────────────────────
    property string activeCameraId: typeof videoStreamManager !== "undefined"
                                    ? videoStreamManager.activeCameraId : ""
    property string connectionStatus: ""
    property bool   isConnected:   connectionStatus === "Connected"

    // The current frame — updated from Python via setFrame() slot
    property var    currentFrame:  null

    // ── Frame display ────────────────────────────────────────────────────────
    Image {
        id: videoImage
        anchors.fill: parent
        fillMode:     Image.PreserveAspectFit
        smooth:       true
        visible:      root.currentFrame !== null && root.currentFrame !== undefined

        // QImage delivered from Python is bound here by the backend
        source:       root.currentFrame ? root.currentFrame : ""
    }

    // ── No-signal overlay ───────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !videoImage.visible

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  "NO SIGNAL"
            color: "#406080"
            font {
                family:      "Courier New"
                pixelSize:   22
                letterSpacing: 6
                bold:        true
            }
        }

        Rectangle {
            width:  220
            height: 1
            color:  "#254060"
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  root.connectionStatus !== ""
                   ? root.connectionStatus
                   : "Awaiting RTSP stream connection"
            color: "#405060"
            font.pixelSize: 11
        }
    }

    // ── HUD top bar ──────────────────────────────────────────────────────────
    Rectangle {
        id: hudTop
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 28
        color:  Qt.rgba(0, 0, 0, 0.55)
        visible: root.isConnected

        Row {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 8

            // Resolution badge
            Rectangle {
                width: resLabel.width + 12; height: 18; radius: 3
                color: "#1a3a55"
                border.color: "#2a6a9a"; border.width: 1
                Text {
                    id: resLabel
                    anchors.centerIn: parent
                    text: "1920×1080"
                    color: "#80c8ff"; font.pixelSize: 10
                }
            }

            // FPS badge
            Rectangle {
                width: fpsLabel.width + 12; height: 18; radius: 3
                color: "#1a3a55"
                border.color: "#2a6a9a"; border.width: 1
                Text {
                    id: fpsLabel
                    anchors.centerIn: parent
                    text: "30 FPS"
                    color: "#80c8ff"; font.pixelSize: 10
                }
            }

            // Channel badge
            Rectangle {
                width: chLabel.width + 12; height: 18; radius: 3
                color: "#1a3a55"
                border.color: "#2a6a9a"; border.width: 1
                Text {
                    id: chLabel
                    anchors.centerIn: parent
                    text: root.activeCameraId !== "" ? root.activeCameraId.toUpperCase() : "CAM1"
                    color: "#80c8ff"; font.pixelSize: 10
                }
            }
        }

        // Live dot
        Row {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 5
            Rectangle {
                width: 8; height: 8; radius: 4
                color: "#ff4444"
                SequentialAnimation on opacity {
                    running: root.isConnected
                    loops:   Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 600 }
                    NumberAnimation { to: 1.0; duration: 600 }
                }
            }
            Text { text: "LIVE"; color: "#ff6666"; font.pixelSize: 11; font.bold: true }
        }
    }

    // ── Status bar bottom ────────────────────────────────────────────────────
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 24
        color:  Qt.rgba(0, 0, 0, 0.55)
        visible: root.connectionStatus !== ""

        Text {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            text:  root.connectionStatus
            color: root.isConnected ? "#44ff88" : "#ff8844"
            font.pixelSize: 10
        }
    }

    // ── Connections to Python backend ─────────────────────────────────────────
    Connections {
        target: typeof videoStreamManager !== "undefined" ? videoStreamManager : null

        function onConnectionStatusChanged(cameraId, status) {
            if (cameraId === root.activeCameraId || root.activeCameraId === "") {
                root.connectionStatus = status;
            }
        }

        function onActiveCameraChanged(cameraId) {
            root.activeCameraId = cameraId;
        }
    }
}

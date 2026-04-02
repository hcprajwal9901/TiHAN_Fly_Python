    property bool showVideoOverlay: true

    // =========================================================================
    // VIDEO OVERLAY — Camera PiP Panel (from File 1)
    // =========================================================================
    Rectangle {
        id: videoOverlay
        visible: showVideoOverlay
        width:  Math.min(parent.width * 0.36, parent.width - 24)
        height: parent.height * 0.38
        anchors.right:   parent.right
        anchors.bottom:  parent.bottom
        anchors.margins: 12
        radius: 10
        z: 5000
        clip: true
        color: "#0E0E0E"
        border.color: "#2A82DA"
        border.width: 1.5
        layer.enabled: true

        property string activeTab: "video"

        // ─── HEADER ──────────────────────────────────────────────────────────
        Rectangle {
            id: overlayHeader
            height: 36; width: parent.width
            color: "#161616"; radius: 10
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: parent.width; height: parent.radius; color: parent.color }
            Row {
                anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 12; spacing: 8
                Text { text: "CAMERA SYSTEM"; color: "#D0D0D0"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.5; leftPadding: 4 }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                Rectangle {
                    width: 7; height: 7; radius: 4; color: "#00FF41"; anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.2; duration: 600 } NumberAnimation { to: 1.0; duration: 600 } }
                }
                Text { text: "LIVE"; color: "#00FF41"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.2 }
            }
            MouseArea { anchors.fill: parent; drag.target: videoOverlay; cursorShape: Qt.SizeAllCursor }
        }

        // ─── TAB BAR ─────────────────────────────────────────────────────────
        Rectangle {
            id: tabBar
            anchors.top: overlayHeader.bottom
            height: 38; width: parent.width
            color: "#111111"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2A82DA"; opacity: 0.4 }
            Row {
                anchors.centerIn: parent; spacing: 4
                Repeater {
                    model: [
                        { name: "Video",    tabId: "video"    },
                        { name: "Controls", tabId: "controls" },
                        { name: "Gimbal",   tabId: "gimbal"   },
                        { name: "Cameras",  tabId: "multi"    },
                        { name: "Stream",   tabId: "stream"   }
                    ]
                    Rectangle {
                        id: tabBtn
                        property bool isActive: videoOverlay.activeTab === modelData.tabId
                        width: tabLabel.implicitWidth + 18; height: 28; radius: 5
                        color: isActive ? "#2A82DA" : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: tabLabel; anchors.centerIn: parent; text: modelData.name
                            color: tabBtn.isActive ? "#FFFFFF" : "#888888"
                            font.pixelSize: 11; font.bold: tabBtn.isActive; font.letterSpacing: 0.5
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: videoOverlay.activeTab = modelData.tabId }
                    }
                }
            }
        }

        // ─── VIDEO SCREEN ─────────────────────────────────────────────────────
        Rectangle {
            id: videoScreen
            anchors.top: tabBar.bottom
            width: parent.width
            height: parent.height - 74   // header(36) + tabs(38)
            color: "#020608"; clip: true

            // RTSP stream frame
            Image {
                id: streamImage; anchors.fill: parent; z: 0
                fillMode: Image.PreserveAspectFit; cache: false; asynchronous: false
                visible: typeof cameraModel !== "undefined" && cameraModel.isStreaming
                source: ""; antialiasing: true
            }
            Timer {
                id: streamRefreshTimer; interval: 33; repeat: true
                running: typeof cameraModel !== "undefined" && cameraModel.isStreaming
                onTriggered: { if (streamImage.visible) { streamImage.source = ""; streamImage.source = "image://rtspframes/frame" } }
            }

            // Vignette
            Canvas {
                anchors.fill: parent; z: 1; opacity: 1.0
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    var grad = ctx.createRadialGradient(width/2, height/2, height*0.22, width/2, height/2, height*0.78)
                    grad.addColorStop(0, "rgba(0,0,0,0)"); grad.addColorStop(1, "rgba(0,0,0,0.72)")
                    ctx.fillStyle = grad; ctx.fillRect(0, 0, width, height)
                }
                Component.onCompleted: requestPaint()
            }

            // Scanlines
            Canvas {
                anchors.fill: parent; z: 2; opacity: 0.045
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#FFFFFF"; ctx.lineWidth = 1
                    for (var y = 0; y < height; y += 3) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke() }
                }
                Component.onCompleted: requestPaint()
            }

            // Animated sweep scan-line
            Rectangle {
                id: sweepLine; width: parent.width; height: 2; z: 3; opacity: 0.0; color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "transparent" }
                        GradientStop { position: 0.45; color: "transparent" }
                        GradientStop { position: 0.50; color: "#4042A0FF"  }
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1.0;  color: "transparent" }
                    }
                }
                SequentialAnimation {
                    running: true; loops: Animation.Infinite
                    NumberAnimation { target: sweepLine; property: "y"; from: 0; to: videoScreen.height; duration: 3200; easing.type: Easing.Linear }
                    PauseAnimation { duration: 800 }
                }
                onYChanged: opacity = (y > 0 && y < videoScreen.height) ? 0.9 : 0.0
            }

            // Corner brackets
            Canvas {
                anchors.fill: parent; z: 4; opacity: 0.85
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#2A82DA"; ctx.lineWidth = 2; ctx.shadowColor = "#2A82DA"; ctx.shadowBlur = 6
                    var L = 22, M = 12
                    ctx.beginPath(); ctx.moveTo(M, M+L); ctx.lineTo(M, M);          ctx.lineTo(M+L, M);          ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(width-M-L, M); ctx.lineTo(width-M, M); ctx.lineTo(width-M, M+L); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(M, height-M-L); ctx.lineTo(M, height-M); ctx.lineTo(M+L, height-M); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(width-M-L, height-M); ctx.lineTo(width-M, height-M); ctx.lineTo(width-M, height-M-L); ctx.stroke()
                    ctx.shadowBlur = 0
                }
                Component.onCompleted: requestPaint()
            }

            // Crosshair
            Canvas {
                anchors.fill: parent; z: 5; opacity: 0.55
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    var cx = width/2, cy = height/2
                    ctx.strokeStyle = "#2A82DA"; ctx.shadowColor = "#2A82DA"; ctx.shadowBlur = 5; ctx.lineWidth = 1.2
                    ctx.beginPath(); ctx.moveTo(cx-70, cy); ctx.lineTo(cx-16, cy); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(cx+16, cy); ctx.lineTo(cx+70, cy); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(cx, cy-55); ctx.lineTo(cx, cy-16); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(cx, cy+16); ctx.lineTo(cx, cy+55); ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy, 13, 0, Math.PI*2); ctx.stroke()
                    ctx.shadowBlur = 0; ctx.fillStyle = "#4A9AEA"; ctx.beginPath(); ctx.arc(cx, cy, 2.5, 0, Math.PI*2); ctx.fill()
                    ctx.shadowBlur = 3
                    var r = 13, t = 5
                    ctx.beginPath(); ctx.moveTo(cx, cy-r); ctx.lineTo(cx, cy-r-t); ctx.moveTo(cx, cy+r); ctx.lineTo(cx, cy+r+t); ctx.moveTo(cx-r, cy); ctx.lineTo(cx-r-t, cy); ctx.moveTo(cx+r, cy); ctx.lineTo(cx+r+t, cy); ctx.stroke()
                    ctx.shadowBlur = 0
                }
                Component.onCompleted: requestPaint()
            }

            // Top HUD Bar
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 10
                height: 22; color: "transparent"; z: 10
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Repeater {
                        model: [{ t: "1920×1080" }, { t: "30 FPS" }, { t: "CH 1 · RGB" }]
                        Rectangle {
                            width: lbl.implicitWidth + 10; height: 16; radius: 3; color: "#0D1A26"; border.color: "#1A4A70"; border.width: 1
                            Text { id: lbl; anchors.centerIn: parent; text: modelData.t; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; font.bold: true }
                        }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4; color: "#FF3B30"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.25; duration: 500 } NumberAnimation { to: 1.0; duration: 500 } }
                    }
                    Text { text: "00:00:00"; color: "#FF5F57"; font.pixelSize: 10; font.family: "Monospace"; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            // Bottom HUD Bar
            Rectangle {
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 10
                height: 24; color: "transparent"; z: 10
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Repeater {
                        model: [{ label: "ALT", value: "---  m" }, { label: "SPD", value: "---  m/s" }, { label: "HDG", value: "---  °" }]
                        Rectangle {
                            width: rowL.implicitWidth + 14; height: 18; radius: 3; color: "#07111B"; border.color: "#153048"; border.width: 1
                            Row { id: rowL; anchors.centerIn: parent; spacing: 4
                                Text { text: modelData.label; color: "#3A6A9A"; font.pixelSize: 8; font.family: "Monospace"; font.bold: true }
                                Text { text: modelData.value; color: "#5AADFF"; font.pixelSize: 8; font.family: "Monospace" }
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: zt.implicitWidth + 14; height: 18; radius: 3; color: "#07111B"; border.color: "#153048"; border.width: 1
                    Text { id: zt; anchors.centerIn: parent; text: "ZOOM  1.0×"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace" }
                }
            }

            // NO SIGNAL idle state
            Column {
                visible: !(typeof cameraModel !== "undefined" && cameraModel.isStreaming)
                anchors.centerIn: parent; spacing: 10; z: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; text: "📡"; font.pixelSize: 32; opacity: 0.18
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.30; duration: 900; easing.type: Easing.InOutSine } NumberAnimation { to: 0.10; duration: 900; easing.type: Easing.InOutSine } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; text: "NO  SIGNAL"; color: "#1C3A58"; font.pixelSize: 16; font.bold: true; font.letterSpacing: 6
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.55; duration: 1100 } NumberAnimation { to: 1.0; duration: 1100 } }
                }
                Canvas {
                    width: 160; height: 6; anchors.horizontalCenter: parent.horizontalCenter
                    onPaint: { var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height); ctx.strokeStyle = "#1A3A5A"; ctx.lineWidth = 1; ctx.setLineDash([6, 5]); ctx.beginPath(); ctx.moveTo(0, 3); ctx.lineTo(width, 3); ctx.stroke() }
                    Component.onCompleted: requestPaint()
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Awaiting RTSP stream connection"; color: "#1A3A5A"; font.pixelSize: 9; font.letterSpacing: 0.8; font.family: "Monospace" }
            }
        }

        // ─── DYNAMIC CONTROL PANEL (expands below video screen on non-video tabs)
        Loader {
            id: controlPanelLoader
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: videoOverlay.activeTab !== "video" ? 70 : 0
            visible: height > 0; clip: true
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            sourceComponent: {
                if (videoOverlay.activeTab === "controls") return cameraControlsComp
                if (videoOverlay.activeTab === "gimbal")   return gimbalControlsComp
                if (videoOverlay.activeTab === "multi")    return multiCameraPanelComp
                if (videoOverlay.activeTab === "stream")   return streamPanelComp
                return null
            }
        }

        // ─── SUB-COMPONENTS ───────────────────────────────────────────────────
        Component {
            id: cameraControlsComp
            Rectangle {
                color: "#131313"; border.color: "#222222"; border.width: 1
                Row {
                    anchors.centerIn: parent; spacing: 10
                    Rectangle {
                        width: snapTxt.implicitWidth + 18; height: 28; radius: 6
                        color: snapMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: snapTxt; anchors.centerIn: parent; text: "📸 Snap"; color: "#CCCCCC"; font.pixelSize: 10 }
                        MouseArea { id: snapMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof cameraModel !== "undefined") cameraModel.takeSnapshot() }
                    }
                    Rectangle {
                        id: recBtn
                        property bool recording: (typeof cameraModel !== "undefined") && cameraModel.isRecording
                        width: recTxt.implicitWidth + 18; height: 28; radius: 6
                        color: recording ? "#3A0A0A" : (recMa.containsMouse ? "#252525" : "#1A1A1A")
                        border.color: recording ? "#FF3B30" : "#3A3A3A"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: recTxt; anchors.centerIn: parent; text: recBtn.recording ? "⏹ Stop" : "⏺ Rec"; color: recBtn.recording ? "#FF5F57" : "#CCCCCC"; font.pixelSize: 10 }
                        MouseArea { id: recMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (typeof cameraModel === "undefined") return; if (cameraModel.isRecording) cameraModel.stopRecording(); else cameraModel.startRecording() } }
                    }
                    Rectangle { width: 28; height: 28; radius: 6; color: ziMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1; Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: "＋"; color: "#CCCCCC"; font.pixelSize: 14 }
                        MouseArea { id: ziMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof cameraModel !== "undefined") cameraModel.zoomIn() }
                    }
                    Rectangle { width: 28; height: 28; radius: 6; color: zoMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1; Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: "－"; color: "#CCCCCC"; font.pixelSize: 14 }
                        MouseArea { id: zoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof cameraModel !== "undefined") cameraModel.zoomOut() }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: (typeof cameraModel !== "undefined") ? cameraModel.zoomLabel : "1×"; color: "#5AADFF"; font.pixelSize: 10; font.family: "Monospace" }
                    Rectangle { width: cntrTxt.implicitWidth + 18; height: 28; radius: 6; color: cntrMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1; Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: cntrTxt; anchors.centerIn: parent; text: "⊙ Center"; color: "#CCCCCC"; font.pixelSize: 10 }
                        MouseArea { id: cntrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof droneCommander !== "undefined") droneCommander.centerGimbal() }
                    }
                }
            }
        }

        Component {
            id: gimbalControlsComp
            Rectangle {
                color: "#131313"; border.color: "#222222"; border.width: 1
                property real gimbalPitch: 0.0
                property real gimbalYaw:   0.0
                property real gimbalRoll:  0.0
                function sendGimbal() { if (typeof droneCommander !== "undefined") droneCommander.setGimbalAngle(gimbalPitch, gimbalYaw, gimbalRoll) }
                Row {
                    anchors.centerIn: parent; spacing: 20
                    Column { spacing: 4
                        Text { text: "PITCH"; color: "#666"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Slider { id: pitchSlider; width: 100; from: -90; to: 30; value: 0; onValueChanged: { parent.parent.parent.gimbalPitch = value; parent.parent.parent.sendGimbal() } }
                        Text { text: Math.round(pitchSlider.value) + "°"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    Column { spacing: 4
                        Text { text: "YAW"; color: "#666"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Slider { id: yawSlider; width: 100; from: -180; to: 180; value: 0; onValueChanged: { parent.parent.parent.gimbalYaw = value; parent.parent.parent.sendGimbal() } }
                        Text { text: Math.round(yawSlider.value) + "°"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    Column { spacing: 4
                        Text { text: "ROLL"; color: "#666"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Slider { id: rollSlider; width: 70; from: -30; to: 30; value: 0; onValueChanged: { parent.parent.parent.gimbalRoll = value; parent.parent.parent.sendGimbal() } }
                        Text { text: Math.round(rollSlider.value) + "°"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
        }

        Component {
            id: multiCameraPanelComp
            Rectangle {
                color: "#0D1117"; border.color: "#1E2A38"; border.width: 1
                property string selectedCam: (typeof cameraModel !== "undefined") ? cameraModel.activeCameraId : "cam1"
                Row {
                    anchors.centerIn: parent; spacing: 10
                    Repeater {
                        model: [{ label: "📷  Camera 1", camId: "cam1" }, { label: "📷  Camera 2", camId: "cam2" }, { label: "🌡  Thermal IR", camId: "thermal" }]
                        Rectangle {
                            id: camBtn
                            property bool isActive: parent.parent.parent.selectedCam === modelData.camId
                            width: camBtnLabel.implicitWidth + 20; height: 28; radius: 14
                            color: isActive ? "#1A4A80" : "#111A24"; border.color: isActive ? "#2A82DA" : "#243040"; border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { id: camBtnLabel; anchors.centerIn: parent; text: modelData.label; color: camBtn.isActive ? "#FFFFFF" : "#6A8FAA"; font.pixelSize: 10; font.bold: camBtn.isActive; Behavior on color { ColorAnimation { duration: 120 } } }
                            ToolTip.visible: hov.containsMouse; ToolTip.delay: 400
                            ToolTip.text: { if (modelData.camId === "cam1") return "Camera 1 (RGB)"; if (modelData.camId === "cam2") return "Camera 2 (RGB)"; return "Thermal IR" }
                            MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (typeof cameraModel !== "undefined") cameraModel.switchCamera(modelData.camId); camBtn.parent.parent.parent.selectedCam = modelData.camId } }
                        }
                    }
                }
            }
        }

        Component {
            id: streamPanelComp
            Rectangle {
                id: streamRoot; color: "#0D1117"; border.color: "#1E2A38"; border.width: 1
                property bool connected: (typeof cameraModel !== "undefined") && cameraModel.isStreaming
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Rectangle {
                        width: 220; height: 28; radius: 6; color: "#080F18"
                        border.color: streamRoot.connected ? "#00C853" : "#1A3A5A"; border.width: 1
                        TextInput {
                            id: streamUrlInput; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 8
                            text: ""; color: "#5AADFF"; font.pixelSize: 10; font.family: "Monospace"; clip: true; readOnly: streamRoot.connected
                            Text { visible: parent.text === ""; text: "rtsp://192.168.1.10:8554/stream"; color: "#2A4A6A"; font.pixelSize: 10; font.family: "Monospace"; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Rectangle {
                        width: streamBtnLabel.implicitWidth + 22; height: 28; radius: 6
                        color: streamBtnMa.containsMouse ? (streamRoot.connected ? "#3A0A0A" : "#1A3A22") : (streamRoot.connected ? "#2A0808" : "#0F2218")
                        border.color: streamRoot.connected ? "#FF3B30" : "#00C853"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { id: streamBtnLabel; anchors.centerIn: parent; text: streamRoot.connected ? "⏹  Disconnect" : "▶  Connect"; color: streamRoot.connected ? "#FF5F57" : "#00E676"; font.pixelSize: 10; font.bold: true; font.family: "Monospace" }
                        MouseArea { id: streamBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (typeof cameraModel === "undefined") return; if (cameraModel.isStreaming) cameraModel.disconnectStream(); else cameraModel.connectStream(streamUrlInput.text) } }
                    }
                }
            }
        }

    } // end videoOverlay Rectangle

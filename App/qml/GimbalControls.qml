// ═══════════════════════════════════════════════════════════════════
//  PROFESSIONAL GIMBAL CONTROL PANEL  — drop-in replacement for
//  the gimbalControls Component in MapView.qml
//
//  Usage: replace the existing `id: gimbalControls` Component block
//         with this file, or paste the Component body inline.
// ═══════════════════════════════════════════════════════════════════

Component {
    id: gimbalControls

    Rectangle {
        id: gimbalRoot
        color: "#0A0E14"
        border.color: "#1C2A3A"
        border.width: 1

        // ── State ──────────────────────────────────────────────────
        property real gimbalPitch: 0.0
        property real gimbalYaw:   0.0
        property real gimbalRoll:  0.0
        property bool lockRoll:    true

        function sendGimbal() {
            if (typeof droneCommander !== "undefined")
                droneCommander.setGimbalAngle(gimbalPitch, gimbalYaw, gimbalRoll)
        }

        // Clamp + send helpers
        function setPitch(v) { gimbalPitch = Math.max(-90, Math.min(30,  v)); sendGimbal() }
        function setYaw(v)   { gimbalYaw   = Math.max(-180,Math.min(180, v)); sendGimbal() }
        function setRoll(v)  { if (!lockRoll) { gimbalRoll = Math.max(-30, Math.min(30, v)); sendGimbal() } }

        function resetAll() {
            gimbalPitch = 0; gimbalYaw = 0; gimbalRoll = 0; sendGimbal()
        }
        function nadir()  { gimbalPitch = -90; sendGimbal() }
        function horizon(){ gimbalPitch =   0; sendGimbal() }

        // ── Layout ─────────────────────────────────────────────────
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            // ═══════════════════════════════
            //  JOYSTICK (Pitch + Yaw pad)
            // ═══════════════════════════════
            Item {
                id: joystickArea
                width: 110; height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                // Track label
                Text {
                    text: "GIMBAL PAD"
                    color: "#304860"
                    font.pixelSize: 8
                    font.letterSpacing: 2
                    font.family: "Monospace"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 2
                }

                // Pad background
                Rectangle {
                    id: joyPad
                    anchors.centerIn: parent
                    width: 90; height: 90
                    radius: 8
                    color: "#060B10"
                    border.color: "#1A2A3A"
                    border.width: 1

                    // Crosshair lines
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0,0,width,height)
                            ctx.strokeStyle = "#0D1E2E"
                            ctx.lineWidth = 1
                            // H
                            ctx.beginPath(); ctx.moveTo(0, height/2); ctx.lineTo(width, height/2); ctx.stroke()
                            // V
                            ctx.beginPath(); ctx.moveTo(width/2, 0); ctx.lineTo(width/2, height); ctx.stroke()
                            // Circles
                            ctx.strokeStyle = "#0D2030"
                            for (var r = 16; r <= 44; r += 14) {
                                ctx.beginPath(); ctx.arc(width/2, height/2, r, 0, Math.PI*2); ctx.stroke()
                            }
                        }
                        Component.onCompleted: requestPaint()
                    }

                    // Thumb knob — position driven by pitch/yaw
                    Rectangle {
                        id: thumbKnob
                        width: 22; height: 22; radius: 11
                        // Map yaw  [-180,180] → [5, pad.width-27]
                        // Map pitch[-90, 30]  → [pad.height-27, 5]  (inverted Y)
                        property real normX: (gimbalRoot.gimbalYaw + 180) / 360
                        property real normY: 1.0 - (gimbalRoot.gimbalPitch + 90) / 120
                        x: 5 + normX * (joyPad.width - 32)
                        y: 5 + normY * (joyPad.height - 32)
                        color: "transparent"
                        border.color: "#2A82DA"
                        border.width: 2
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            color: "#2A82DA"
                        }
                        // glow
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22; height: 22; radius: 11
                            color: "transparent"
                            border.color: "#2A82DA40"
                            border.width: 6
                        }
                    }

                    MouseArea {
                        id: joyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onPressed:       updateFromMouse(mouse.x, mouse.y)
                        onPositionChanged: if (pressed) updateFromMouse(mouse.x, mouse.y)
                        onReleased: { /* hold position — real gimbals don't spring */ }

                        function updateFromMouse(mx, my) {
                            var nx = Math.max(0, Math.min(1, (mx - 11) / (joyPad.width  - 22)))
                            var ny = Math.max(0, Math.min(1, (my - 11) / (joyPad.height - 22)))
                            gimbalRoot.gimbalYaw   = -180 + nx * 360
                            gimbalRoot.gimbalPitch = 30   - ny * 120   // inverted
                            gimbalRoot.sendGimbal()
                        }
                    }
                }

                // Axis labels below pad
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    spacing: 18
                    Text { text: "YAW"; color: "#304860"; font.pixelSize: 7; font.letterSpacing: 1.5; font.family: "Monospace" }
                    Text { text: "PITCH"; color: "#304860"; font.pixelSize: 7; font.letterSpacing: 1.5; font.family: "Monospace" }
                }
            }

            // ═══════════════════════════════
            //  ROLL STRIP + LOCK
            // ═══════════════════════════════
            Item {
                width: 80; height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "ROLL"
                    color: "#304860"
                    font.pixelSize: 8; font.letterSpacing: 2; font.family: "Monospace"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 2
                }

                // Vertical slider track
                Item {
                    id: rollTrack
                    anchors.centerIn: parent
                    width: 36; height: 70

                    Rectangle {
                        anchors.centerIn: parent
                        width: 4; height: parent.height; radius: 2
                        color: "#0D1E2E"
                    }

                    // Filled portion
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        property real frac: (gimbalRoot.gimbalRoll + 30) / 60   // 0..1
                        height: Math.abs(gimbalRoot.gimbalRoll) / 30 * (rollTrack.height / 2)
                        width: 4; radius: 2
                        color: gimbalRoot.lockRoll ? "#253545" : "#2A82DA"
                        y: gimbalRoot.gimbalRoll >= 0
                            ? rollTrack.height/2 - height
                            : rollTrack.height/2
                    }

                    // Thumb
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        property real frac: (gimbalRoot.gimbalRoll + 30) / 60
                        y: frac * (rollTrack.height - 18)
                        width: 18; height: 18; radius: 4
                        color: gimbalRoot.lockRoll ? "#111A24" : "#0F2030"
                        border.color: gimbalRoot.lockRoll ? "#253545" : "#2A82DA"
                        border.width: 2
                        opacity: gimbalRoot.lockRoll ? 0.45 : 1.0
                        Rectangle {
                            anchors.centerIn: parent
                            width: 6; height: 2; radius: 1
                            color: parent.border.color
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !gimbalRoot.lockRoll
                            drag.target: parent
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: rollTrack.height - 18
                            onPositionChanged: {
                                if (drag.active) {
                                    var frac = parent.y / (rollTrack.height - 18)
                                    gimbalRoot.setRoll(-30 + frac * 60)
                                }
                            }
                        }
                    }

                    // Tick marks
                    Repeater {
                        model: 7  // -30 -20 -10 0 +10 +20 +30
                        Rectangle {
                            x: rollTrack.width/2 + 4
                            y: index * (rollTrack.height / 6) - 1
                            width: index === 3 ? 10 : 6; height: 1
                            color: index === 3 ? "#2A82DA" : "#1A3050"
                        }
                    }
                }

                // Value
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: lockBtn.top; anchors.bottomMargin: 4
                    text: (gimbalRoot.gimbalRoll >= 0 ? "+" : "") + Math.round(gimbalRoot.gimbalRoll) + "°"
                    color: gimbalRoot.lockRoll ? "#253545" : "#5AADFF"
                    font.pixelSize: 9; font.family: "Monospace"; font.bold: true
                }

                // Lock toggle
                Rectangle {
                    id: lockBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    width: 54; height: 16; radius: 3
                    color: gimbalRoot.lockRoll ? "#1A0D0D" : "#0D1A0D"
                    border.color: gimbalRoot.lockRoll ? "#5A2020" : "#205A20"; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: gimbalRoot.lockRoll ? "🔒 LOCKED" : "🔓 FREE"
                        color: gimbalRoot.lockRoll ? "#804040" : "#408040"
                        font.pixelSize: 7; font.letterSpacing: 0.8; font.family: "Monospace"
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            gimbalRoot.lockRoll = !gimbalRoot.lockRoll
                            if (gimbalRoot.lockRoll) { gimbalRoot.gimbalRoll = 0; gimbalRoot.sendGimbal() }
                        }
                    }
                }
            }

            // ═══════════════════════════════
            //  READOUTS  +  PRESETS
            // ═══════════════════════════════
            Column {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 90

                // ── Numeric readouts ──
                Repeater {
                    model: [
                        { label: "P", value: gimbalRoot.gimbalPitch, lo: -90, hi: 30,  color: "#DA4A2A" },
                        { label: "Y", value: gimbalRoot.gimbalYaw,   lo:-180, hi: 180, color: "#2A82DA" },
                        { label: "R", value: gimbalRoot.gimbalRoll,  lo: -30, hi: 30,  color: "#2ADA6A" }
                    ]

                    Rectangle {
                        width: 90; height: 22; radius: 4
                        color: "#060C14"
                        border.color: "#111E2E"; border.width: 1

                        Row {
                            anchors.fill: parent; anchors.margins: 5
                            spacing: 0

                            // Axis badge
                            Rectangle {
                                width: 14; height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 2
                                color: modelData.color + "22"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: modelData.color
                                    font.pixelSize: 8; font.bold: true; font.family: "Monospace"
                                }
                            }

                            Item { width: 4; height: 1 }

                            // Value
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.value >= 0 ? "+" : "") + modelData.value.toFixed(1) + "°"
                                color: "#C0D8F0"
                                font.pixelSize: 11; font.family: "Monospace"; font.bold: true
                                width: 52; horizontalAlignment: Text.AlignRight
                            }

                            Item { width: 4; height: 1 }

                            // Mini bar
                            Item {
                                width: 8; height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 0; width: 2; height: parent.height; radius: 1
                                    color: "#0D1E2E"
                                }
                                Rectangle {
                                    property real frac: (modelData.value - modelData.lo) / (modelData.hi - modelData.lo)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    property real barH: Math.abs(modelData.value) / Math.max(Math.abs(modelData.lo), Math.abs(modelData.hi)) * 12
                                    height: Math.max(1, barH)
                                    y: modelData.value >= 0 ? (12 - height) / 2 - height/2 : 12/2
                                    width: 2; radius: 1
                                    color: modelData.color
                                }
                            }
                        }
                    }
                }

                // ── Preset strip ──
                Row {
                    spacing: 4
                    width: 90

                    Repeater {
                        model: [
                            { label: "↓90", tip: "Nadir",   action: "nadir"   },
                            { label: "—",   tip: "Horizon", action: "horizon" },
                            { label: "⊙",   tip: "Reset",   action: "reset"   }
                        ]

                        Rectangle {
                            width: (90 - 8) / 3; height: 20; radius: 3
                            color: pMa.containsMouse ? "#1A3050" : "#0D1A2A"
                            border.color: pMa.containsMouse ? "#2A82DA" : "#1A3040"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 80 } }
                            Behavior on border.color { ColorAnimation { duration: 80 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: pMa.containsMouse ? "#FFFFFF" : "#5A8AAA"
                                font.pixelSize: 10; font.family: "Monospace"
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            ToolTip.visible: pMa.containsMouse
                            ToolTip.text: modelData.tip
                            ToolTip.delay: 400

                            MouseArea {
                                id: pMa; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if      (modelData.action === "nadir")   gimbalRoot.nadir()
                                    else if (modelData.action === "horizon") gimbalRoot.horizon()
                                    else                                      gimbalRoot.resetAll()
                                }
                            }
                        }
                    }
                }
            }

        } // Row
    } // gimbalRoot
} // Component
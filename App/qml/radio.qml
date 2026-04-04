import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtGraphicalEffects 1.15

ApplicationWindow {
    id: window
    visible: true
    width: 1000
    height: 700
    title: "Radio Calibration - TiHAN Drone System"

    onClosing: {
        if (radioCalibrationModel && radioCalibrationModel.calibrationActive)
            radioCalibrationModel.stopCalibration();
    }

    // ── State properties ─────────────────────────────────────────────────────
    property bool isConnected:        droneModel            ? droneModel.isConnected             : false
    property bool calibrationActive:  radioCalibrationModel ? radioCalibrationModel.calibrationActive : false
    property int  calibrationStep:    radioCalibrationModel ? radioCalibrationModel.calibrationStep   : 0
    property string statusMessage:    radioCalibrationModel ? radioCalibrationModel.statusMessage     : "Connect drone to begin"
    property int  calibrationProgress:radioCalibrationModel ? radioCalibrationModel.calibrationProgress : 0

    // ── PERFORMANCE: bind to QVariantList directly (zero Python overhead) ─────
    // ch[i] is updated on every radioChannelsChanged — pure C++ list read.
    // getChannelInfo() (creates Python dicts) is only called on step-changes.
    property var ch: radioCalibrationModel
                     ? radioCalibrationModel.radioChannels
                     : [1500,1500,1000,1500,0,0,0,0,0,0,0,0]

    // Rich info (min/max/trim) — refreshed only on calibration step changes
    property var channelInfo: radioCalibrationModel ? radioCalibrationModel.getChannelInfo() : []

    Connections {
        target: droneModel
        function onIsConnectedChanged() { window.isConnected = droneModel.isConnected }
    }

    Connections {
        target: radioCalibrationModel

        // Hot path: raw list swap — no Python dicts, no crossing marshalling
        function onRadioChannelsChanged() {
            window.ch = radioCalibrationModel.radioChannels
        }

        // Slow path: only on step changes
        function onCalibrationStatusChanged() {
            window.channelInfo      = radioCalibrationModel.getChannelInfo()
            window.calibrationActive = radioCalibrationModel.calibrationActive
            window.calibrationStep   = radioCalibrationModel.calibrationStep
        }
        function onCalibrationProgressChanged() {
            window.calibrationProgress = radioCalibrationModel.calibrationProgress
        }
        function onStatusMessageChanged() {
            window.statusMessage = radioCalibrationModel.statusMessage
        }
    }

    // White background
    Rectangle { anchors.fill: parent; color: "#ffffff" }

    // ── Calibration Summary Dialog ────────────────────────────────────────────
    Dialog {
        id: calibrationSummaryDialog
        title: "Calibration Summary"
        anchors.centerIn: parent
        width: 600; height: 400; modal: true
        background: Rectangle { radius: 15; color: "#ffffff"; border.color: "#4CAF50"; border.width: 2 }

        Column {
            id: summaryColumn
            anchors.fill: parent; anchors.margins: 20; spacing: 15

            Text { text: "Radio Calibration Complete"; color: "#333333"
                   font.pixelSize: 16; font.bold: true
                   anchors.horizontalCenter: summaryColumn.horizontalCenter }

            Rectangle {
                width: parent.width; height: 250
                color: "#f9f9f9"; border.color: "#cccccc"; border.width: 1; radius: 5
                ScrollView {
                    anchors.fill: parent; anchors.margins: 10
                    Column {
                        spacing: 8; width: parent.parent.width - 20
                        Row {
                            spacing: 10; width: parent.width
                            Text { text: "Channel"; color: "#333333"; font.pixelSize: 12; font.bold: true; width: 120 }
                            Text { text: "Min";     color: "#333333"; font.pixelSize: 12; font.bold: true; width: 60 }
                            Text { text: "Max";     color: "#333333"; font.pixelSize: 12; font.bold: true; width: 60 }
                            Text { text: "Trim";    color: "#333333"; font.pixelSize: 12; font.bold: true; width: 60 }
                            Text { text: "Range";   color: "#333333"; font.pixelSize: 12; font.bold: true; width: 60 }
                        }
                        Rectangle { width: parent.width; height: 1; color: "#cccccc" }
                        Repeater {
                            model: window.channelInfo ? Math.min(8, window.channelInfo.length) : 0
                            Row {
                                spacing: 10; width: parent ? parent.width : 0
                                property var channel:    channelInfo[index]
                                property int rangeValue: channel ? (channel.max - channel.min) : 0
                                property color rangeColor: rangeValue < 200 ? "#ff4444"
                                                         : rangeValue < 400 ? "#ffaa00" : "#00cc66"
                                Text { text: channel ? channel.name          : "Ch"+(index+1); color:"#333333"; font.pixelSize:11; width:120 }
                                Text { text: channel ? channel.min.toString(): "0";            color:"#333333"; font.pixelSize:11; width:60  }
                                Text { text: channel ? channel.max.toString(): "0";            color:"#333333"; font.pixelSize:11; width:60  }
                                Text { text: channel ? channel.trim.toString(): "0";           color:"#333333"; font.pixelSize:11; width:60  }
                                Text { text: rangeValue+"us"; color:rangeColor; font.pixelSize:11; font.bold:true; width:60 }
                            }
                        }
                    }
                }
            }

            Text {
                text: "Green: Good (>400us) | Yellow: Acceptable (200-400us) | Red: Poor (<200us)"
                color: "#666666"; font.pixelSize: 10; wrapMode: Text.WordWrap
                width: summaryColumn.width; anchors.horizontalCenter: summaryColumn.horizontalCenter
            }

            Button {
                text: "OK"
                anchors.horizontalCenter: summaryColumn.horizontalCenter
                onClicked: {
                    calibrationSummaryDialog.close()
                    if (radioCalibrationModel) radioCalibrationModel.saveCalibration()
                }
                background: Rectangle { radius: 10; color: "#4CAF50"; border.color: "#66BB6A"; border.width: 1 }
                contentItem: Text { text: parent.text; color: "white"; font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment:   Text.AlignVCenter }
            }
        }
    }

    // ── Main layout ───────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 16

        Row {
            anchors.fill: parent
            spacing: 20

            // ═══════════════════════════════════════════════════════════════════
            // LEFT PANEL — Mission Planner cross layout
            //
            //   [       Roll (Ch1) horizontal bar        ]
            //   [Pitch]                      [Throttle]
            //   [ (v) ]     (empty centre)    [  (v)  ]
            //   [       Yaw  (Ch4) horizontal bar        ]
            // ═══════════════════════════════════════════════════════════════════
            Item {
                id: leftPanel
                width: 330
                height: parent.height

                readonly property int hBarH:    30
                readonly property int hBarLblW: 80
                readonly property int vBarW:    46
                readonly property int vBarH:    190

                // Direct QVariantList read — no Python call
                function pwm(i)  { return (window.ch && window.ch.length > i) ? window.ch[i] : 1500 }
                function frac(i) { return Math.max(0, Math.min((pwm(i) - 1000) / 1000, 1.0)) }

                // ── Horizontal bar component ──────────────────────────────────
                // Cross-sibling ID anchors (hbLbl → hbBg, hbBg → hbLbl) cause
                // QML TypeError during construction because siblings aren't
                // guaranteed to exist when bindings evaluate.  Fixed layout:
                //   label: left-aligned, vertically centred in top 30px zone
                //   bar:   from x=hBarLblW+8 to right edge, top offset 8px
                //   value: below bar, centred
                component HBar: Item {
                    id: hb
                    property int    chIdx: 0
                    property string lbl:   ""
                    width:  leftPanel.width
                    height: leftPanel.hBarH + 32   // label row + bar + value

                    // Fixed label column
                    Text {
                        text: hb.lbl
                        x: 0
                        y: 4
                        width: leftPanel.hBarLblW
                        height: leftPanel.hBarH
                        color: "#333333"; font.pixelSize: 12; font.bold: true
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Bar track — positioned by constants only, no sibling IDs
                    Rectangle {
                        x: leftPanel.hBarLblW + 8
                        y: 6
                        width:  parent.width - leftPanel.hBarLblW - 8
                        height: leftPanel.hBarH
                        color: "#e4e4e4"; border.color: "#bbbbbb"; border.width: 1; radius: 3

                        // centre tick
                        Rectangle {
                            x: parent.width / 2
                            y: 0; width: 1; height: parent.height
                            color: "#999999"; opacity: 0.7
                        }
                        // green fill
                        Rectangle {
                            x: 0; y: 0; height: parent.height
                            width: leftPanel.frac(hb.chIdx) * parent.width
                            color: "#4CAF50"; radius: 2
                            Behavior on width { NumberAnimation { duration: 10 } }
                        }
                        // value text inside bar
                        Text {
                            anchors.centerIn: parent
                            text: Math.round(leftPanel.pwm(hb.chIdx))
                            color: "#222222"; font.pixelSize: 10; font.bold: true
                        }
                    }
                }

                // ── Vertical bar component ────────────────────────────────────
                // Uses only parent-relative coordinates — no cross-sibling IDs.
                // Layout (from top):
                //   0 .. 20px  : label text
                //   20 .. H-16 : bar track
                //   H-16 .. H  : value text
                component VBar: Item {
                    id: vb
                    property int    chIdx:      0
                    property string lbl:        ""
                    property bool   showCentre: true

                    readonly property int lblH: 22   // label zone height
                    readonly property int valH: 16   // value zone height

                    width:  leftPanel.vBarW + 16
                    height: leftPanel.vBarH + lblH + valH

                    // Label — anchored only to parent
                    Text {
                        x: 0; y: 0
                        width: parent.width; height: vb.lblH
                        text: vb.lbl
                        color: "#333333"; font.pixelSize: 12; font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }

                    // Bar track — anchored only to parent
                    Rectangle {
                        x: (parent.width - leftPanel.vBarW) / 2
                        y: vb.lblH
                        width:  leftPanel.vBarW
                        height: leftPanel.vBarH
                        color: "#e4e4e4"; border.color: "#bbbbbb"; border.width: 1; radius: 3

                        // centre tick (pitch only)
                        Rectangle {
                            x: 0; y: parent.height / 2
                            width: parent.width; height: 1
                            color: "#999999"
                            opacity: vb.showCentre ? 0.7 : 0
                        }
                        // green fill (grows upward from bottom)
                        Rectangle {
                            x: 0
                            height: leftPanel.frac(vb.chIdx) * parent.height
                            y: parent.height - height
                            width: parent.width
                            color: "#4CAF50"; radius: 2
                            Behavior on height { NumberAnimation { duration: 10 } }
                        }
                    }

                    // Value text — anchored only to parent bottom
                    Text {
                        x: 0
                        y: parent.height - vb.valH
                        width: parent.width; height: vb.valH
                        text: Math.round(leftPanel.pwm(vb.chIdx))
                        color: "#444444"; font.pixelSize: 10; font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                }

                // ── Cross arrangement ─────────────────────────────────────────
                Column {
                    anchors.fill: parent
                    spacing: 8

                    // Row 1 — Roll horizontal (top-centre)
                    HBar { chIdx: 0; lbl: "Roll\n(Ch1)" }

                    // Row 2 — Pitch (left vertical) | gap | Throttle (right vertical)
                    Row {
                        width: parent.width
                        height: leftPanel.vBarH + 36

                        VBar {
                            chIdx: 1; lbl: "Pitch\n(Ch2)"; showCentre: true
                        }

                        Item {
                            width: parent.width - 2*(leftPanel.vBarW + 16)
                            height: parent.height
                        }

                        VBar {
                            chIdx: 2; lbl: "Throttle\n(Ch3)"; showCentre: false
                        }
                    }

                    // Row 3 — Yaw horizontal (bottom-centre)
                    HBar { chIdx: 3; lbl: "Yaw\n(Ch4)" }
                }
            }

            // ═══════════════════════════════════════════════════════════════════
            // RIGHT PANEL — Radio 5-12 + buttons (unchanged)
            // ═══════════════════════════════════════════════════════════════════
            Item {
                width: parent.width - leftPanel.width - 20
                height: parent.height

                Column {
                    id: rightControlsColumn
                    anchors.fill: parent
                    spacing: 15

                    GridLayout {
                        columns: 2
                        columnSpacing: 15; rowSpacing: 8
                        width: parent.width

                        Repeater {
                            id: radioChannelsRepeater
                            // Fixed count of 8 — channels 5-12 (indices 4-11 in window.ch)
                            // Values come directly from window.ch (the live QVariantList)
                            // so they update at 50 Hz with zero Python overhead.
                            model: 8

                            Row {
                                spacing: 10
                                // chI = 0-indexed position in window.ch
                                readonly property int  chI:    index + 4
                                readonly property int  pwmVal: (window.ch && window.ch.length > chI) ? window.ch[chI] : 0
                                // "active" = valid PWM range received from hardware
                                readonly property bool active: pwmVal > 900 && pwmVal < 2200

                                Text {
                                    text: "Radio " + (index + 5)
                                    color: "#333333"; font.pixelSize: 11; font.bold: true
                                    width: 60; anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    width: 200; height: 20
                                    color: active ? "#c8f0c8" : "#e0e0e0"
                                    border.color: "#cccccc"; border.width: 1
                                    Rectangle {
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: active ? Math.max(0, Math.min((pwmVal - 1000) / 1000, 1.0)) * parent.width : 0
                                        color: "#4CAF50"
                                        Behavior on width { NumberAnimation { duration: 60 } }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: active ? Math.round(pwmVal) : "0"
                                        color: "#222222"; font.pixelSize: 9; font.bold: true
                                    }
                                }
                                Text {
                                    text: "0"; color: "#333333"; font.pixelSize: 11; width: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // Click When Done
                    Button {
                        id: clickWhenDoneBtn
                        text: "Click when Done"
                        width: 200; height: 40
                        anchors.horizontalCenter: rightControlsColumn.horizontalCenter
                        enabled: isConnected && calibrationActive
                        visible: calibrationActive
                        onClicked: {
                            if (radioCalibrationModel) {
                                // finishCalibration() commits captured extremes → step 3
                                // then emits calibrationStatusChanged which triggers the
                                // Connections below to refresh channelInfo and open dialog.
                                radioCalibrationModel.finishCalibration()
                                // Refresh summary data immediately, then open dialog
                                window.channelInfo = radioCalibrationModel.getChannelInfo()
                                calibrationSummaryDialog.open()
                            }
                        }
                        background: Rectangle { color: "#90EE90"; border.color: "#4CAF50"; border.width: 2; radius: 5 }
                        contentItem: Text {
                            text: clickWhenDoneBtn.text; color: "#000000"
                            font.bold: true; font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                        }
                    }

                    // Spectrum Bind
                    Rectangle {
                        width: 300; height: 80
                        anchors.horizontalCenter: rightControlsColumn.horizontalCenter
                        color: "#f0f0f0"; border.color: "#cccccc"; border.width: 1; radius: 5

                        Column {
                            id: spectrumColumn
                            anchors.centerIn: parent; spacing: 10
                            Text {
                                text: "Spectrum Bind"; color: "#333333"
                                font.pixelSize: 12; font.bold: true
                                anchors.horizontalCenter: spectrumColumn.horizontalCenter
                            }
                            Row {
                                spacing: 10
                                anchors.horizontalCenter: spectrumColumn.horizontalCenter
                                Repeater {
                                    model: ["DSM2", "DSMX", "DSME"]
                                    Button {
                                        text: "Bind " + modelData
                                        width: 80; height: 25
                                        enabled: isConnected && !calibrationActive
                                        onClicked: { if (radioCalibrationModel) radioCalibrationModel.bindSpectrum(modelData) }
                                        background: Rectangle {
                                            color: parent.enabled ? "#4CAF50" : "#cccccc"
                                            border.color: "#66BB6A"; border.width: 1; radius: 3
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: parent.enabled ? "white" : "#666666"
                                            font.pixelSize: 9; font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment:   Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Start Calibration
                    Button {
                        text: "Start Calibration"
                        width: 150; height: 35
                        enabled: isConnected && !calibrationActive
                        anchors.horizontalCenter: rightControlsColumn.horizontalCenter
                        onClicked: { if (radioCalibrationModel) radioCalibrationModel.startCalibration() }
                        background: Rectangle {
                            color: parent.enabled ? "#4CAF50" : "#cccccc"
                            border.color: "#66BB6A"; border.width: 2; radius: 5
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? "white" : "#666666"
                            font.bold: true; font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
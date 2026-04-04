import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Dialogs 1.3

ApplicationWindow {
    id: root
    visible: true
    visibility: Window.Maximized

    width: Math.min(Screen.width * 0.95, 1920)
    height: Math.min(Screen.height * 0.95, 1080)

    minimumWidth: 800
    minimumHeight: 600
    title: "Compass Calibration System"
    color: "#f0f2f5"

    property bool isDroneConnected: droneModel ? (droneModel.isConnected || false) : false
    property var compassCalibrationModel: null
    property var droneModel: null
    property var droneCommander: null
    property bool isCalibrationCompleted: false

    // ── Color tokens ──────────────────────────────────────────────────────────
    readonly property color primaryColor:    "#2563eb"
    readonly property color successColor:    "#10b981"
    readonly property color dangerColor:     "#ef4444"
    readonly property color warningColor:    "#f59e0b"
    readonly property color cardColor:       "#ffffff"
    readonly property color textPrimary:     "#1f2937"
    readonly property color textSecondary:   "#6b7280"
    readonly property color borderColor:     "#e5e7eb"
    readonly property color surfaceColor:    "#f8fafc"

    // ── Column widths (fixed — table scrolls horizontally if needed) ──────────
    readonly property int colPriority:  70
    readonly property int colDevId:    100
    readonly property int colBusType:   90
    readonly property int colBus:       60
    readonly property int colAddress:  110
    readonly property int colDevType:  130
    readonly property int colMissing:   80
    readonly property int colExternal:  80
    readonly property int colActions:   90
    readonly property int tableMinWidth: colPriority + colDevId + colBusType + colBus +
                                         colAddress + colDevType + colMissing + colExternal + colActions

    // ── Compass table data ────────────────────────────────────────────────────
    ListModel {
        id: compassTableModel
        ListElement {
            priority: "1"; devId: "97539";  busType: "UAVCAN"; bus: "0";
            address: "125";     devType: "SENSOR_ID#1"; missing: false; external: true
        }
        ListElement {
            priority: "2"; devId: "590114"; busType: "SPI";   bus: "4";
            address: "AK09916"; devType: "";            missing: false; external: false
        }
    }

    function reorderPriorities() {
        for (var i = 0; i < compassTableModel.count; i++)
            compassTableModel.setProperty(i, "priority", String(i + 1))
    }

    // ── Connections ───────────────────────────────────────────────────────────
    Connections {
        target: droneModel; enabled: droneModel !== null
        function onIsConnectedChanged() {
            if (droneModel && !droneModel.isConnected &&
                compassCalibrationModel && compassCalibrationModel.calibrationStarted)
                compassCalibrationModel.stopCalibration()
        }
    }
    Connections {
        target: compassCalibrationModel; enabled: compassCalibrationModel !== null
        function onCalibrationStartedChanged() { isCalibrationCompleted = false }
        function onCalibrationComplete()       { isCalibrationCompleted = true  }
        function onCalibrationFailed()         { isCalibrationCompleted = false }
        function onRebootInitiated()           { rebootBanner.visible = true }
    }

    MessageDialog {
        id: rebootDialog
        title: "Reboot Required"
        text: "Calibration completed successfully!\n\nReboot required to apply settings. Reboot now?"
        standardButtons: StandardButton.Yes | StandardButton.No
        onYes: {
            if (isDroneConnected && compassCalibrationModel) {
                compassCalibrationModel.rebootAutopilot()
                isCalibrationCompleted = false
            }
        }
    }

    // ── Reboot-in-progress banner ──────────────────────────────────────────────
    // Shown instead of closing the window so the user gets feedback.
    Rectangle {
        id: rebootBanner
        visible: false
        z: 100
        anchors.top: root.top
        anchors.left: root.left
        anchors.right: root.right
        height: 52
        color: "#f59e0b"

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            Text { text: "🔄"; font.pixelSize: 20 }
            Text {
                text: "Rebooting autopilot… please wait. The connection indicator will update automatically."
                color: "white"; font.pixelSize: 13; font.weight: Font.Medium
            }
        }

        // Auto-hide after 6 s
        Timer {
            interval: 6000; running: rebootBanner.visible; repeat: false
            onTriggered: rebootBanner.visible = false
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  HEADER
    // ═══════════════════════════════════════════════════════════════════════════
    Rectangle {
        id: headerBar
        anchors.top: parent ? parent.top : undefined
        anchors.left: parent ? parent.left : undefined
        anchors.right: parent ? parent.right : undefined
        height: 70
        color: cardColor
        z: 10

        Rectangle { anchors.bottom: parent ? parent.bottom : undefined; width: parent ? parent.width : 0; height: 1; color: borderColor }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Logo
            Rectangle {
                width: 42; height: 42; radius: 10; color: primaryColor
                layer.enabled: true
                layer.effect: null
                Text { anchors.centerIn: parent; text: "⚙"; color: "white"; font.pixelSize: 22 }
            }

            ColumnLayout {
                spacing: 1
                Text { text: "Compass Calibration System"; color: textPrimary; font.pixelSize: 17; font.weight: Font.DemiBold }
                Text { text: "Advanced Configuration & Diagnostics";  color: textSecondary; font.pixelSize: 11 }
            }

            Item { Layout.fillWidth: true }

            // Connection pill
            Rectangle {
                Layout.preferredWidth: 148; Layout.preferredHeight: 34; radius: 17
                color: isDroneConnected ? "#ecfdf5" : "#fef2f2"
                border.color: isDroneConnected ? "#a7f3d0" : "#fecaca"; border.width: 1

                RowLayout {
                    anchors.centerIn: parent; spacing: 8
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: isDroneConnected ? successColor : dangerColor
                        SequentialAnimation on opacity {
                            running: isDroneConnected; loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.3; duration: 800 }
                            NumberAnimation { from: 0.3; to: 1.0; duration: 800 }
                        }
                    }
                    Text {
                        text: isDroneConnected ? "Connected" : "Disconnected"
                        color: isDroneConnected ? "#065f46" : "#991b1b"
                        font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  MAIN SCROLL AREA
    // ═══════════════════════════════════════════════════════════════════════════
    ScrollView {
        id: mainScroll
        anchors.top: headerBar.bottom
        anchors.left: parent ? parent.left : undefined
        anchors.right: parent ? parent.right : undefined
        anchors.bottom: parent ? parent.bottom : undefined
        anchors.margins: 20
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: mainScroll.width
            spacing: 16

            // ─────────────────────────────────────────────────────────────────
            //  SYSTEM DIAGNOSTICS
            // ─────────────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 86
                color: cardColor; radius: 12; border.color: borderColor; border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10

                    Text { text: "System Diagnostics"; color: textPrimary; font.pixelSize: 13; font.weight: Font.DemiBold }

                    RowLayout {
                        spacing: 32

                        Repeater {
                            model: [
                                { label: "Model Status", value: compassCalibrationModel ? "Active"   : "Inactive", ok: compassCalibrationModel !== null },
                                { label: "Calibration",  value: (compassCalibrationModel && compassCalibrationModel.calibrationStarted) ? "Running" : "Idle",
                                  ok: !!(compassCalibrationModel && compassCalibrationModel.calibrationStarted) },
                                { label: "Mag 1", value: Math.round(compassCalibrationModel ? compassCalibrationModel.mag1Progress : 0) + "%", ok: true },
                                { label: "Mag 2", value: Math.round(compassCalibrationModel ? compassCalibrationModel.mag2Progress : 0) + "%", ok: true },
                                { label: "Mag 3", value: Math.round(compassCalibrationModel ? compassCalibrationModel.mag3Progress : 0) + "%", ok: true }
                            ]
                            ColumnLayout {
                                spacing: 3
                                Text { text: modelData.label; color: textSecondary; font.pixelSize: 10; font.weight: Font.Medium }
                                RowLayout {
                                    spacing: 5
                                    Rectangle { width: 6; height: 6; radius: 3; color: modelData.ok ? successColor : textSecondary }
                                    Text { text: modelData.value; color: textPrimary; font.pixelSize: 13; font.weight: Font.DemiBold }
                                }
                            }
                        }
                    }
                }
            }

            // ─────────────────────────────────────────────────────────────────
            //  COMPASS PRIORITY CONFIGURATION
            // ─────────────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: compassConfigCol.implicitHeight + 40
                color: cardColor; radius: 12; border.color: borderColor; border.width: 1

                ColumnLayout {
                    id: compassConfigCol
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    // Title
                    RowLayout {
                        spacing: 10
                        Rectangle { width: 4; height: 20; color: primaryColor; radius: 2 }
                        Text { text: "Compass Priority Configuration"; color: textPrimary; font.pixelSize: 15; font.weight: Font.DemiBold }
                    }
                    Text {
                        text: "Configure compass priority order (highest priority at top). Each compass is listed with its device ID, bus configuration, and type."
                        color: textSecondary; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }

                    // ── TABLE (horizontal scroll protects data at any window width) ──
                    Rectangle {
                        Layout.fillWidth: true
                        height: tableInner.height + 2        // +2 for border
                        color: "transparent"
                        border.color: borderColor; border.width: 1; radius: 10
                        clip: true

                        ScrollView {
                            id: tableScroll
                            anchors.fill: parent
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                            ScrollBar.horizontal.policy: tableInner.width > tableScroll.width
                                                         ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

                            Column {
                                id: tableInner
                                // Always at least as wide as the scroll view, but grows if columns need it
                                width: Math.max(tableScroll.width, tableMinWidth)

                                // ── HEADER ───────────────────────────────────
                                Rectangle {
                                    width: parent.width; height: 38
                                    color: "#f1f5f9"; radius: 0

                                    Row {
                                        anchors.fill: parent

                                        Repeater {
                                            model: [
                                                { label: "Priority",  w: colPriority  },
                                                { label: "DevID",     w: colDevId     },
                                                { label: "Bus Type",  w: colBusType   },
                                                { label: "Bus",       w: colBus       },
                                                { label: "Address",   w: colAddress   },
                                                { label: "Dev Type",  w: colDevType   },
                                                { label: "Missing",   w: colMissing   },
                                                { label: "External",  w: colExternal  },
                                                { label: "Actions",   w: colActions   }
                                            ]

                                            // Distribute any extra space proportionally to the last column
                                            property real extraW: (tableInner.width - tableMinWidth) / 9

                                            Rectangle {
                                                width: (modelData ? modelData.w : 0) + (parent && parent.extraW !== undefined ? parent.extraW : 0)
                                                height: 38
                                                color: "transparent"
                                                // Right border separator
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor; visible: index < 8
                                                }
                                                Text {
                                                    anchors.left: parent ? parent.left : undefined
                                                    anchors.right: parent ? parent.right : undefined
                                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                                    anchors.leftMargin: 10
                                                    text: modelData ? modelData.label : ""
                                                    font.pixelSize: 11; font.weight: Font.DemiBold
                                                    color: "#374151"
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }

                                    // Bottom border under header
                                    Rectangle {
                                        anchors.bottom: parent ? parent.bottom : undefined
                                        width: parent ? parent.width : 0; height: 1; color: borderColor
                                    }
                                }

                                // ── DATA ROWS ─────────────────────────────────
                                Repeater {
                                    model: compassTableModel

                                    Rectangle {
                                        id: rowRect
                                        width: tableInner.width
                                        height: 52

                                        // Alternating / highlight colours
                                        color: index === 0 ? "#f0f7ff" : (index % 2 === 0 ? surfaceColor : cardColor)

                                        // Hover highlight
                                        MouseArea {
                                            anchors.fill: parent; hoverEnabled: true
                                            onEntered: rowRect.color = "#e8f0fe"
                                            onExited:  rowRect.color = index === 0 ? "#f0f7ff" : (index % 2 === 0 ? surfaceColor : cardColor)
                                        }

                                        // Bottom separator
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width; height: 1
                                            color: borderColor
                                            visible: index < compassTableModel.count - 1
                                        }

                                        property real extraW: (tableInner.width - tableMinWidth) / 9

                                        Row {
                                            anchors.fill: parent

                                            // PRIORITY badge
                                            Item {
                                                width: colPriority + rowRect.extraW; height: parent.height
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 28; height: 28; radius: 14
                                                    color: index === 0 ? primaryColor : "#e5e7eb"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: model.priority
                                                        font.pixelSize: 12; font.weight: Font.Bold
                                                        color: index === 0 ? "white" : "#374151"
                                                    }
                                                }
                                                // Col separator
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // DEV ID
                                            Item {
                                                width: colDevId + rowRect.extraW; height: parent.height
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 10
                                                    text: model.devId
                                                    font.pixelSize: 11; font.family: "Courier New"
                                                    color: textPrimary; elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // BUS TYPE pill
                                            Item {
                                                width: colBusType + rowRect.extraW; height: parent.height
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: busTypeTxt.implicitWidth + 16; height: 22; radius: 5
                                                    color: model.busType === "UAVCAN" ? "#dbeafe" : "#f3e8ff"
                                                    border.color: model.busType === "UAVCAN" ? "#93c5fd" : "#d8b4fe"; border.width: 1
                                                    Text {
                                                        id: busTypeTxt
                                                        anchors.centerIn: parent
                                                        text: model.busType
                                                        font.pixelSize: 10; font.weight: Font.DemiBold
                                                        color: model.busType === "UAVCAN" ? "#1d4ed8" : "#7e22ce"
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // BUS
                                            Item {
                                                width: colBus + rowRect.extraW; height: parent.height
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: model.bus; font.pixelSize: 11; color: textPrimary
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // ADDRESS
                                            Item {
                                                width: colAddress + rowRect.extraW; height: parent.height
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 10
                                                    text: model.address
                                                    font.pixelSize: 11; font.family: "Courier New"
                                                    color: textPrimary; elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // DEV TYPE
                                            Item {
                                                width: colDevType + rowRect.extraW; height: parent.height
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 10
                                                    text: model.devType !== "" ? model.devType : "—"
                                                    font.pixelSize: 10
                                                    color: model.devType !== "" ? textPrimary : textSecondary
                                                    elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // MISSING checkbox
                                            Item {
                                                width: colMissing + rowRect.extraW; height: parent.height
                                                CheckBox {
                                                    anchors.centerIn: parent
                                                    checked: model.missing; enabled: isDroneConnected; scale: 0.80
                                                    onCheckedChanged: compassTableModel.setProperty(index, "missing", checked)
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // EXTERNAL checkbox
                                            Item {
                                                width: colExternal + rowRect.extraW; height: parent.height
                                                CheckBox {
                                                    anchors.centerIn: parent
                                                    checked: model.external; enabled: isDroneConnected; scale: 0.80
                                                    onCheckedChanged: compassTableModel.setProperty(index, "external", checked)
                                                }
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.right: parent.right
                                                    width: 1; color: borderColor
                                                }
                                            }

                                            // ACTIONS — up/down
                                            Item {
                                                width: colActions + rowRect.extraW; height: parent.height

                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 6

                                                    // UP
                                                    Rectangle {
                                                        width: 30; height: 30; radius: 6
                                                        color: upArea.containsMouse && index > 0 ? "#dbeafe" : "#f1f5f9"
                                                        border.color: index > 0 ? "#93c5fd" : borderColor; border.width: 1
                                                        opacity: index > 0 ? 1.0 : 0.4
                                                        Text {
                                                            anchors.centerIn: parent; text: "↑"
                                                            font.pixelSize: 14
                                                            color: index > 0 ? primaryColor : textSecondary
                                                        }
                                                        MouseArea {
                                                            id: upArea; anchors.fill: parent; hoverEnabled: true
                                                            cursorShape: index > 0 && isDroneConnected ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                            enabled: isDroneConnected && index > 0
                                                            onClicked: { compassTableModel.move(index, index - 1, 1); root.reorderPriorities() }
                                                        }
                                                    }

                                                    // DOWN
                                                    Rectangle {
                                                        width: 30; height: 30; radius: 6
                                                        color: downArea.containsMouse && index < compassTableModel.count - 1 ? "#dbeafe" : "#f1f5f9"
                                                        border.color: index < compassTableModel.count - 1 ? "#93c5fd" : borderColor; border.width: 1
                                                        opacity: index < compassTableModel.count - 1 ? 1.0 : 0.4
                                                        Text {
                                                            anchors.centerIn: parent; text: "↓"
                                                            font.pixelSize: 14
                                                            color: index < compassTableModel.count - 1 ? primaryColor : textSecondary
                                                        }
                                                        MouseArea {
                                                            id: downArea; anchors.fill: parent; hoverEnabled: true
                                                            cursorShape: index < compassTableModel.count - 1 && isDroneConnected ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                            enabled: isDroneConnected && index < compassTableModel.count - 1
                                                            onClicked: { compassTableModel.move(index, index + 1, 1); root.reorderPriorities() }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Bottom controls bar ────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true; height: 52
                        color: surfaceColor; radius: 8
                        border.color: borderColor; border.width: 1

                        RowLayout {
                            anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                            spacing: 6

                            Repeater {
                                model: [
                                    { label: "Use Compass 1", checked: true  },
                                    { label: "Use Compass 2", checked: true  },
                                    { label: "Use Compass 3", checked: false }
                                ]
                                RowLayout {
                                    spacing: 4
                                    CheckBox { checked: modelData.checked; enabled: isDroneConnected; scale: 0.82 }
                                    Text { text: modelData.label; color: textPrimary; font.pixelSize: 12 }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Remove Missing button
                            Rectangle {
                                width: rmLabel.implicitWidth + 28; height: 34; radius: 7
                                color: rmArea.containsMouse && isDroneConnected ? "#fef2f2" : cardColor
                                border.color: isDroneConnected ? "#fca5a5" : borderColor; border.width: 1
                                opacity: isDroneConnected ? 1.0 : 0.5
                                Text {
                                    id: rmLabel; anchors.centerIn: parent
                                    text: "Remove Missing"
                                    font.pixelSize: 12; font.weight: Font.Medium
                                    color: isDroneConnected ? dangerColor : textSecondary
                                }
                                MouseArea {
                                    id: rmArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: isDroneConnected ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: isDroneConnected
                                }
                            }
                        }
                    }
                }
            }

            // ─────────────────────────────────────────────────────────────────
            //  CALIBRATION PROCESS
            // ─────────────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: calibCol.implicitHeight + 40
                color: cardColor; radius: 12; border.color: borderColor; border.width: 1

                ColumnLayout {
                    id: calibCol
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 18

                    // Title + status badge
                    RowLayout {
                        spacing: 10
                        Rectangle { width: 4; height: 20; color: primaryColor; radius: 2 }
                        Text { text: "Calibration Process"; color: textPrimary; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 140; height: 30; radius: 15
                            color: isCalibrationCompleted ? "#ecfdf5"
                                 : (compassCalibrationModel && compassCalibrationModel.calibrationStarted) ? "#fef3c7"
                                 : "#f3f4f6"
                            border.color: isCalibrationCompleted ? "#a7f3d0"
                                        : (compassCalibrationModel && compassCalibrationModel.calibrationStarted) ? "#fde68a"
                                        : borderColor
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: isCalibrationCompleted ? "✓  COMPLETED"
                                    : (compassCalibrationModel && compassCalibrationModel.calibrationStarted)
                                        ? "Step " + (compassCalibrationModel.currentOrientation || 1) + " of 6"
                                    : "Ready"
                                color: isCalibrationCompleted ? "#065f46"
                                     : (compassCalibrationModel && compassCalibrationModel.calibrationStarted) ? "#92400e"
                                     : textSecondary
                                font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Action buttons
                    RowLayout {
                        spacing: 10
                        // Start / Reboot
                        Rectangle {
                            width: 175; height: 42; radius: 9
                            color: (isDroneConnected && compassCalibrationModel &&
                                    (!compassCalibrationModel.calibrationStarted || isCalibrationCompleted))
                                   ? (startArea.containsMouse ? Qt.darker(isCalibrationCompleted ? successColor : primaryColor, 1.08)
                                                              : (isCalibrationCompleted ? successColor : primaryColor))
                                   : "#9ca3af"
                            Text {
                                anchors.centerIn: parent
                                text: isCalibrationCompleted ? "✓  Reboot & Apply" : "Start Calibration"
                                color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: startArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: isDroneConnected && compassCalibrationModel &&
                                         (!compassCalibrationModel.calibrationStarted || isCalibrationCompleted)
                                onClicked: {
                                    if (isCalibrationCompleted) rebootDialog.open()
                                    else if (compassCalibrationModel && isDroneConnected) compassCalibrationModel.startCalibration()
                                }
                            }
                        }
                        // Accept
                        Rectangle {
                            width: 175; height: 42; radius: 9
                            color: (isDroneConnected && compassCalibrationModel &&
                                    compassCalibrationModel.calibrationStarted && !isCalibrationCompleted)
                                   ? (acceptArea.containsMouse ? "#059669" : successColor)
                                   : "#9ca3af"
                            Text { anchors.centerIn: parent; text: "Accept Calibration"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea {
                                id: acceptArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: isDroneConnected && compassCalibrationModel &&
                                         compassCalibrationModel.calibrationStarted && !isCalibrationCompleted
                                onClicked: { if (compassCalibrationModel && isDroneConnected) compassCalibrationModel.acceptCalibration() }
                            }
                        }
                        // Cancel
                        Rectangle {
                            width: 110; height: 42; radius: 9
                            color: (isDroneConnected && compassCalibrationModel &&
                                    compassCalibrationModel.calibrationStarted && !isCalibrationCompleted)
                                   ? (cancelArea.containsMouse ? "#dc2626" : dangerColor)
                                   : "#9ca3af"
                            Text { anchors.centerIn: parent; text: "Cancel"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea {
                                id: cancelArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: isDroneConnected && compassCalibrationModel &&
                                         compassCalibrationModel.calibrationStarted && !isCalibrationCompleted
                                onClicked: {
                                    if (compassCalibrationModel && isDroneConnected) {
                                        compassCalibrationModel.stopCalibration()
                                        isCalibrationCompleted = false
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: borderColor }

                    Text { text: "Magnetometer Progress"; color: textPrimary; font.pixelSize: 13; font.weight: Font.DemiBold }

                    // ── Progress bars ─────────────────────────────────────────
                    Repeater {
                        model: [
                            { name: "Magnetometer 1", magId: 1, barColor: "#3b82f6", shimColor: "#93c5fd", bgColor: "#eff6ff", trackColor: "#dbeafe" },
                            { name: "Magnetometer 2", magId: 2, barColor: "#10b981", shimColor: "#6ee7b7", bgColor: "#f0fdf4", trackColor: "#d1fae5" },
                            { name: "Magnetometer 3", magId: 3, barColor: "#f59e0b", shimColor: "#fcd34d", bgColor: "#fffbeb", trackColor: "#fde68a" }
                        ]

                        RowLayout {
                            Layout.fillWidth: true; spacing: 12

                            readonly property real currentProgress: compassCalibrationModel ? 
                                (modelData.magId === 1 ? compassCalibrationModel.mag1Progress :
                                 modelData.magId === 2 ? compassCalibrationModel.mag2Progress :
                                 compassCalibrationModel.mag3Progress) : 0

                            // Label
                            Text {
                                text: modelData.name; color: textPrimary
                                Layout.preferredWidth: 120; font.pixelSize: 12; font.weight: Font.Medium
                            }

                            // Track
                            Rectangle {
                                Layout.fillWidth: true; height: 28
                                color: modelData.trackColor
                                radius: 6; clip: true

                                // Simple solid fill bar
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, currentProgress / 100.0))
                                    height: parent.height
                                    color: modelData.barColor
                                    radius: 6
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }

                                // Percentage label (always on top)
                                Text {
                                    anchors.centerIn: parent
                                    text: { var p = currentProgress; return isNaN(p) ? "—" : Math.round(p) + "%" }
                                    color: currentProgress > 45 ? "white" : Qt.darker(modelData.barColor, 1.4)
                                    font.pixelSize: 11; font.weight: Font.DemiBold
                                }
                            }


                            // Status dot
                            Rectangle {
                                width: 34; height: 34; radius: 17
                                color: currentProgress >= 100 ? modelData.bgColor
                                     : currentProgress > 0    ? "#fef3c7"
                                     : "#f3f4f6"
                                border.color: currentProgress >= 100 ? modelData.barColor
                                            : currentProgress > 0    ? warningColor
                                            : borderColor
                                border.width: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: currentProgress >= 100 ? "✓" : currentProgress > 0 ? "●" : "○"
                                    color: currentProgress >= 100 ? modelData.barColor
                                         : currentProgress > 0    ? warningColor : textSecondary
                                    font.pixelSize: 13

                                    SequentialAnimation on scale {
                                        running: currentProgress >= 100
                                        NumberAnimation { from: 0.5; to: 1.25; duration: 200; easing.type: Easing.OutBack }
                                        NumberAnimation { from: 1.25; to: 1.0;  duration: 150 }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: borderColor }

                    // Config options row
                    RowLayout {
                        spacing: 14
                        Text { text: "Fitness Level:"; color: textPrimary; font.pixelSize: 12; font.weight: Font.Medium }
                        ComboBox {
                            model: ["Strict", "Default", "Relaxed", "Very Relaxed"]; currentIndex: 1
                            enabled: isDroneConnected && (!compassCalibrationModel || !compassCalibrationModel.calibrationStarted)
                            Layout.preferredWidth: 155; Layout.preferredHeight: 34
                            background: Rectangle {
                                color: parent.enabled ? cardColor : surfaceColor
                                border.color: borderColor; border.width: 1; radius: 6
                            }
                        }
                        Item { Layout.fillWidth: true }
                        CheckBox { checked: true; enabled: isDroneConnected; scale: 0.83 }
                        Text { text: "Auto-retry on failure"; color: textPrimary; font.pixelSize: 12 }
                    }

                    // Status message
                    Rectangle {
                        Layout.fillWidth: true; height: 64
                        color: isCalibrationCompleted ? "#f0fdf4" : surfaceColor
                        border.color: isCalibrationCompleted ? "#bbf7d0" : borderColor
                        border.width: 1; radius: 8

                        RowLayout {
                            anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                            Rectangle {
                                width: 4; height: parent.height; radius: 2
                                color: isCalibrationCompleted ? successColor : primaryColor
                            }
                            Text {
                                Layout.fillWidth: true
                                text: isCalibrationCompleted
                                    ? "✓  Calibration completed successfully! Click 'Reboot & Apply' to finalize changes."
                                    : compassCalibrationModel
                                        ? (compassCalibrationModel.statusText || "Ready to begin calibration process")
                                        : "Ready to begin calibration process"
                                color: isCalibrationCompleted ? "#166534" : textSecondary
                                font.pixelSize: 12; wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }

            // ─────────────────────────────────────────────────────────────────
            //  SYSTEM ACTIONS
            // ─────────────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 112
                color: cardColor; radius: 12; border.color: borderColor; border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14
                    Text { text: "System Actions"; color: textPrimary; font.pixelSize: 14; font.weight: Font.DemiBold }

                    RowLayout {
                        spacing: 10

                        Rectangle {
                            width: 155; height: 38; radius: 8
                            color: isDroneConnected ? (rbArea.containsMouse ? "#0891b2" : "#06b6d4") : "#9ca3af"
                            Text { anchors.centerIn: parent; text: "Reboot Ardupilot"; color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                id: rbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: isDroneConnected
                                onClicked: { if (compassCalibrationModel) compassCalibrationModel.rebootAutopilot() }
                            }
                        }

                        Rectangle {
                            width: 175; height: 38; radius: 8
                            color: isDroneConnected ? (lvcArea.containsMouse ? "#ea580c" : "#f97316") : "#9ca3af"
                            Text { anchors.centerIn: parent; text: "Large Vehicle MagCal"; color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                id: lvcArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: isDroneConnected
                                onClicked: { if (compassCalibrationModel && isDroneConnected) compassCalibrationModel.startCalibration() }
                            }
                        }
                    }
                }
            }

            Item { height: 16 }
        }
    }

    Component.onDestruction: {
        if (compassCalibrationModel && compassCalibrationModel.calibrationStarted)
            compassCalibrationModel.stopCalibration()
    }
}

import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC   // 👈 IMPORTANT (alias)
import QtGraphicalEffects 1.10
import QtQuick.Window 2.15
import QtQuick.Layouts 1.15
import "."

Rectangle {
    id: mainContent
    // Position and width are driven by the parent in Main.qml
    color: "transparent"
    border.color: "#000000ff"
    border.width: 0.5

    // ============================
    // VIEW STATE
    // ============================
    property string leftView: "statusText"
    property string currentView: ""

    // ============================================================
    // PERSISTENT GEOFENCE STATE  (survives tab switches)
    // The Loader recreates GeoFensePanel every time — we keep the
    // state here at the parent level so it is never reset.
    // ============================================================
    property bool   gfEnabled:    false
    property int    gfType:       0
    property int    gfAction:     0
    property int    gfMaxAlt:     100
    property int    gfMaxRadius:  150

    // ============================================================
    // LEFT SIDEBAR
    // ============================================================
    Rectangle {
        id: leftPanel
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: screenTools.defaultMargins
        width: sidebarVisible ? sidebarWidthOpen : sidebarWidthClosed
        color: primaryColor
        radius: screenTools.defaultRadius
        border.color: borderColor
        border.width: screenTools.defaultBorderWidth
        clip: true

        Behavior on width {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        DropShadow {
            anchors.fill: parent
            verticalOffset: 2
            radius: 8
            samples: 17
            color: "#20000000"
            source: parent
        }

        // ============================================================
        // HUD (ALWAYS VISIBLE)
        // ============================================================
        Rectangle {
            id: hudContainer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: screenTools.defaultMargins
            height: Math.max(
                screenTools.defaultFontPixelHeight * 24,
                mainWindow.height * 0.30
            )
            color: secondaryColor
            radius: screenTools.defaultRadius * 0.7
            border.color: borderColor
            border.width: 1

            HudWidget {
                id: hudunit
                anchors.fill: parent
                anchors.margins: screenTools.smallMargins
                clip: true

                // Auto-binding handled by PFD internally
            }
        }

        // ============================================================
        // TOOLBAR — scrollable horizontal row, no Button.qml conflict
        // ============================================================
        QQC.ScrollView {
            id: leftToolbar
            anchors.top: hudContainer.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: screenTools.smallMargins
            height: toolbarRow.implicitHeight + 4
            clip: true

            // Hide the vertical scrollbar; only horizontal scrolling needed
            QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AlwaysOff
            QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AsNeeded

            Row {
                id: toolbarRow
                spacing: 8
                leftPadding: 4
                rightPadding: 4

                QQC.ToolButton {
                    text: translator ? translator.translate("Status") : "Status"
                    checkable: true
                    checked: leftView === "statusText"
                    onClicked: leftView = "statusText"
                }

                QQC.ToolButton {
                    text: translator ? translator.translate("Panel") : "Panel"
                    checkable: true
                    checked: leftView === "statusPanel"
                    onClicked: leftView = "statusPanel"
                }

                QQC.ToolButton {
                    text: translator ? translator.translate("Fail Safe") : "Fail Safe"
                    checkable: true
                    checked: leftView === "failSafe"
                    onClicked: leftView = "failSafe"
                }

                QQC.ToolButton {
                    text: translator ? translator.translate("GeoFence") : "GeoFence"
                    checkable: true
                    checked: leftView === "geoFence"
                    onClicked: leftView = "geoFence"
                }

                QQC.ToolButton {
                    text: translator ? translator.translate("DataFlash Logs") : "DataFlash Logs"
                    checkable: true
                    checked: leftView === "dataFlashLogs"
                    onClicked: leftView = "dataFlashLogs"
                }

                QQC.ToolButton {
                    text: translator ? translator.translate("MAVLink Inspector") : "MAVLink Inspector"
                    onClicked: mavlinkInspectorWindow.visible = true
                }
            }
        }

        // ============================================================
        // SCROLL AREA (ONLY BELOW TOOLBAR)
        // ============================================================
        QQC.ScrollView {
            anchors.top: leftToolbar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: screenTools.defaultMargins
            clip: true

            Column {
                width: parent.width
                spacing: screenTools.defaultSpacing

                // ============================
                // DYNAMIC VIEW LOADER
                // ============================
                Loader {
                    id: leftViewLoader
                    width: parent.width
                    asynchronous: true
                    z: 0  // Ensure loaded content stays below StatusBar
                    sourceComponent:
                        leftView === "statusText"     ? statusTextComponent   :
                        leftView === "statusPanel"    ? statusPanelComponent  :
                        leftView === "failSafe"       ? failSafeComponent     :
                        leftView === "geoFence"       ? geoFenseComponent     :
                        leftView === "dataFlashLogs"  ? dataFlashLogsComponent :
                        null
                }

                Item {
                    height: screenTools.defaultSpacing
                }
            }
        }

        // ============================================================
        // COMPONENT DEFINITIONS
        // ============================================================
        Component {
            id: statusTextComponent
            StatusTextDisplay {
                width: parent.width
            }
        }

        Component {
            id: geoFenseComponent
            GeoFensePanel {
                width: parent.width
                // Read initial values from persistent parent state
                geoFenceEnabled: mainContent.gfEnabled
                fenceType:       mainContent.gfType
                fenceAction:     mainContent.gfAction
                maxAltitude:     mainContent.gfMaxAlt
                maxRadius:       mainContent.gfMaxRadius
                // Write back to persistent parent state on any change
                onGeoFenceEnabledChanged: mainContent.gfEnabled   = geoFenceEnabled
                onFenceTypeChanged:       mainContent.gfType       = fenceType
                onFenceActionChanged:     mainContent.gfAction      = fenceAction
                onMaxAltitudeChanged:     mainContent.gfMaxAlt     = maxAltitude
                onMaxRadiusChanged:       mainContent.gfMaxRadius  = maxRadius
            }
        }

        Component {
            id: failSafeComponent
            FailSafeComponent {
                width: parent.width
            }
        }

        Component {
            id: dataFlashLogsComponent
            DataFlashLogsPanel {
                width: parent.width
            }
        }

        MavlinkInspectorWindow {
            id: mavlinkInspectorWindow
        }

        Component {
            id: statusPanelComponent
            Column {
                width: parent.width
                spacing: screenTools.defaultSpacing

                StatusPanel {
                    width: parent.width

                    altitude: mainWindow.currentAltitude
                    groundSpeed: mainWindow.currentGroundSpeed
                    yaw: mainWindow.currentYaw

                    battery: droneModel.isConnected
                             ? (droneModel.telemetry.voltage_battery || 0)
                             : 0

                    vibrationX: droneModel.isConnected
                                ? (droneModel.telemetry.vibration_x || 0) : 0
                    vibrationY: droneModel.isConnected
                                ? (droneModel.telemetry.vibration_y || 0) : 0
                    vibrationZ: droneModel.isConnected
                                ? (droneModel.telemetry.vibration_z || 0) : 0

                    gpsFixType: droneModel.isConnected
                                ? (droneModel.telemetry.gps_fix || 0) : 0
                    gpsSatellites: droneModel.isConnected
                                   ? (droneModel.telemetry.satellites_visible || 0) : 0
                }

                StatusBar {
                    width: parent.width
                    currentView: "statusPanel"  // Explicitly specific to this view
                    z: 1
                }
            }
        }

    }


    // ============================================================
    // QUICK ACCESS BUTTON
    // ============================================================
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: screenTools.defaultMargins
        width: screenTools.defaultFontPixelHeight * 3
        height: width
        radius: width / 2
        color: accentColor
        opacity: sidebarVisible ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 300 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: sidebarVisible = true
            cursorShape: Qt.PointingHandCursor
        }

        Text {
            anchors.centerIn: parent
            text: "📊"
            color: "#ffffff"
            font.pixelSize: screenTools.largeFontPointSize
        }
    }
}

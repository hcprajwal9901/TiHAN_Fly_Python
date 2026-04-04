// GeoFensePanel.qml
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    width: parent ? parent.width : 150
    height: mainCol.height + 165

    color: "#ffffff"
    radius: 6
    border.color: "#cccccc"
    border.width: 1

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#f5f5f5" }
        GradientStop { position: 0.5; color: "#e0e0e0" }
        GradientStop { position: 1.0; color: "#d5d5d5" }
    }

    // =======================
    // DATA MODEL
    // =======================
    property bool geoFenceEnabled: false   // default OFF — user must explicitly enable
    // fenceType holds the ArduPilot FENCE_TYPE bitmask value:
    //   1 = Altitude only, 2 = Circle only, 3 = Altitude + Circle
    property int fenceType: 3        // default: both (index 0 in ComboBox)

    // fenceAction holds the ArduPilot FENCE_ACTION value:
    //   0 = Report Only (NO action — fence breach is ignored!)
    //   1 = RTL or Land
    //   2 = Always Land
    // Default to 1 (RTL) so the fence actually enforces by default.
    property int fenceAction: 1
    property int maxAltitude: 100
    property int maxRadius: 150

    // Maps ComboBox index → ArduPilot FENCE_TYPE bitmask
    readonly property var fenceTypeValues: [3, 1, 2]
    // Maps ComboBox index → ArduPilot FENCE_ACTION value
    // Index 0 = "RTL"  → ArduPilot value 1 (RTL or Land)
    // Index 1 = "Land" → ArduPilot value 2 (Always Land)
    readonly property var fenceActionValues: [1, 2]

    Column {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // TITLE REMOVED as per user request

        // ================= SINGLE CONTAINER FOR ALL ROWS =================
        Rectangle {
            width: parent.width
            height: rowsColumn.height + 24 // Padding
            color: "#f9f9f9" // Light background for the box
            radius: 4
            border.color: "#bfbfbf" // Static Grey Border
            border.width: 1

            Column {
                id: rowsColumn
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 10

                // ================= ENABLE ROW =================
                RowLayout {
                    width: parent.width
                    spacing: 6

                    CheckBox {
                        id: geoFenceEnable
                        // Use imperative init to avoid a binding loop:
                        // declarative `checked: geoFenceEnabled` would overwrite
                        // the user's choice every time the binding re-evaluates.
                        Component.onCompleted: checked = geoFenceEnabled
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 12
                        onCheckedChanged: geoFenceEnabled = checked

                        indicator: Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            x: geoFenceEnable.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            border.color: geoFenceEnable.down ? "#17a81a" : "#21be2b"
                            
                            Rectangle {
                                width: 10
                                height: 10
                                x: 4
                                y: 4
                                radius: 2
                                color: "#21be2b"
                                visible: geoFenceEnable.checked
                            }
                        }
                    }

                    Text {
                        text: "Enable"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // ================= TYPE ROW =================
                RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                        text: "Type"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    ComboBox {
                        id: typeCombo
                        model: ["Altitude and Circle", "Altitude Only", "Circle Only"]
                        // currentIndex: 0=AltCircle(bitmask 3), 1=AltOnly(1), 2=CircleOnly(2)
                        Component.onCompleted: {
                            // Map initial bitmask value back to index
                            if      (fenceType === 1) currentIndex = 1
                            else if (fenceType === 2) currentIndex = 2
                            else                       currentIndex = 0  // 3 = both
                        }
                        enabled: geoFenceEnabled
                        Layout.preferredWidth: 165
                        Layout.preferredHeight: 35
                        Layout.alignment: Qt.AlignVCenter
                        // Map ComboBox index to correct ArduPilot bitmask
                        onCurrentIndexChanged: fenceType = fenceTypeValues[currentIndex]

                        delegate: ItemDelegate {
                            width: typeCombo.width
                            text: modelData
                            contentItem: Text {
                                text: modelData
                                color: typeCombo.highlightedIndex === index ? "white" : "black"
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: typeCombo.highlightedIndex === index ? "#3daee9" : "white"
                            }
                        }
                    }
                }

                // ================= ACTION ROW =================
                RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                        text: "Action"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                     ComboBox {
                        id: actionCombo
                        model: ["RTL", "Land"]
                        // Map initial ArduPilot value back to ComboBox index
                        // ArduPilot 1=RTL→index 0, ArduPilot 2=Land→index 1
                        Component.onCompleted: {
                            if (fenceAction === 2) currentIndex = 1
                            else                   currentIndex = 0  // 1 = RTL
                        }
                        enabled: geoFenceEnabled
                        Layout.preferredWidth: 165
                        Layout.preferredHeight: 35
                        Layout.alignment: Qt.AlignVCenter
                        // Map ComboBox index to correct ArduPilot FENCE_ACTION value
                        onCurrentIndexChanged: fenceAction = fenceActionValues[currentIndex]

                        delegate: ItemDelegate {
                            width: actionCombo.width
                            text: modelData
                            contentItem: Text {
                                text: modelData
                                color: actionCombo.highlightedIndex === index ? "white" : "black"
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: actionCombo.highlightedIndex === index ? "#3daee9" : "white"
                            }
                        }
                    }
                }

                // ================= MAX ALTITUDE ROW =================
                RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                        text: "Max Alt"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    SpinBox {
                        from: 10
                        to: 1000
                        value: maxAltitude
                        enabled: geoFenceEnabled
                        Layout.preferredWidth: 125
                        Layout.preferredHeight: 35
                        Layout.alignment: Qt.AlignVCenter
                        onValueChanged: maxAltitude = value
                    }

                    Text {
                        text: "m"
                        color: "black"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // ================= MAX RADIUS ROW =================
                RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                        text: "Max Radius"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    SpinBox {
                        from: 10
                        to: 5000
                        value: maxRadius
                        enabled: geoFenceEnabled
                        Layout.preferredWidth: 125
                        Layout.preferredHeight: 35
                        Layout.alignment: Qt.AlignVCenter
                        onValueChanged: maxRadius = value
                    }

                    Text {
                        text: "m"
                        color: "black"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }

        // ================= WRITE BUTTON =================
        Rectangle {
            width: parent.width
            height: 36
            radius: 4
            color: "#3daee9"

            Text {
                anchors.centerIn: parent
                text: "Write GeoFence"
                color: "white"
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (typeof droneCommander === 'undefined' || !droneCommander) {
                        console.warn("GeoFence: droneCommander not available")
                        return
                    }
                    droneCommander.writeGeoFence(
                        geoFenceEnabled,
                        fenceType,
                        fenceAction,
                        maxAltitude,
                        maxRadius
                    )
                    console.log("GeoFence write sent — Enable:", geoFenceEnabled,
                                "Type:", fenceType, "Action:", fenceAction,
                                "MaxAlt:", maxAltitude, "Radius:", maxRadius)
                    geoFenceWrittenPopup.open()
                }
            }
        }
    }

    // ================= GEO FENCE WRITTEN POPUP =================
    Popup {
        id: geoFenceWrittenPopup
        anchors.centerIn: Overlay.overlay
        width: 260
        height: 90
        modal: false
        closePolicy: Popup.NoAutoClose
        padding: 0

        // Auto-close after 2.5 seconds
        Timer {
            id: popupAutoClose
            interval: 2500
            running: geoFenceWrittenPopup.visible
            repeat: false
            onTriggered: geoFenceWrittenPopup.close()
        }

        background: Rectangle {
            radius: 10
            color: "#1a1a2e"
            border.color: "#3daee9"
            border.width: 2

            // Glow effect
            layer.enabled: true
        }

        contentItem: Item {
            anchors.fill: parent

            // Check icon
            Rectangle {
                id: checkCircle
                width: 32
                height: 32
                radius: 16
                color: "#21be2b"
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: checkCircle.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                spacing: 2

                Text {
                    text: "Geo Fence Written"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.bold: true
                    font.family: "Consolas"
                }

                Text {
                    text: "Parameters saved to drone"
                    color: "#aaaacc"
                    font.pixelSize: 11
                    font.family: "Consolas"
                }
            }
        }

        // Fade-in animation
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.85; to: 1.0; duration: 250; easing.type: Easing.OutBack }
        }

        // Fade-out animation
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200; easing.type: Easing.InCubic }
        }
    }
}

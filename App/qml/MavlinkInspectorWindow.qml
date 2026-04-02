import QtQuick 2.15
import QtQuick.Controls 1.4 as OldControls
import QtQuick.Controls 2.15 as NewControls
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import "."

Window {
    id: inspectorWindow
    width: 1000
    height: 680
    visible: false
    title: "MAVLink Inspector"

    modality: Qt.NonModal
    color: "#2b2b2b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // ── Toolbar ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            NewControls.CheckBox {
                id: chkGCS
                text: "Show GCS Traffic"
                checked: true
                onCheckedChanged: {
                    if (typeof mavlinkInspectorModel !== "undefined") {
                        mavlinkInspectorModel.showGcs = checked
                    }
                }

                contentItem: Text {
                    text: chkGCS.text
                    font.pixelSize: 14
                    color: "#e0e0e0"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: chkGCS.indicator.width + chkGCS.spacing
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ── Tree View ─────────────────────────────────────────────
        // Hierarchy: Vehicle → Component → Message → Fields
        //
        // Col 0  Name / field name
        // Col 1  Hz (messages) | live value (fields)
        // Col 2  Msg ID (messages) | type label (fields)
        // Col 3  Bandwidth (messages only)
        OldControls.TreeView {
            id: messageTree
            Layout.fillWidth: true
            Layout.fillHeight: true

            model: inspectorWindow.visible ? mavlinkInspectorModel : null

            OldControls.TableViewColumn {
                role: "messageName"
                title: "Name / Field"
                width: 220
            }

            OldControls.TableViewColumn {
                role: "frequency"
                title: "Value / Hz"
                width: 340
            }

            OldControls.TableViewColumn {
                role: "messageId"
                title: "ID / Type"
                width: 120
            }

            OldControls.TableViewColumn {
                role: "bandwidth"
                title: "Bandwidth"
                width: 100
            }

            // ── Item text ────────────────────────────────────────
            itemDelegate: Item {
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    width: parent.width - 10
                    color: "#e0e0e0"
                    elide: Text.ElideRight
                    text: styleData.value !== undefined ? styleData.value : ""
                    font.pixelSize: 13
                }
            }

            // ── Column headers ───────────────────────────────────
            headerDelegate: Rectangle {
                height: 24
                color: "#3d3d3d"
                border.color: "#555"
                Text {
                    anchors.centerIn: parent
                    text: styleData.value
                    color: "#e0e0e0"
                    font.bold: true
                    font.pixelSize: 13
                }
            }

            // ── Row background ───────────────────────────────────
            rowDelegate: Rectangle {
                height: 22
                color: styleData.selected ? "#4a90e2"
                                          : (styleData.row % 2 === 0 ? "#333333" : "#2b2b2b")
            }
        }
    }
}

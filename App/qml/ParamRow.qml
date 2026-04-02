import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10

Item {
    id: root

    property string   rowLabel:   ""
    property var      dataKeys:   ["p","i","d","imax","filt"]
    property int      axisIndex:  0
    property int      modeIndex:  0
    property var      pidSource
    property string   fontFam:    "Consolas"
    property color    accentClr:  "#0066cc"
    property color    borderC:    "#d0d7de"
    property color    labelC:     "#495057"

    height: 50

    property var curData: (pidSource && axisIndex >= 0 && modeIndex >= 0)
        ? pidSource[axisIndex][modeIndex]
        : null

    Rectangle {
        anchors.fill: parent
        color: rowHov.containsMouse ? "#fafbfc" : "transparent"

        MouseArea {
            id: rowHov
            anchors.fill: parent
            hoverEnabled: true
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16

            Text {
                width: 170
                height: parent.height
                text: root.rowLabel
                font.pixelSize: 13
                font.family: root.fontFam
                color: root.labelC
                verticalAlignment: Text.AlignVCenter
            }

            Repeater {
                model: root.dataKeys

                delegate: Item {
                    width: 112
                    height: parent.height

                    Rectangle {
                        anchors.centerIn: parent
                        width: 90
                        height: 34
                        radius: 7
                        color: "#f8f9fa"
                        border.color: fi.activeFocus ? root.accentClr : root.borderC
                        border.width: fi.activeFocus ? 2 : 1

                        TextInput {
                            id: fi
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: root.curData ? (root.curData[modelData] !== undefined ? root.curData[modelData] : "0.000") : "0.000"
                            font.pixelSize: 14
                            font.family: root.fontFam
                            font.weight: Font.DemiBold
                            color: root.accentClr
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            selectByMouse: true
                            validator: DoubleValidator {
                                decimals: 4
                                notation: DoubleValidator.StandardNotation
                            }
                        }
                    }
                }
            }
        }
    }
}
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10

Item {
    id: root

    property string rowLabel:   ""
    property color  accentClr:  "#0066cc"
    property real   defaultVal: 0.5
    property string fontFam:    "Consolas"
    property color  dangerC:    "#dc3545"
    property color  borderC:    "#d0d7de"

    height: 54

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        Column {
            width: 230
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: root.rowLabel
                font.pixelSize: 13
                font.family: root.fontFam
                color: "#495057"
            }

            Text {
                text: sensSlider.value.toFixed(2)
                font.pixelSize: 12
                font.family: root.fontFam
                font.weight: Font.DemiBold
                color: root.accentClr
            }
        }

        Slider {
            id: sensSlider
            width: parent.width - 230 - 100 - 32
            height: 54
            from: 0
            to: 1
            value: root.defaultVal
            stepSize: 0.01

            background: Item {
                x: sensSlider.leftPadding
                y: sensSlider.topPadding + sensSlider.availableHeight / 2 - 4
                width: sensSlider.availableWidth
                height: 8

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: "#e9ecef"

                    Rectangle {
                        width: sensSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 4
                        color: root.accentClr

                        Behavior on width { NumberAnimation { duration: 60 } }
                    }
                }
            }

            handle: Rectangle {
                x: sensSlider.leftPadding + sensSlider.visualPosition * (sensSlider.availableWidth - width)
                y: sensSlider.topPadding + sensSlider.availableHeight / 2 - height / 2
                width: 22
                height: 22
                radius: 11
                color: root.accentClr
                border.color: "#ffffff"
                border.width: 3

                layer.enabled: true
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 4
                    samples: 9
                    color: "#40000000"
                }
            }
        }

        Rectangle {
            width: 72
            height: 30
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            color: resetHov.containsMouse ? "#f8d7da" : "#fff5f5"
            border.color: root.dangerC
            border.width: 1

            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "Reset"
                font.pixelSize: 12
                font.family: root.fontFam
                color: root.dangerC
            }

            MouseArea {
                id: resetHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sensSlider.value = root.defaultVal
            }
        }
    }
}
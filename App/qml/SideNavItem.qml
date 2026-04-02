import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root

    property string itemLabel: ""
    property bool   selected:  false
    property color  selColor:  "#0066cc"
    property string fontFamily: "Consolas"

    signal itemClicked()

    width: parent ? parent.width : 128
    height: 36
    radius: 7
    color: selected
        ? Qt.lighter(selColor, 1.55)
        : (ma.containsMouse ? "#f0f4f8" : "transparent")

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        visible: root.selected
        width: 3
        height: 20
        radius: 2
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.selColor
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 14
        text: root.itemLabel
        font.pixelSize: 13
        font.family: root.fontFamily
        font.weight: root.selected ? Font.Bold : Font.Normal
        color: root.selected ? root.selColor : "#444c56"
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.itemClicked()
    }
}
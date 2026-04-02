import QtQuick 2.15

Rectangle {
    id: root

    property string label:    "Button"
    property color  bcolor:   "#0066cc"
    property bool   outlined: false
    property string fontFamily: "Consolas"

    signal clicked()

    width:  btnLabel.implicitWidth + 28
    height: 36
    radius: 8

    color: outlined
        ? (bm.containsMouse ? Qt.lighter(bcolor, 1.9) : "transparent")
        : (bm.pressed
            ? Qt.darker(bcolor, 1.12)
            : (bm.containsMouse ? Qt.lighter(bcolor, 1.1) : bcolor))

    border.color: bcolor
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: btnLabel
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: 13
        font.family: root.fontFamily
        font.weight: Font.Medium
        color: root.outlined ? root.bcolor : "#ffffff"
    }

    MouseArea {
        id: bm
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
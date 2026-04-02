import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    property string title:       ""
    property color  accentColor: "#00e5ff"

    Layout.fillWidth: true; Layout.preferredHeight: 30; color: "#141f2b"

    RowLayout {
        anchors.fill: parent; spacing: 0
        Rectangle { width: 3; height: parent.height; color: accentColor }
        Item    { width: 10 }
        Text {
            Layout.fillWidth: true; text: title; color: accentColor; opacity: 0.92
            font.family: "Consolas"; font.pixelSize: 16
            font.weight: Font.DemiBold; font.letterSpacing: 1.4
        }
    }
}
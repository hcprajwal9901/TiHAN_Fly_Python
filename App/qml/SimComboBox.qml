import QtQuick 2.15
import QtQuick.Controls 2.15

ComboBox {
    id: root
    implicitHeight: 34

    contentItem: Text {
        leftPadding: 10; text: root.displayText; color: "white"
        font.family: "Consolas"; font.pixelSize: 16
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        color: "#1c2c3c"; radius: 5
        border.color: root.activeFocus ? "#00e5ff" : "#2a4a5a"
        border.width: root.activeFocus ? 2 : 1
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    indicator: Text {
        x: root.width - width - 10; anchors.verticalCenter: parent.verticalCenter
        text: "▾"; color: "#00e5ff"; font.family: "Consolas"; font.pixelSize: 16
    }

    delegate: ItemDelegate {
        width: root.width
        contentItem: Text {
            text: modelData; leftPadding: 10; verticalAlignment: Text.AlignVCenter
            color: root.currentIndex === index ? "#00e5ff" : "#cccccc"
            font.family: "Consolas"; font.pixelSize: 16
        }
        background: Rectangle {
            color: hovered ? "#2a4a5a" : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    popup: Popup {
        y: root.height + 2; width: root.width
        implicitHeight: contentItem.implicitHeight; padding: 2
        background: Rectangle { color: "#1c2c3c"; border.color: "#00e5ff"; border.width: 1; radius: 5 }
        contentItem: ListView {
            clip: true; implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
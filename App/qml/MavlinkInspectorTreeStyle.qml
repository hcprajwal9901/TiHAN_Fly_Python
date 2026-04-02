import QtQuick 2.15
import QtQuick.Controls.Styles 1.4

TreeViewStyle {
    backgroundColor: "#2b2b2b"
    alternateBackgroundColor: "#333333"
    textColor: "#e0e0e0"
    
    headerDelegate: Rectangle {
        height: 24
        color: "#3d3d3d"
        border.color: "#555"
        Text {
            anchors.centerIn: parent
            text: styleData.value
            color: "#e0e0e0"
            font.bold: true
        }
    }
    
    rowDelegate: Rectangle {
        height: 20
        color: styleData.selected ? "#4a90e2" : (styleData.row % 2 == 0 ? "#333" : "#2b2b2b")
    }

    branchDelegate: Item {
        width: 20
        height: 20
        Text {
            anchors.centerIn: parent
            text: styleData.isExpanded ? "▼" : "▶"
            color: "#e0e0e0"
            font.pixelSize: 10
            visible: styleData.hasChildren
        }
    }
    
    itemDelegate: Item {
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 5
            color: "#e0e0e0"
            elide: Text.ElideRight
            text: styleData.value !== undefined ? styleData.value : ""
            font.pixelSize: 13
        }
    }
}

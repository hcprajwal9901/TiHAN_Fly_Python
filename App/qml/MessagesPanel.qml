import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10

Rectangle {
    id: messagePanel
    color: "#ffffff"
    radius: 8
    border.color: "#dee2e6"
    border.width: 1
    
    property int maxMessages: 100
    property bool autoScroll: true
    
    // Message types enum
    readonly property int msgInfo: 0
    readonly property int msgSuccess: 1
    readonly property int msgWarning: 2
    readonly property int msgError: 3
    readonly property int msgDebug: 4
    
    // Header
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40
        color: "#f8f9fa"
        radius: 8
        border.color: "#dee2e6"
        border.width: 1
        
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 15
            spacing: 10
            
            Text {
                text: "📋"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            
            Text {
                text: "Console Messages"
                font.family: "Segoe UI"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: "#212529"
                anchors.verticalCenter: parent.verticalCenter
            }
            
            Rectangle {
                width: 30
                height: 20
                color: "#0066cc"
                radius: 10
                anchors.verticalCenter: parent.verticalCenter
                
                Text {
                    anchors.centerIn: parent
                    text: messageListModel.count
                    color: "#ffffff"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }
        }
        
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 10
            spacing: 5
            
            // Auto-scroll toggle
            Rectangle {
                width: 30
                height: 30
                color: autoScroll ? "#28a745" : "#6c757d"
                radius: 4
                
                Text {
                    anchors.centerIn: parent
                    text: "↓"
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: autoScroll = !autoScroll
                }
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }
            
            // Clear button
            Rectangle {
                width: 30
                height: 30
                color: "#dc3545"
                radius: 4
                
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: messageListModel.clear()
                }
            }
        }
    }
    
    // Message List
    Rectangle {
        id: messageContainer
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        color: "#ffffff"
        radius: 8
        
        ScrollView {
            id: scrollView
            anchors.fill: parent
            anchors.margins: 5
            clip: true
            
            ScrollBar.vertical: ScrollBar {
                width: 10
                policy: ScrollBar.AsNeeded
                
                background: Rectangle {
                    color: "#e0e0e0"
                    radius: 5
                }
                
                contentItem: Rectangle {
                    color: "#0066cc"
                    radius: 5
                }
            }
            
            ListView {
                id: messageListView
                width: parent.width
                model: messageListModel
                spacing: 2
                
                delegate: Rectangle {
                    width: messageListView.width
                    height: messageText.height + 16
                    color: index % 2 === 0 ? "#ffffff" : "#f8f9fa"
                    radius: 4
                    
                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10
                        
                        // Timestamp
                        Text {
                            text: model.timestamp
                            font.family: "Consolas"
                            font.pixelSize: 10
                            color: "#6c757d"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 80
                        }
                        
                        // Type indicator
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: {
                                switch(model.type) {
                                    case messagePanel.msgInfo: return "#0066cc"
                                    case messagePanel.msgSuccess: return "#28a745"
                                    case messagePanel.msgWarning: return "#ffc107"
                                    case messagePanel.msgError: return "#dc3545"
                                    case messagePanel.msgDebug: return "#6c757d"
                                    default: return "#0066cc"
                                }
                            }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        // Message text
                        Text {
                            id: messageText
                            text: model.message
                            font.family: "Consolas"
                            font.pixelSize: 11
                            color: "#212529"
                            wrapMode: Text.Wrap
                            width: parent.width - 110
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            // Optional: copy message to clipboard or show details
                        }
                    }
                }
                
                onCountChanged: {
                    if (autoScroll && count > 0) {
                        positionViewAtEnd()
                    }
                }
            }
        }
        
        // Empty state
        Column {
            anchors.centerIn: parent
            spacing: 10
            visible: messageListModel.count === 0
            
            Text {
                text: "📭"
                font.pixelSize: 48
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.3
            }
            
            Text {
                text: "No messages yet"
                font.family: "Segoe UI"
                font.pixelSize: 14
                color: "#6c757d"
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    
    // Message Model
    ListModel {
        id: messageListModel
    }
    
    // Public functions
    function addMessage(message, type) {
        var timestamp = Qt.formatDateTime(new Date(), "hh:mm:ss")
        
        messageListModel.append({
            "timestamp": timestamp,
            "message": message,
            "type": type || messagePanel.msgInfo
        })
        
        // Limit messages
        if (messageListModel.count > maxMessages) {
            messageListModel.remove(0)
        }
    }
    
    function log(message) {
        addMessage(message, messagePanel.msgInfo)
    }
    
    function success(message) {
        addMessage(message, messagePanel.msgSuccess)
    }
    
    function warning(message) {
        addMessage(message, messagePanel.msgWarning)
    }
    
    function error(message) {
        addMessage(message, messagePanel.msgError)
    }
    
    function debug(message) {
        addMessage(message, messagePanel.msgDebug)
    }
    
    function clear() {
        messageListModel.clear()
    }
}
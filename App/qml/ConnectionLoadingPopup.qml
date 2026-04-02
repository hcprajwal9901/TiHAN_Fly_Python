import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10

Popup {
    id: loadingPopup
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose  // Prevent closing by clicking outside
    
    anchors.centerIn: Overlay.overlay
    width: 400
    height: 300
    
    // Properties
    property string connectionString: ""
    property bool isConnecting: false
    property int dotsCount: 0
    
    background: Rectangle {
        color: "#ffffff"
        radius: 16
        border.color: "#dee2e6"
        border.width: 2
        
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 8
            radius: 16
            samples: 33
            color: "#40000000"
        }
    }
    
    // Content
    Column {
        anchors.centerIn: parent
        spacing: 30
        width: parent.width - 60
        
        // Connection icon with animation
        Rectangle {
            width: 80
            height: 80
            radius: 40
            color: "#e3f2fd"
            anchors.horizontalCenter: parent.horizontalCenter
            
            Text {
                anchors.centerIn: parent
                text: "📡"
                font.pixelSize: 40
                
                RotationAnimation on rotation {
                    running: loadingPopup.isConnecting
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 2000
                }
            }
        }
        
        // Connection status text
        Column {
            width: parent.width
            spacing: 10
            
            Text {
                width: parent.width
                text: "Connecting to Drone"
                font.pixelSize: 22
                font.weight: Font.Bold
                font.family: "Consolas"
                color: "#212529"
                horizontalAlignment: Text.AlignHCenter
            }
            
            Text {
                id: animatedDotsText
                width: parent.width
                text: "Please wait" + ".".repeat(loadingPopup.dotsCount)
                font.pixelSize: 16
                font.family: "Consolas"
                color: "#6c757d"
                horizontalAlignment: Text.AlignHCenter
            }
        }
        
        // Connection details
        Rectangle {
            width: parent.width
            height: 60
            radius: 8
            color: "#f8f9fa"
            border.color: "#dee2e6"
            border.width: 1
            
            Column {
                anchors.centerIn: parent
                spacing: 5
                
                Text {
                    text: "Connection String:"
                    font.pixelSize: 12
                    font.family: "Consolas"
                    color: "#6c757d"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: loadingPopup.connectionString
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.family: "Consolas"
                    color: "#0066cc"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
        
        // Loading progress bar
        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: "#e9ecef"
            
            Rectangle {
                id: progressBar
                height: parent.height
                radius: parent.radius
                color: "#0066cc"
                width: 0
                
                SequentialAnimation on width {
                    running: loadingPopup.isConnecting
                    loops: Animation.Infinite
                    
                    NumberAnimation {
                        from: 0
                        to: parent.parent.width
                        duration: 1500
                        easing.type: Easing.InOutQuad
                    }
                    
                    NumberAnimation {
                        from: parent.parent.width
                        to: 0
                        duration: 1500
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
        
        // Cancel button
        Button {
            width: 120
            height: 40
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Cancel"
            
            background: Rectangle {
                radius: 8
                color: parent.pressed ? "#bd2130" : (parent.hovered ? "#c82333" : "#dc3545")
                border.color: "#bd2130"
                border.width: 1
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: parent.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.family: "Consolas"
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: {
                console.log("Connection cancelled by user")
                loadingPopup.isConnecting = false
                
                // Disconnect the drone
                if (typeof droneModel !== 'undefined') {
                    droneModel.disconnectDrone()
                }
                
                loadingPopup.close()
            }
        }
    }
    
    // Animated dots timer
    Timer {
        id: dotsTimer
        interval: 500
        running: loadingPopup.isConnecting
        repeat: true
        
        onTriggered: {
            loadingPopup.dotsCount = (loadingPopup.dotsCount + 1) % 4
        }
    }
    
    // Reset when opened
    onOpened: {
        isConnecting = true
        dotsCount = 0
        dotsTimer.restart()
    }
    
    // Cleanup when closed
    onClosed: {
        isConnecting = false
        dotsTimer.stop()
    }
}
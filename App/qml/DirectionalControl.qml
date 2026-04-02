import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10

Rectangle {
    id: root
    width: 200
    height: 200
    color: "transparent"
    
    // Signals for direction buttons
    signal upPressed()
    signal upReleased()
    signal downPressed()
    signal downReleased()
    signal leftPressed()
    signal leftReleased()
    signal rightPressed()
    signal rightReleased()
    signal okPressed()
    signal okReleased()
    
    // Properties
    property bool upActive: false
    property bool downActive: false
    property bool leftActive: false
    property bool rightActive: false
    property bool okActive: false
    
    // Color scheme matching the image
    property color buttonColorNormal: "#8B9FFF"
    property color buttonColorPressed: "#6B7FDF"
    property color shadowColor: "#4058CC"
    
    // OK button colors - Green
    property color okButtonColorNormal: "#28a745"
    property color okButtonColorPressed: "#218838"
    property color okButtonShadow: "#1e7e34"
    
    // Connect to backend controller
    Connections {
        target: directionalPadController
        
        function onStatusChanged(message, severity) {
            console.log("[DirectionalPad] Status:", message)
            // Optionally show message in UI
        }
        
        function onArmStatusChanged(armed) {
            console.log("[DirectionalPad] Armed status:", armed)
        }
    }
    
    // Container for directional buttons (lower z-order)
    Item {
        id: directionalButtons
        anchors.fill: parent
        z: 1
        
        // Up Button - Forward
        Item {
            id: upButton
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 0
            width: 50
            height: 60
            
            Canvas {
                id: upArrow
                anchors.fill: parent
                
                property bool pressed: upActive
                
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    
                    // Shadow layer
                    ctx.fillStyle = shadowColor
                    ctx.beginPath()
                    ctx.moveTo(width / 2, 5)
                    ctx.lineTo(width - 5, height - 5)
                    ctx.lineTo(width / 2, height - 15)
                    ctx.lineTo(5, height - 5)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Main arrow
                    ctx.fillStyle = pressed ? buttonColorPressed : buttonColorNormal
                    ctx.beginPath()
                    ctx.moveTo(width / 2, 0)
                    ctx.lineTo(width - 8, height - 8)
                    ctx.lineTo(width / 2, height - 18)
                    ctx.lineTo(8, height - 8)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Highlight gradient
                    var gradient = ctx.createLinearGradient(0, 0, 0, height)
                    gradient.addColorStop(0, "rgba(255, 255, 255, 0.4)")
                    gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.0)")
                    ctx.fillStyle = gradient
                    ctx.beginPath()
                    ctx.moveTo(width / 2, 0)
                    ctx.lineTo(width - 8, height - 8)
                    ctx.lineTo(width / 2, height - 18)
                    ctx.lineTo(8, height - 8)
                    ctx.closePath()
                    ctx.fill()
                }
                
                onPressedChanged: requestPaint()
            }
            
            DropShadow {
                anchors.fill: upArrow
                source: upArrow
                horizontalOffset: 0
                verticalOffset: upActive ? 2 : 4
                radius: upActive ? 8 : 12
                samples: 17
                color: "#40000000"
                transparentBorder: true
            }
            
            MouseArea {
                anchors.fill: parent
                onPressed: {
                    upActive = true
                    root.upPressed()
                    // Call backend to move forward
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.moveForward()
                    }
                }
                onReleased: {
                    upActive = false
                    root.upReleased()
                    // Stop movement
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.stopMovement()
                    }
                }
            }
        }
        
        // Down Button - Backward
        Item {
            id: downButton
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0
            width: 50
            height: 60
            
            Canvas {
                id: downArrow
                anchors.fill: parent
                
                property bool pressed: downActive
                
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    
                    // Shadow layer
                    ctx.fillStyle = shadowColor
                    ctx.beginPath()
                    ctx.moveTo(width / 2, height - 5)
                    ctx.lineTo(5, 5)
                    ctx.lineTo(width / 2, 15)
                    ctx.lineTo(width - 5, 5)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Main arrow
                    ctx.fillStyle = pressed ? buttonColorPressed : buttonColorNormal
                    ctx.beginPath()
                    ctx.moveTo(width / 2, height)
                    ctx.lineTo(8, 8)
                    ctx.lineTo(width / 2, 18)
                    ctx.lineTo(width - 8, 8)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Highlight gradient
                    var gradient = ctx.createLinearGradient(0, 0, 0, height)
                    gradient.addColorStop(0, "rgba(255, 255, 255, 0.4)")
                    gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.0)")
                    ctx.fillStyle = gradient
                    ctx.beginPath()
                    ctx.moveTo(width / 2, height)
                    ctx.lineTo(8, 8)
                    ctx.lineTo(width / 2, 18)
                    ctx.lineTo(width - 8, 8)
                    ctx.closePath()
                    ctx.fill()
                }
                
                onPressedChanged: requestPaint()
            }
            
            DropShadow {
                anchors.fill: downArrow
                source: downArrow
                horizontalOffset: 0
                verticalOffset: downActive ? 2 : 4
                radius: downActive ? 8 : 12
                samples: 17
                color: "#40000000"
                transparentBorder: true
            }
            
            MouseArea {
                anchors.fill: parent
                onPressed: {
                    downActive = true
                    root.downPressed()
                    // Call backend to move backward
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.moveBackward()
                    }
                }
                onReleased: {
                    downActive = false
                    root.downReleased()
                    // Stop movement
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.stopMovement()
                    }
                }
            }
        }
        
        // Left Button
        Item {
            id: leftButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 0
            width: 60
            height: 50
            
            Canvas {
                id: leftArrow
                anchors.fill: parent
                
                property bool pressed: leftActive
                
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    
                    // Shadow layer
                    ctx.fillStyle = shadowColor
                    ctx.beginPath()
                    ctx.moveTo(5, height / 2)
                    ctx.lineTo(width - 5, 5)
                    ctx.lineTo(width - 15, height / 2)
                    ctx.lineTo(width - 5, height - 5)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Main arrow
                    ctx.fillStyle = pressed ? buttonColorPressed : buttonColorNormal
                    ctx.beginPath()
                    ctx.moveTo(0, height / 2)
                    ctx.lineTo(width - 8, 8)
                    ctx.lineTo(width - 18, height / 2)
                    ctx.lineTo(width - 8, height - 8)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Highlight gradient
                    var gradient = ctx.createLinearGradient(0, 0, width, 0)
                    gradient.addColorStop(0, "rgba(255, 255, 255, 0.4)")
                    gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.0)")
                    ctx.fillStyle = gradient
                    ctx.beginPath()
                    ctx.moveTo(0, height / 2)
                    ctx.lineTo(width - 8, 8)
                    ctx.lineTo(width - 18, height / 2)
                    ctx.lineTo(width - 8, height - 8)
                    ctx.closePath()
                    ctx.fill()
                }
                
                onPressedChanged: requestPaint()
            }
            
            DropShadow {
                anchors.fill: leftArrow
                source: leftArrow
                horizontalOffset: leftActive ? -1 : -2
                verticalOffset: leftActive ? 1 : 2
                radius: leftActive ? 8 : 12
                samples: 17
                color: "#40000000"
                transparentBorder: true
            }
            
            MouseArea {
                anchors.fill: parent
                onPressed: {
                    leftActive = true
                    root.leftPressed()
                    // Call backend to move left
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.moveLeft()
                    }
                }
                onReleased: {
                    leftActive = false
                    root.leftReleased()
                    // Stop movement
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.stopMovement()
                    }
                }
            }
        }
        
        // Right Button
        Item {
            id: rightButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 0
            width: 60
            height: 50
            
            Canvas {
                id: rightArrow
                anchors.fill: parent
                
                property bool pressed: rightActive
                
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    
                    // Shadow layer
                    ctx.fillStyle = shadowColor
                    ctx.beginPath()
                    ctx.moveTo(width - 5, height / 2)
                    ctx.lineTo(5, height - 5)
                    ctx.lineTo(15, height / 2)
                    ctx.lineTo(5, 5)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Main arrow
                    ctx.fillStyle = pressed ? buttonColorPressed : buttonColorNormal
                    ctx.beginPath()
                    ctx.moveTo(width, height / 2)
                    ctx.lineTo(8, height - 8)
                    ctx.lineTo(18, height / 2)
                    ctx.lineTo(8, 8)
                    ctx.closePath()
                    ctx.fill()
                    
                    // Highlight gradient
                    var gradient = ctx.createLinearGradient(0, 0, width, 0)
                    gradient.addColorStop(0, "rgba(255, 255, 255, 0.4)")
                    gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.0)")
                    ctx.fillStyle = gradient
                    ctx.beginPath()
                    ctx.moveTo(width, height / 2)
                    ctx.lineTo(8, height - 8)
                    ctx.lineTo(18, height / 2)
                    ctx.lineTo(8, 8)
                    ctx.closePath()
                    ctx.fill()
                }
                
                onPressedChanged: requestPaint()
            }
            
            DropShadow {
                anchors.fill: rightArrow
                source: rightArrow
                horizontalOffset: rightActive ? 1 : 2
                verticalOffset: rightActive ? 1 : 2
                radius: rightActive ? 8 : 12
                samples: 17
                color: "#40000000"
                transparentBorder: true
            }
            
            MouseArea {
                anchors.fill: parent
                onPressed: {
                    rightActive = true
                    root.rightPressed()
                    // Call backend to move right
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.moveRight()
                    }
                }
                onReleased: {
                    rightActive = false
                    root.rightReleased()
                    // Stop movement
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.stopMovement()
                    }
                }
            }
        }
    }
    
    // OK Button (center) - ARM & FLY
    Item {
        id: okButtonContainer
        anchors.fill: parent
        z: 100
        
        Rectangle {
            id: okButton
            anchors.centerIn: parent
            width: 52
            height: 52
            radius: 26
            color: okActive ? okButtonColorPressed : okButtonColorNormal
            border.color: okButtonShadow
            border.width: 3
            
            // Shadow effect using Rectangle instead of layer
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: parent.radius
                color: "#40000000"
                z: -1
                anchors.verticalCenterOffset: okActive ? 2 : 4
                visible: true
            }
            
            Text {
                anchors.centerIn: parent
                text: "ARM\n& FLY"
                font.family: "Segoe UI"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 0.9
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                    okActive = true
                    root.okPressed()
                }
                onReleased: {
                    okActive = false
                    root.okReleased()
                    // Call backend to ARM and TAKEOFF
                    if (typeof directionalPadController !== 'undefined') {
                        directionalPadController.armAndTakeoff()
                    }
                }
            }
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            
            // Inner glow effect when pressed
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 8
                height: parent.height - 8
                radius: (parent.width - 8) / 2
                color: "transparent"
                border.color: "#ffffff"
                border.width: okActive ? 2 : 0
                opacity: 0.6
                
                Behavior on border.width {
                    NumberAnimation { duration: 150 }
                }
            }
        }
    }
    
    // Label
    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: -20
        text: "DIRECTIONAL PAD"
        font.family: "Segoe UI"
        font.pixelSize: 9
        font.weight: Font.Bold
        color: "#6c757d"
        opacity: 0.7
        z: 101
    }
}
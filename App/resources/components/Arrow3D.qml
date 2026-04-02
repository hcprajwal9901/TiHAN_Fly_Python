// Replace the directionArrow Rectangle in MapView.qml with this complete code
// Place this after the mapControls DropShadow section

// 4-Way Direction Control (Top Left Corner)
Rectangle {
    id: directionControl
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: 15
    width: 150
    height: 150
    color: "#1a1a1a"
    radius: 12
    border.color: "#404040"
    border.width: 2
    opacity: 0.95
    
    // UP Arrow Button
    Rectangle {
        id: upArrow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 5
        width: 40
        height: 35
        color: upMouseArea.pressed ? "#00897b" : (upMouseArea.containsMouse ? "#00acc1" : "transparent")
        radius: 4
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        Text {
            anchors.centerIn: parent
            text: "▲"
            font.pixelSize: 24
            font.bold: true
            color: "#00e676"
            style: Text.Outline
            styleColor: "#000000"
        }
        
        MouseArea {
            id: upMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                console.log("UP arrow clicked")
                // Move map up or drone forward
                mapWebView.runJavaScript("map.panBy(0, -100);")
            }
        }
    }
    
    // DOWN Arrow Button
    Rectangle {
        id: downArrow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        width: 40
        height: 35
        color: downMouseArea.pressed ? "#00897b" : (downMouseArea.containsMouse ? "#00acc1" : "transparent")
        radius: 4
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        Text {
            anchors.centerIn: parent
            text: "▼"
            font.pixelSize: 24
            font.bold: true
            color: "#00e676"
            style: Text.Outline
            styleColor: "#000000"
        }
        
        MouseArea {
            id: downMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                console.log("DOWN arrow clicked")
                // Move map down or drone backward
                mapWebView.runJavaScript("map.panBy(0, 100);")
            }
        }
    }
    
    // LEFT Arrow Button
    Rectangle {
        id: leftArrow
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 5
        width: 35
        height: 40
        color: leftMouseArea.pressed ? "#00897b" : (leftMouseArea.containsMouse ? "#00acc1" : "transparent")
        radius: 4
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        Text {
            anchors.centerIn: parent
            text: "◀"
            font.pixelSize: 24
            font.bold: true
            color: "#00e676"
            style: Text.Outline
            styleColor: "#000000"
        }
        
        MouseArea {
            id: leftMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                console.log("LEFT arrow clicked")
                // Move map left or drone left
                mapWebView.runJavaScript("map.panBy(-100, 0);")
            }
        }
    }
    
    // RIGHT Arrow Button
    Rectangle {
        id: rightArrow
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 5
        width: 35
        height: 40
        color: rightMouseArea.pressed ? "#00897b" : (rightMouseArea.containsMouse ? "#00acc1" : "transparent")
        radius: 4
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        Text {
            anchors.centerIn: parent
            text: "▶"
            font.pixelSize: 24
            font.bold: true
            color: "#00e676"
            style: Text.Outline
            styleColor: "#000000"
        }
        
        MouseArea {
            id: rightMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                console.log("RIGHT arrow clicked")
                // Move map right or drone right
                mapWebView.runJavaScript("map.panBy(100, 0);")
            }
        }
    }
    
    // Center OK Button
    Rectangle {
        id: centerButton
        anchors.centerIn: parent
        width: 55
        height: 55
        radius: 28
        color: centerMouseArea.pressed ? "#00897b" : (centerMouseArea.containsMouse ? "#00acc1" : "#2d2d2d")
        border.color: "#00bcd4"
        border.width: 2
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        // Inner circle for 3D effect
        Rectangle {
            anchors.centerIn: parent
            width: 45
            height: 45
            radius: 23
            color: "transparent"
            border.color: "#00bcd4"
            border.width: 1
            opacity: 0.3
        }
        
        Text {
            anchors.centerIn: parent
            text: "OK"
            font.pixelSize: 16
            font.bold: true
            color: "#ffffff"
        }
        
        MouseArea {
            id: centerMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                console.log("Center OK button clicked")
                // Add your OK action here - for example, confirm selection or reset view
                mapWebView.centerOnDroneJS()
            }
        }
        
        // Glow effect
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 4
            radius: (width / 2)
            color: "transparent"
            border.color: "#00bcd4"
            border.width: 2
            opacity: centerMouseArea.containsMouse ? 0.6 : 0
            
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }
    
    // Pulse animation for the border
    SequentialAnimation {
        running: true
        loops: Animation.Infinite
        
        NumberAnimation {
            target: directionControl
            property: "border.width"
            from: 2
            to: 3
            duration: 1500
            easing.type: Easing.InOutQuad
        }
        
        NumberAnimation {
            target: directionControl
            property: "border.width"
            from: 3
            to: 2
            duration: 1500
            easing.type: Easing.InOutQuad
        }
    }
    
    // Drop shadow effect
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        radius: parent.radius
        border.color: "#000000"
        border.width: 3
        opacity: 0.2
        z: -1
    }
    
    // Corner decorations
    Repeater {
        model: 4
        Rectangle {
            width: 8
            height: 8
            radius: 4
            color: "#00bcd4"
            opacity: 0.5
            
            x: {
                if (index === 0 || index === 3) return 8
                else return parent.width - 16
            }
            
            y: {
                if (index === 0 || index === 1) return 8
                else return parent.height - 16
            }
        }
    }
}
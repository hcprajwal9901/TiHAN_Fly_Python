import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15
Rectangle {
    id: rowRoot
    
    // Public properties
    property string labelText: "FailSafe"
    property string iconColor: "#3498db"
    property bool isEnabled: false
    property string selectedAction: "RTL"
    
    // Signals
    signal enabledChanged()
    signal actionChanged()
    
    height: 44
    color: isEnabled ? "#ecf9f2" : "#fef5f1"
    radius: 6
    border.color: isEnabled ? "#27ae60" : "#bdc3c7"
    border.width: 2
    
    // Smooth transition
    Behavior on color {
        ColorAnimation { duration: 200 }
    }
    
    Behavior on border.color {
        ColorAnimation { duration: 200 }
    }
    
    // Hover effect
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: parent.color = isEnabled ? "#d5f4e6" : "#fce8e0"
        onExited: parent.color = isEnabled ? "#ecf9f2" : "#fef5f1"
    }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12
        
        // Status Indicator (pulsing when enabled)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: rowRoot.isEnabled ? "#27ae60" : "#95a5a6"
            
            SequentialAnimation on opacity {
                running: rowRoot.isEnabled
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 800 }
                NumberAnimation { to: 1.0; duration: 800 }
            }
        }
        
        // Label
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rowRoot.labelText
            color: rowRoot.isEnabled ? "#2c3e50" : "#7f8c8d"
            font.pixelSize: 13
            font.family: "Roboto"
            font.weight: Font.DemiBold
            width: 120
        }
        
        // Toggle Switch
        Switch {
            id: toggleSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: rowRoot.isEnabled
            
            onCheckedChanged: {
                rowRoot.isEnabled = checked
                rowRoot.enabledChanged()
            }
            
            indicator: Rectangle {
                implicitWidth: 44
                implicitHeight: 22
                x: toggleSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: 11
                color: toggleSwitch.checked ? "#27ae60" : "#bdc3c7"
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
                
                Rectangle {
                    x: toggleSwitch.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: 18
                    height: 18
                    radius: 9
                    color: "#ffffff"
                    
                    // Drop shadow for toggle
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 1
                        radius: 2
                        samples: 5
                        color: "#30000000"
                    }
                    
                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
        
        // Action ComboBox
        ComboBox {
            id: actionCombo
            anchors.verticalCenter: parent.verticalCenter
            model: ["None", "RTL", "Land", "Hold"]
            currentIndex: model.indexOf(rowRoot.selectedAction)
            enabled: rowRoot.isEnabled
            width: 85
            height: 32
            
            onCurrentTextChanged: {
                rowRoot.selectedAction = currentText
                rowRoot.actionChanged()
            }
            
            background: Rectangle {
                color: actionCombo.enabled ? "#ffffff" : "#ecf0f1"
                border.color: actionCombo.enabled ? "#3498db" : "#bdc3c7"
                border.width: 1
                radius: 4
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: actionCombo.displayText
                font.pixelSize: 12
                font.family: "Roboto"
                font.weight: Font.Medium
                color: actionCombo.enabled ? "#2c3e50" : "#95a5a6"
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
            }
            
            // Custom popup style
            popup: Popup {
                y: actionCombo.height + 2
                width: actionCombo.width
                implicitHeight: contentItem.implicitHeight
                padding: 4
                
                background: Rectangle {
                    color: "#ffffff"
                    border.color: "#3498db"
                    border.width: 1
                    radius: 4
                    
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 2
                        radius: 4
                        samples: 9
                        color: "#30000000"
                    }
                }
                
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: actionCombo.popup.visible ? actionCombo.delegateModel : null
                    currentIndex: actionCombo.highlightedIndex
                }
            }
            
            delegate: ItemDelegate {
                width: actionCombo.width - 8
                height: 28
                
                contentItem: Text {
                    text: modelData
                    color: "#2c3e50"
                    font.pixelSize: 12
                    font.family: "Roboto"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8
                }
                
                background: Rectangle {
                    color: parent.highlighted ? "#3498db" : "transparent"
                    radius: 3
                }
            }
        }
    }
}
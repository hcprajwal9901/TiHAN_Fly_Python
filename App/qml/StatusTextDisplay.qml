import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15

Rectangle {
    id: statusTextDisplay
    width: parent.width
    height: 280  // REDUCED from 400 to 280
    color: "#ffffff"
    radius: 10
    border.color: "#dee2e6"
    border.width: 2



    DropShadow {
        anchors.fill: parent
        horizontalOffset: 0
        verticalOffset: 2
        radius: 6
        samples: 13
        color: "#15000000"
        source: parent
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12  // REDUCED from 15 to 12
        spacing: 8  // REDUCED from 10 to 8

        // Status Messages Area
        Rectangle {
            width: parent.width
            height: parent.height - 15  // ADJUSTED
            color: "#f8f9fa"
            radius: 8
            border.color: "#dee2e6"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 8  // REDUCED from 10 to 8
                spacing: 6  // REDUCED from 8 to 6

                // Subheader with Clear button
                Row {
                    width: parent.width
                    spacing: 8  // REDUCED from 10 to 8

                    Text {
                        text: "📡"
                        font.pixelSize: 14  // REDUCED from 16 to 14
                    }

                    Text {
                        font.family: "Segoe UI"
                        font.pixelSize: 12  // REDUCED from 13 to 12
                        font.weight: Font.DemiBold
                        color: "#495057"
                    }

                    Item { 
                        width: parent.width - 230  // ADJUSTED
                        height: 1 
                    }

                    // Message counter
                    Text {
                        text: droneModel.statusTexts.length + " msgs"
                        font.family: "Segoe UI"
                        font.pixelSize: 10  // REDUCED from 11 to 10
                        color: "#6c757d"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Clear button
                    Rectangle {
                        width: 65  // REDUCED from 70 to 65
                        height: 23  // REDUCED from 25 to 23
                        color: clearBtnMouse.pressed ? "#dc3545" : "#6c757d"
                        radius: 4
                        visible: droneModel.statusTexts.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: "Clear"
                            color: "white"
                            font.pixelSize: 10  // REDUCED from 11 to 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: clearBtnMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                droneModel.clearStatusTexts()
                            }
                        }

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                }

                // Separator
                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#dee2e6"
                }

                // Scrollable Status List
                ScrollView {
                    width: parent.width
                    height: parent.height - 40  // ADJUSTED from 50 to 40
                    clip: true

                    ScrollBar.vertical: ScrollBar {
                        id: statusScrollBar
                        width: 8  // REDUCED from 10 to 8
                        policy: ScrollBar.AsNeeded
                        
                        background: Rectangle {
                            color: "#e9ecef"
                            radius: 4
                        }
                        
                        contentItem: Rectangle {
                            color: statusScrollBar.pressed ? "#495057" : "#6c757d"
                            radius: 4
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }

                    ListView {
                        id: statusListView
                        width: parent.width - 12  // ADJUSTED
                        model: droneModel.statusTexts
                        spacing: 3  // REDUCED from 4 to 3
                        
                        // Auto-scroll to bottom when new messages arrive
                        onCountChanged: {
                            console.log("ListView message count changed:", count)
                            if (count > 0) {
                                Qt.callLater(positionViewAtEnd)
                            }
                        }

                        delegate: Rectangle {
                            width: statusListView.width
                            height: Math.max(statusTextItem.contentHeight + 16, 35)  // REDUCED padding
                            color: {
                                var text = modelData.toLowerCase()
                                if (text.includes("error") || text.includes("❌") || text.includes("critical") || text.includes("failed"))
                                    return "#f8d7da"
                                else if (text.includes("warning") || text.includes("⚠️") || text.includes("low"))
                                    return "#fff3cd"
                                else if (text.includes("success") || text.includes("✅") || text.includes("connected") || text.includes("healthy"))
                                    return "#d4edda"
                                else if (text.includes("armed") || text.includes("🔴"))
                                    return "#ffe5e5"
                                else if (text.includes("gps") || text.includes("📡") || text.includes("satellite"))
                                    return "#e7f3ff"
                                else if (text.includes("mode") || text.includes("🔄"))
                                    return "#fff4e6"
                                else if (text.includes("battery") || text.includes("🔋"))
                                    return "#fff9e6"
                                else
                                    return "#ffffff"
                            }
                            radius: 5  // REDUCED from 6 to 5
                            border.color: {
                                var text = modelData.toLowerCase()
                                if (text.includes("error") || text.includes("❌") || text.includes("critical"))
                                    return "#dc3545"
                                else if (text.includes("warning") || text.includes("⚠️") || text.includes("low"))
                                    return "#ffc107"
                                else if (text.includes("success") || text.includes("✅") || text.includes("connected"))
                                    return "#28a745"
                                else if (text.includes("armed") || text.includes("🔴"))
                                    return "#ff6b6b"
                                else if (text.includes("gps") || text.includes("📡"))
                                    return "#0066cc"
                                else
                                    return "#dee2e6"
                            }
                            border.width: 1

                            Row {
                                anchors.fill: parent
                                anchors.margins: 8  // REDUCED from 10 to 8
                                spacing: 6  // REDUCED from 8 to 6

                                // Status indicator dot
                                Rectangle {
                                    width: 6  // REDUCED from 8 to 6
                                    height: 6  // REDUCED from 8 to 6
                                    radius: 3
                                    anchors.top: parent.top
                                    anchors.topMargin: 4
                                    color: {
                                        var text = modelData.toLowerCase()
                                        if (text.includes("error") || text.includes("❌") || text.includes("critical"))
                                            return "#dc3545"
                                        else if (text.includes("warning") || text.includes("⚠️"))
                                            return "#ffc107"
                                        else if (text.includes("success") || text.includes("✅"))
                                            return "#28a745"
                                        else if (text.includes("armed") || text.includes("🔴"))
                                            return "#ff6b6b"
                                        else if (text.includes("gps") || text.includes("📡"))
                                            return "#0066cc"
                                        else
                                            return "#6c757d"
                                    }
                                }

                                Text {
                                    id: statusTextItem
                                    text: modelData
                                    font.family: "Consolas, monospace"
                                    font.pixelSize: 10  // REDUCED from 11 to 10
                                    color: {
                                        var text = modelData.toLowerCase()
                                        if (text.includes("error") || text.includes("❌") || text.includes("critical"))
                                            return "#721c24"
                                        else if (text.includes("warning") || text.includes("⚠️"))
                                            return "#856404"
                                        else if (text.includes("armed") || text.includes("🔴"))
                                            return "#c92a2a"
                                        else
                                            return "#212529"
                                    }
                                    wrapMode: Text.WordWrap
                                    width: parent.width - 25  // ADJUSTED
                                }
                            }
                        }

                        // Empty state - ONLY show when list is actually empty
                        Column {
                            visible: statusListView.count === 0
                            anchors.centerIn: parent
                            spacing: 8  // REDUCED from 10 to 8

                            Text {
                                text: "📭"
                                font.pixelSize: 40  // REDUCED from 48 to 40
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: 0.3
                            }

                            Text {
                                text: droneModel.isConnected ? 
                                      "⏳ Waiting for status messages..." : 
                                      "📡 Connect to drone to see status updates"
                                font.family: "Segoe UI"
                                font.pixelSize: 11  // REDUCED from 12 to 11
                                color: "#6c757d"
                                font.italic: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: "Status messages will appear here"
                                font.family: "Segoe UI"
                                font.pixelSize: 9  // REDUCED from 10 to 9
                                color: "#adb5bd"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
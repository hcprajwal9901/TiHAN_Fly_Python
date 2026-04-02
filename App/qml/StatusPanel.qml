
//StatusPanel.qml - FIXED VERSION
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15

Rectangle {
    id: root
    width: 280
    implicitHeight: mainColumn.implicitHeight + 28
    color: "#ffffff"
    radius: 8
    border.color: "#cccccc"
    border.width: 1

    // Professional gradient background
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#f5f5f5" }
        GradientStop { position: 0.5; color: "#e0e0e0" }
        GradientStop { position: 1.0; color: "#d5d5d5" }
    }

    // Professional data binding properties
    property real altitude: 0.0
    property real groundSpeed: 2.22
    property real yaw: 153.09
    property real battery: (droneModel && droneModel.telemetry && droneModel.telemetry.voltage_battery !== undefined)
                      ? droneModel.telemetry.voltage_battery : 0.0
    property real vibrationX: (droneModel && droneModel.telemetry && droneModel.telemetry.vibration_x !== undefined)
                            ? droneModel.telemetry.vibration_x : 0.0

    property real vibrationY: (droneModel && droneModel.telemetry && droneModel.telemetry.vibration_y !== undefined)
                            ? droneModel.telemetry.vibration_y : 0.0

    property real vibrationZ: (droneModel && droneModel.telemetry && droneModel.telemetry.vibration_z !== undefined)
                         ? droneModel.telemetry.vibration_z : 0.0

    property real gpsFixType: (droneModel && droneModel.telemetry && droneModel.telemetry.gps_fix_type !== undefined) 
                          ? droneModel.telemetry.gps_fix_type : 0

    property real gpsSatellites: (droneModel && droneModel.telemetry && droneModel.telemetry.satellites_visible !== undefined)
                             ? droneModel.telemetry.satellites_visible : 0

    property real gpsLat: (droneModel && droneModel.telemetry && droneModel.telemetry.lat !== undefined)
                      ? droneModel.telemetry.lat : 0.0

    property real gpsLon: (droneModel && droneModel.telemetry && droneModel.telemetry.lon !== undefined)
                      ? droneModel.telemetry.lon : 0.0
    property var languageManager: null
    property var translator: null
    
    // ✅ GPS Quality Properties - BOUND TO TELEMETRY
    property real gpsHdop: (droneModel && droneModel.telemetry && droneModel.telemetry.hdop !== undefined)
                       ? droneModel.telemetry.hdop : 99.99

    property real gpsAlt: (droneModel && droneModel.telemetry && droneModel.telemetry.alt !== undefined)
                        ? droneModel.telemetry.alt : 0.0

    property real gpsVel: (droneModel && droneModel.telemetry && droneModel.telemetry.gps_vel !== undefined)
                        ? droneModel.telemetry.gps_vel : 0.0

    property real gpsCog: (droneModel && droneModel.telemetry && droneModel.telemetry.gps_cog !== undefined)
                        ? droneModel.telemetry.gps_cog : 0.0

    property real gpsEph: (droneModel && droneModel.telemetry && droneModel.telemetry.gps_eph !== undefined)
                        ? droneModel.telemetry.gps_eph : 0.0

    property real gpsEpv: (droneModel && droneModel.telemetry && droneModel.telemetry.gps_epv !== undefined)
                      ? droneModel.telemetry.gps_epv : 0.0
    
    
    // Battery monitoring properties
    property real batteryPercentage: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry && droneModel.telemetry.battery_remaining !== undefined) ? droneModel.telemetry.battery_remaining : 0.0
    property real batteryCurrent: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry && droneModel.telemetry.current_battery !== undefined) ? droneModel.telemetry.current_battery : 0.0
    property real batteryRemaining: (typeof droneModel !== "undefined" && droneModel && droneModel.telemetry && droneModel.telemetry.battery_remaining_mah !== undefined) ? droneModel.telemetry.battery_remaining_mah : 0.0
    
    // Dynamic flight mode property
    property string flightMode: typeof droneModel !== "undefined" && droneModel ? droneModel.droneMode : "UNKNOWN"

    // ═══════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════
    
    function vibrationColor(value) {
        if (value < 30)
            return "#2ecc71"   // green
        else if (value < 60)
            return "#f39c12"   // orange
        else
            return "#e74c3c"   // red
    }

    function batteryColor(percentage) {
        if (percentage > 50)
            return "#2ecc71"   // green
        else if (percentage > 20)
            return "#f39c12"   // orange
        else
            return "#e74c3c"   // red
    }
    
    // ✅ GPS Status Helper Functions
    function gpsQualityColor(hdop) {
        if (hdop < 1.5)
            return "#2ecc71"  // Green - Excellent
        else if (hdop < 2.5)
            return "#f39c12"  // Orange - Good
        else
            return "#e74c3c"  // Red - Poor
    }
    
    function isGpsReadyToFly() {
        return gpsFixType >= 3 && gpsSatellites >= 6 && gpsHdop < 2.0
    }
    
    function formatCoordinate(value, isLat) {
        if (value === 0.0) return "--"
        var direction = isLat ? (value >= 0 ? "N" : "S") : (value >= 0 ? "E" : "W")
        return Math.abs(value).toFixed(4) + "° " + direction
    }

    Column {
        id:mainColumn
        anchors.fill: parent
        anchors.margins: 14
        spacing: 3

        // ═══════════════════════════════════════════════════════════════
        // FIRST ROW - VIBRATION X, Y, Z
        // ═══════════════════════════════════════════════════════════════
        Row {
            width: parent.width
            spacing: 3

            // -------- Vibration X --------
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.color: vibrationX < 30 ? "#2ecc71" : (vibrationX < 60 ? "#f39c12" : "#e74c3c")
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: (translator ? translator.translate("Vib X") : "Vib X")
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }
                }

                Text {
                    text: vibrationX.toFixed(2)
                    color: "black"
                    font.pixelSize: 13
                    font.family: "Consolas"
                    font.weight: Font.Bold
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // -------- Vibration Y --------
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.color: vibrationY < 30 ? "#2ecc71" : (vibrationY < 60 ? "#f39c12" : "#e74c3c")
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: (translator ? translator.translate("Vib Y") : "Vib Y")
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }
                }

                Text {
                    text: vibrationY.toFixed(2)
                    color: "black"
                    font.pixelSize: 13
                    font.family: "Consolas"
                    font.weight: Font.Bold
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // -------- Vibration Z --------
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.color: vibrationZ < 30 ? "#2ecc71" : (vibrationZ < 60 ? "#f39c12" : "#e74c3c")
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: (translator ? translator.translate("Vib Z") : "Vib Z")
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }
                }
                Text {
                    text: vibrationZ.toFixed(2)
                    color: "black"
                    font.pixelSize: 13
                    font.family: "Consolas"
                    font.weight: Font.Bold
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // SECOND ROW - GPS FIX, SATELLITES, VOLTAGE
        // ═══════════════════════════════════════════════════════════════
        Row {
            width: parent.width
            spacing: 3

            // ================= GPS FIX =================
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.width: 2
                border.color: gpsFixType < 3 ? "#e74c3c" : "#2ecc71"

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text {
                        text: translator ? translator.translate("GPS Fix") : "GPS Fix"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }

                    Text {
                        text: gpsFixType === 6 ? "RTK"
                             : gpsFixType === 5 ? "RTK F"
                             : gpsFixType === 4 ? "DGPS"
                             : gpsFixType === 3 ? "3D"
                             : gpsFixType === 2 ? "2D"
                             : "NO"
                        color: gpsFixType < 3 ? "#e74c3c" : "#2ecc71"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }
                }
            }

            // ================= SATELLITES =================
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.width: 2
                border.color: gpsSatellites < 6 ? "#e74c3c"
                             : gpsSatellites < 10 ? "#f39c12"
                             : "#2ecc71"

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text {
                        text: translator ? translator.translate("Sats") : "Sats"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }

                    Text {
                        text: gpsSatellites
                        color: "black"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                    }
                }
            }

            // ================= BATTERY VOLTAGE =================
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.width: 1
                border.color: "#cccccc"

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    Text {
                        id: volLabel
                        text: translator ? translator.translate("Volt") : "Volt"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: battery.toFixed(2) + " V"
                        color: "black"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.right: parent.right
                        anchors.left: volLabel.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        clip: true
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // THIRD ROW - BATTERY MONITORING
        // ═══════════════════════════════════════════════════════════════
        Row {
            width: parent.width
            spacing: 3

            // ================= BATTERY PERCENTAGE =================
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.width: 2
                border.color: batteryColor(batteryPercentage)

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    // Battery icon background
                    Rectangle {
                        id: batteryIcon
                        width: 18
                        height: 10
                        color: "transparent"
                        border.color: batteryColor(batteryPercentage)
                        border.width: 1
                        radius: 2
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter

                        // Battery fill
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            width: Math.max(0, (parent.width - 2) * (batteryPercentage / 100))
                            color: batteryColor(batteryPercentage)
                            radius: 1
                        }

                        // Battery terminal
                        Rectangle {
                            width: 2
                            height: 4
                            color: batteryColor(batteryPercentage)
                            anchors.left: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: batteryPercentage.toFixed(0) + "%"
                        color: batteryColor(batteryPercentage)
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ================= BATTERY CURRENT =================
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.width: 1
                border.color: batteryCurrent > 20 ? "#e74c3c" : "#cccccc"

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    Text {
                        id: currentLabel
                        text: translator ? translator.translate("Curr") : "Curr"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: batteryCurrent.toFixed(1) + "A"
                        color: "black"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ================= BATTERY REMAINING CAPACITY =================
            Rectangle {
                width: (parent.width - 6) / 3
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.width: 1
                border.color: "#cccccc"

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    Text {
                        id: capacityLabel
                        text: translator ? translator.translate("mAh") : "mAh"
                        color: "#ff0000"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: batteryRemaining.toFixed(0)
                        color: "black"
                        font.pixelSize: 13
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
// =======================================================
// GPS STATUS DISPLAY (BOX STYLE LIKE CURR / mAh / Volt)
// =======================================================
Rectangle {
    width: parent.width
    radius: 6
    color: "#f8f8f8"
    border.width: 2
    border.color: gpsFixType >= 3 ? "#2ecc71" : "#e74c3c"

    implicitHeight: gpsColumn.implicitHeight + 20

    Column {
        id: gpsColumn
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Text {
            text: "GPS Status Display"
            color: "#e74c3c"
            font.pixelSize: 15
            font.bold: true
            font.family: "Consolas"
        }

        // -------- FIRST ROW --------
        Row {
            width: parent.width
            spacing: 4

            // Fix Type
            Rectangle {
                width: (parent.width - 8) / 2
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6

                    Text {
                        text: "gps_fix_type"
                        color: "#ff0000"
                        font.family: "Consolas"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        text: "  " + gpsFixType
                        color: "black"
                        font.family: "Consolas"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            // Satellites
            Rectangle {
                width: (parent.width - 8) / 2
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6

                    Text {
                        text: "Sat_visible"
                        color: "#ff0000"
                        font.family: "Consolas"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        text: "  " + gpsSatellites
                        color: "black"
                        font.family: "Consolas"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }

        // -------- SECOND ROW --------
        Row {
            width: parent.width
            spacing: 4

            Rectangle {
                width: (parent.width - 8) / 2
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6

                    Text { text: "Lat"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + gpsLat.toFixed(6); color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }

            Rectangle {
                width: (parent.width - 8) / 2
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6

                    Text { text: "Lon"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + gpsLon.toFixed(6); color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }
        }

        // -------- THIRD ROW --------
        Row {
            width: parent.width
            spacing: 4

            Rectangle {
                width: (parent.width - 8) / 2
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    Text { text: "Alt"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + gpsAlt.toFixed(1) + " m"; color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }

            Rectangle {
                width: (parent.width - 8) / 2
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    Text { text: "Vel"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + (gpsVel/100).toFixed(1) + " m/s"; color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }
        }

        // -------- FOURTH ROW --------
        Row {
            width: parent.width
            spacing: 4

            Rectangle {
                width: (parent.width - 8) / 3
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    Text { text: "Cog"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + (gpsCog/100).toFixed(1) + "°"; color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }

            Rectangle {
                width: (parent.width - 8) / 3
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    Text { text: "EPH"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + (gpsEph/100).toFixed(1) + " m"; color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }

            Rectangle {
                width: (parent.width - 8) / 3
                height: 32
                radius: 4
                color: "#f0f0f0"
                border.color: "#2ecc71"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    Text { text: "EPV"; color: "#ff0000"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                    Text { text: "  " + (gpsEpv/100).toFixed(1) + " m"; color: "black"; font.family: "Consolas"; font.bold: true; font.pixelSize: 12 }
                }
            }
        }
    }
}
        // ═══════════════════════════════════════════════════════════════
        // SIXTH ROW - FLIGHT MODE
        // ═══════════════════════════════════════════════════════════════
        Row {
            width: parent.width
            spacing: 3

            Rectangle {
                width: parent.width
                height: 35
                color: "#f0f0f0"
                radius: 4
                border.color: "#cccccc"
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: (translator ? translator.translate("Flight Mode") : "Flight Mode")
                        color: "#ff0000"
                        font.pixelSize: 14
                        font.family: "Consolas"
                        font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: root.translator ? root.translator.translate(root.flightMode) : root.flightMode
                    color: "black"
                    font.pixelSize: 14
                    font.family: "Consolas"
                    font.weight: Font.Bold
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}




 
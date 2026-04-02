import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ApplicationWindow {
    id: win
    width: 320
    height: 220
    visible: false
    title: "Select Flight Mode"
    flags: Qt.Window 
    modality: Qt.ApplicationModal

    property var droneCommander
    property var droneModel

    Column {
        anchors.centerIn: parent
        spacing: 15
        width: parent.width * 0.85

        Text {
            text: "Choose flight mode"
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }

        ComboBox {
            id: modeCombo
            width: parent.width

            model: [
                "STABILIZE",
                "ACRO",
                "ALT_HOLD",
                "AUTO",
                "GUIDED",
                "LOITER",
                "RTL",
                "LAND",
                "POSHOLD",
                "BRAKE",
                "SMART_RTL"
            ]

            Component.onCompleted: {
                if (droneModel && droneModel.telemetry) {
                    const idx = model.indexOf(droneModel.telemetry.mode)
                    if (idx >= 0)
                        currentIndex = idx
                }
            }
        }

        Button {
            text: "SET MODE"
            width: parent.width
            enabled: droneModel && droneModel.isConnected

            onClicked: {
                const mode = modeCombo.currentText
                console.log("[ModeWindow] Setting mode:", mode)
                droneCommander.setMode(mode)
                win.close()
            }
        }

        Text {
            visible: modeCombo.currentText === "AUTO"
                  || modeCombo.currentText === "RTL"
                  || modeCombo.currentText === "LAND"
            text: "⚠️ Autonomous mode"
            color: "#d32f2f"
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }
    }
}

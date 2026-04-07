import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs 1.3

ApplicationWindow {
    id: root
    
    visible: true
    width: 600
    height: 650
    title: "User Params"
    color: "#1a1a1a"

    property color gridColor: "#3a3a3a"
    property color headerBg: "#252525"
    property color accentColor: "#9acd32"

    property var droneCommander: null
    property var droneModel: null
    
    ListModel {
        id: rcOptionsModel
        ListElement { text: "Do Nothing"; value: 0 }
        ListElement { text: "ACRO Mode"; value: 52 }
        ListElement { text: "ADSB Avoidance Enable"; value: 38 }
        ListElement { text: "AHRS AutoTrim"; value: 182 }
        ListElement { text: "ALTHOLD Mode"; value: 70 }
        ListElement { text: "AUTO Mode"; value: 16 }
        ListElement { text: "AUTO RTL"; value: 99 }
        ListElement { text: "AUTOTUNE Mode"; value: 17 }
        ListElement { text: "Acro Trainer"; value: 14 }
        ListElement { text: "AirMode"; value: 84 }
        ListElement { text: "Arm/Emergency Motor"; value: 165 }
        ListElement { text: "ArmDisarm (4.1/older)"; value: 41 }
        ListElement { text: "ArmDisarm (4.2/newer)"; value: 153 }
        ListElement { text: "ArmDisarm with AirMode"; value: 154 }
        ListElement { text: "AttCon Accel Limits"; value: 26 }
        ListElement { text: "AttCon Feed Forward"; value: 25 }
        ListElement { text: "Auto Mission Reset"; value: 24 }
        ListElement { text: "BRAKE Mode"; value: 33 }
        ListElement { text: "Battery MPPT Enable"; value: 172 }
        ListElement { text: "CIRCLE Mode"; value: 72 }
        ListElement { text: "Calibrate Compasses"; value: 171 }
        ListElement { text: "Camera Auto Focus"; value: 169 }
        ListElement { text: "Camera Image Tracking"; value: 174 }
        ListElement { text: "Camera Lens"; value: 175 }
        ListElement { text: "Camera Manual Focus"; value: 168 }
        ListElement { text: "Camera Mode Toggle"; value: 102 }
        ListElement { text: "Camera Record Video"; value: 166 }
        ListElement { text: "Camera Trigger"; value: 9 }
        ListElement { text: "Camera Zoom"; value: 167 }
        ListElement { text: "Clear Waypoints"; value: 58 }
        ListElement { text: "Compass Learn"; value: 62 }
        ListElement { text: "DRIFT Mode"; value: 73 }
        ListElement { text: "Disarm"; value: 81 }
        ListElement { text: "EKF Source Set"; value: 90 }
        ListElement { text: "EKF lane switch attem"; value: 103 }
        ListElement { text: "EKF yaw reset"; value: 104 }
        ListElement { text: "FFT Tune"; value: 162 }
        ListElement { text: "FLIP Mode"; value: 2 }
        ListElement { text: "FLOWHOLD Mode"; value: 71 }
        ListElement { text: "FOLLOW Mode"; value: 57 }
        ListElement { text: "Fence Enable"; value: 11 }
        ListElement { text: "FlightMode Pause/Re"; value: 178 }
        ListElement { text: "Force IS_Flying"; value: 159 }
        ListElement { text: "GPS Disable"; value: 65 }
        ListElement { text: "GPS Disable Yaw"; value: 105 }
        ListElement { text: "GUIDED Mode"; value: 55 }
        ListElement { text: "Generator"; value: 85 }
        ListElement { text: "Gripper"; value: 19 }
        ListElement { text: "InvertedFlight Enable"; value: 43 }
        ListElement { text: "KillIMU1"; value: 100 }
        ListElement { text: "KillIMU2"; value: 101 }
        ListElement { text: "KillIMU3"; value: 110 }
        ListElement { text: "LAND Mode"; value: 18 }
        ListElement { text: "LOITER Mode"; value: 56 }
        ListElement { text: "Landing Gear"; value: 29 }
        ListElement { text: "Lost Copter Sound"; value: 30 }
        ListElement { text: "Loweheiser starter"; value: 111 }
        ListElement { text: "Loweheiser throttle"; value: 218 }
        ListElement { text: "Motor Emergency Stop"; value: 31 }
        ListElement { text: "Motor Interlock"; value: 32 }
        ListElement { text: "Mount LRF enable"; value: 177 }
        ListElement { text: "Mount POI Lock"; value: 186 }
        ListElement { text: "Mount Roll/Pitch Loc"; value: 185 }
        ListElement { text: "Mount Yaw Lock"; value: 163 }
        ListElement { text: "Mount1 Pitch"; value: 213 }
        ListElement { text: "Mount1 Roll"; value: 212 }
        ListElement { text: "Mount1 Yaw"; value: 214 }
        ListElement { text: "Mount2 Pitch"; value: 216 }
        ListElement { text: "Mount2 Roll"; value: 215 }
        ListElement { text: "Mount2 Yaw"; value: 217 }
        ListElement { text: "Optflow Calibration"; value: 158 }
        ListElement { text: "POSHOLD Mode"; value: 69 }
        ListElement { text: "Parachute 3pos"; value: 23 }
        ListElement { text: "Parachute Enable"; value: 21 }
        ListElement { text: "Parachute Release"; value: 22 }
        ListElement { text: "Pause Stream Logging"; value: 164 }
        ListElement { text: "PrecLoiter Enable"; value: 39 }
        ListElement { text: "Proximity Avoidance"; value: 40 }
        ListElement { text: "RC Override Enable"; value: 46 }
        ListElement { text: "RCPassThru"; value: 1 }
        ListElement { text: "RTL"; value: 4 }
        ListElement { text: "RangeFinder Enable"; value: 10 }
        ListElement { text: "Relay1 On/Off"; value: 28 }
        ListElement { text: "Relay2 On/Off"; value: 34 }
        ListElement { text: "Relay3 On/Off"; value: 35 }
        ListElement { text: "Relay4 On/Off"; value: 36 }
        ListElement { text: "Relay5 On/Off"; value: 66 }
        ListElement { text: "Relay6 On/Off"; value: 67 }
        ListElement { text: "Retract Mount1"; value: 27 }
        ListElement { text: "Retract Mount2"; value: 113 }
        ListElement { text: "RunCam Control"; value: 78 }
    }

    Component.onCompleted: {
        console.log("UserParams UI initialized")
        
        for (var i = 6; i <= 16; i++) {
            userParamsModel.append({
                paramName: "RC" + i + "_OPTION",
                currentValue: 0,
                editedValue: -1
            })
        }

        if (droneCommander) {
            droneCommander.parametersUpdated.connect(onParametersUpdated)
            console.log("✅ Connected to DroneCommander signals")
            loadParametersFromBackend()
        }
    }

    function onParametersUpdated() {
        loadParametersFromBackend()
    }

    function loadParametersFromBackend() {
        if (!droneCommander || !droneCommander.parameters) return

        var params = droneCommander.parameters
        var loadedCount = 0
        for (var i = 0; i < userParamsModel.count; i++) {
            var item = userParamsModel.get(i)
            var pName = item.paramName
            if (params[pName] !== undefined && params[pName].value !== undefined) {
                var storedValue = Math.round(parseFloat(params[pName].value))
                console.log("📥 Loaded " + pName + " = " + params[pName].value + " -> " + storedValue)
                userParamsModel.setProperty(i, "currentValue", storedValue)
                userParamsModel.setProperty(i, "editedValue", -1) 
                loadedCount++
            } else {
                console.log("⚠️ Parameter " + pName + " not found in backend!")
            }
        }
        statusLabel.text = "✅ Parameters loaded"
    }

    function requestParameters() {
        if (!droneCommander || !droneModel || !droneModel.isConnected) {
            statusLabel.text = "❌ Drone not connected"
            return
        }
        statusLabel.text = "📡 Requesting parameters from drone..."
        droneCommander.requestAllParameters()
    }

    function writeEditedParameters() {
        if (!droneCommander || !droneModel || !droneModel.isConnected) {
            statusLabel.text = "❌ Drone not connected"
            return
        }

        var paramsToSend = {}
        var editCount = 0
        for (var i = 0; i < userParamsModel.count; i++) {
            var item = userParamsModel.get(i)
            if (item.editedValue !== -1 && item.editedValue !== item.currentValue) {
                paramsToSend[item.paramName] = item.editedValue
                editCount++
            }
        }

        if (editCount === 0) {
            statusLabel.text = "⚠️ No parameters have been edited"
            return
        }

        statusLabel.text = "💾 Writing " + editCount + " parameter(s) to drone..."
        var paramsJson = JSON.stringify(paramsToSend)
        
        var success = droneCommander.writeParameters(paramsJson)
        if (success) {
            statusLabel.text = "✅ Successfully wrote " + editCount + " parameter(s)"
            for (var j = 0; j < userParamsModel.count; j++) {
                var itm = userParamsModel.get(j)
                if (itm.editedValue !== -1) {
                    userParamsModel.setProperty(j, "currentValue", itm.editedValue)
                    userParamsModel.setProperty(j, "editedValue", -1)
                }
            }
        } else {
            statusLabel.text = "❌ Failed to write parameters"
        }
    }

    function getComboIndex(currentValue, editedValue, paramName) {
        var targetVal = Number((editedValue !== undefined && editedValue !== -1) ? editedValue : currentValue)
        // console.log("🔍 getComboIndex for " + paramName + " | current=" + currentValue + " edited=" + editedValue + " target=" + targetVal)
        for (var i = 0; i < rcOptionsModel.count; i++) {
            var itemVal = Number(rcOptionsModel.get(i).value)
            if (itemVal === targetVal) {
                // console.log("  ✅ Found match at index " + i + " for value " + targetVal)
                return i
            }
        }
        console.log("  ⚠️ No match found in rcOptionsModel for " + targetVal + ". Defaulting to index 0.")
        return 0
    }

    ListModel { id: userParamsModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#1f1f1f"
            border.color: gridColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Text {
                    text: "User Params"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.fillWidth: true
                }
                
                Text {
                    id: statusLabel
                    text: "Ready"
                    color: "white"
                    font.pixelSize: 12
                }

                Button {
                    text: "🔄 Refresh"
                    font.pixelSize: 12
                    implicitWidth: 90
                    implicitHeight: 36
                    background: Rectangle {
                        color: parent.pressed ? "#444" : (parent.hovered ? "#333" : "#222")
                        border.color: accentColor
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text; color: "white"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                    }
                    onClicked: root.requestParameters()
                }

                Button {
                    text: "✍️ Write"
                    font.pixelSize: 12
                    implicitWidth: 90
                    implicitHeight: 36
                    background: Rectangle {
                        color: parent.pressed ? "#3a5a3a" : (parent.hovered ? "#2a4a2a" : "#1a3a1a")
                        border.color: accentColor
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text; color: "white"
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                    }
                    onClicked: root.writeEditedParameters()
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 40
            color: headerBg
            border.color: gridColor
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 20
                Text { text: "Parameter"; color: "white"; font.pixelSize: 14; font.bold: true; Layout.preferredWidth: 150 }
                Text { text: "Action"; color: "white"; font.pixelSize: 14; font.bold: true; Layout.fillWidth: true }
            }
        }

        ListView {
            id: paramTable
            model: userParamsModel
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            
            // Speed up mouse wheel scrolling natively
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: {
                    var step = 150 // Scroll 3 elements per wheel tick (50px * 3)
                    if (wheel.angleDelta.y > 0) {
                        parent.contentY = Math.max(parent.contentY - step, 0)
                    } else {
                        parent.contentY = Math.min(parent.contentY + step, Math.max(0, parent.contentHeight - parent.height))
                    }
                }
            }
            
            delegate: Rectangle {
                id: delegateItem
                width: paramTable.width
                height: 50
                color: index % 2 === 0 ? "#1a1a1a" : "#1e1e1e"
                border.color: gridColor
                border.width: 1

                // Explicitly declare tracked properties to bind model attributes cleanly
                property int rowIdx: index
                property string pName: model.paramName !== undefined ? model.paramName : "Unknown"
                property int mCurrentValue: model.currentValue !== undefined ? model.currentValue : 0
                property int mEditedValue: model.editedValue !== undefined ? model.editedValue : -1

                // Watch for dynamic role changes explicitly without syntax errors
                onMCurrentValueChanged: combo.syncIndex()
                onMEditedValueChanged: combo.syncIndex()

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 20

                    Text {
                        text: model.paramName
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.preferredWidth: 150
                    }

                    ComboBox {
                        id: combo
                        Layout.fillWidth: true
                        height: 36
                        model: rcOptionsModel
                        textRole: "text"
                        valueRole: "value"
                        
                        background: Rectangle {
                            color: "#2a2a2a"
                            border.color: parent.activeFocus ? accentColor : gridColor
                            border.width: 1
                            radius: 4
                        }
                        
                        contentItem: Text {
                            leftPadding: 10
                            text: parent.displayText
                            font.pixelSize: 14
                            color: "white"
                            verticalAlignment: Text.AlignVCenter
                        }

                        // Explicit popup definition to fix scroll speed and bounds
                        popup: Popup {
                            y: combo.height - 1
                            width: combo.width
                            implicitHeight: Math.min(contentItem.implicitHeight, 350)
                            padding: 1

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: combo.popup.visible ? combo.delegateModel : null
                                currentIndex: combo.highlightedIndex
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                // Native scroll speed up
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.NoButton
                                    onWheel: {
                                        var step = 36 * 4 // Scroll 4 items per tick
                                        if (wheel.angleDelta.y > 0) {
                                            parent.contentY = Math.max(parent.contentY - step, 0)
                                        } else {
                                            parent.contentY = Math.min(parent.contentY + step, Math.max(0, parent.contentHeight - parent.height))
                                        }
                                    }
                                }
                            }
                            background: Rectangle {
                                color: "white"
                                border.color: gridColor
                                border.width: 1
                            }
                        }

                        delegate: ItemDelegate {
                            id: cbDelegate
                            width: combo.width
                            height: 36
                            hoverEnabled: true
                            
                            contentItem: Text {
                                text: model.text
                                color: "black"
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            background: Rectangle {
                                color: cbDelegate.hovered ? "#868686ff" : "#e8e8e8ff"
                            }
                        }

                        // Explicit sync function called by model change signals
                        function syncIndex() {
                            var curr = delegateItem.mCurrentValue;
                            var edit = delegateItem.mEditedValue;
                            var tVal = Number(edit !== -1 ? edit : curr);
                            
                            for (var i = 0; i < rcOptionsModel.count; i++) {
                                if (Number(rcOptionsModel.get(i).value) === tVal) {
                                    currentIndex = i;
                                    return;
                                }
                            }
                            currentIndex = 0;
                        }

                        Component.onCompleted: syncIndex()

                        onActivated: {
                            // "index" here is the ComboBox's activated index from the signal argument!
                            var newVal = rcOptionsModel.get(index).value
                            if (newVal !== delegateItem.mCurrentValue) {
                                userParamsModel.setProperty(delegateItem.rowIdx, "editedValue", newVal)
                                console.log("✏️ Set", delegateItem.pName, "to", newVal)
                            } else {
                                userParamsModel.setProperty(delegateItem.rowIdx, "editedValue", -1)
                            }
                        }
                    }
                }
            }
            
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 12
                contentItem: Rectangle { color: "#555"; radius: 6 }
            }
        }
    }
}

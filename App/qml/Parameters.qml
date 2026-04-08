import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs 1.3

ApplicationWindow {
    id: root  // ✅ ADD ID TO ROOT!
    
    visible: true
    width: 1400
    height: 800
    title: "Drone Parameters - Full List"
    color: "#1a1a1a"

    property color gridColor: "#3a3a3a"
    property color headerBg: "#252525"
    property color accentColor: "#9acd32"
    property color rowHoverColor: "#2a2a2a"
    property string searchText: ""

    property var droneCommander: null
    property var droneModel: null
    
    // ✅ Use ListModel for proper reactivity
    ListModel {
        id: editedParamsModel
    }
    
    property int editedCount: editedParamsModel.count

    // ✅ File dialogs
    FileDialog {
        id: loadFileDialog
        title: "Load Parameters from File"
        folder: shortcuts.home
        nameFilters: ["JSON Files (*.json)", "All Files (*)"]
        selectExisting: true
        onAccepted: {
            console.log("📂 Loading from:", loadFileDialog.fileUrl)
            statusLabel.text = "📂 Loading parameters from file..."
            
            if (droneCommander) {
                var success = droneCommander.loadParametersFromFile()
                if (success) {
                    statusLabel.text = "✅ Parameters loaded from file"
                } else {
                    statusLabel.text = "❌ Failed to load parameters from file"
                }
            }
        }
        onRejected: {
            statusLabel.text = "⚠️ Load cancelled"
        }
    }

    FileDialog {
        id: saveFileDialog
        title: "Save Parameters to File"
        folder: shortcuts.home
        nameFilters: ["JSON Files (*.json)", "All Files (*)"]
        selectExisting: false
        defaultSuffix: "json"
        onAccepted: {
            console.log("💾 Saving to:", saveFileDialog.fileUrl)
            
            if (!droneCommander) {
                statusLabel.text = "❌ DroneCommander not connected"
                return
            }
            
            var params = droneCommander.parameters
            if (!params || Object.keys(params).length === 0) {
                statusLabel.text = "❌ No parameters to save"
                return
            }
            
            var paramDict = {}
            for (var paramName in params) {
                paramDict[paramName] = parseFloat(params[paramName].value)
            }
            
            var paramsJson = JSON.stringify(paramDict)
            var urlStr = saveFileDialog.fileUrl.toString()
            var filename = urlStr.substring(urlStr.lastIndexOf('/') + 1)
            if (!filename.endsWith('.json')) {
                filename += '.json'
            }
            
            statusLabel.text = "💾 Saving " + Object.keys(paramDict).length + " parameters..."
            var success = droneCommander.saveParametersToFile(paramsJson, filename)
            
            if (success) {
                statusLabel.text = "✅ Saved " + Object.keys(paramDict).length + " parameters to " + filename
            } else {
                statusLabel.text = "❌ Failed to save parameters"
            }
        }
        onRejected: {
            statusLabel.text = "⚠️ Save cancelled"
        }
    }

    Component.onCompleted: {
        console.log("Parameter UI initialized")
        console.log("droneCommander:", droneCommander)
        console.log("droneModel:", droneModel)
        if (droneCommander) loadParametersFromBackend()
    }

    onDroneCommanderChanged: {
        if (droneCommander) loadParametersFromBackend()
    }

    Connections {
        target: droneCommander
        function onParametersUpdated() { root.onParametersUpdated() }
        function onCommandFeedback(message) { root.onCommandFeedback(message) }
        function onParameterFetchProgress(count, total) { root.onParameterFetchProgress(count, total) }
    }

    function onParameterFetchProgress(count, total) {
        if (total > 0) {
            var pct = Math.round((count / total) * 100)
            statusLabel.text = "📥 Fetching parameters... " + count + " / " + total + " (" + pct + "%)"
            if (progressContainer && progressFill) {
                progressFill.width = (count / total) * progressContainer.width
                progressFill.visible = (count < total && count > 0)
            }
        }
    }

    function onParametersUpdated() {
        console.log("📥 Parameters updated signal received")
        loadParametersFromBackend()
    }

    function onCommandFeedback(message) {
        statusLabel.text = message
    }

    function loadParametersFromBackend() {
        if (!droneCommander) {
            statusLabel.text = "❌ DroneCommander not connected"
            return
        }

        console.log("🔄 Loading parameters from DroneCommander...")
        var params = droneCommander.parameters

        if (!params) {
            statusLabel.text = "❌ No parameters returned"
            return
        }

        var keys = Object.keys(params)
        console.log("📊 Received", keys.length, "parameters")

        paramModel.clear()

        var count = 0
        for (var paramName in params) {
            var param = params[paramName]

            paramModel.append({
                command:   paramName,
                value:     param.value       || "0",
                units:     param.units       || "",
                options:   param.options     || "",
                desc:      param.desc        || "",
                paramType: param.type        || "FLOAT",
                synced:    param.synced      || false
            })
            count++
        }

        console.log("✅ Loaded", count, "parameters into model")
        statusLabel.text = "✅ Loaded " + count + " parameters"
        clearEditedParams()
    }

    function formatValue(value) {
        if (!value) return "0"
        var numValue = parseFloat(value)
        if (isNaN(numValue)) return value
        if (Math.abs(numValue - Math.round(numValue)) < 0.0001)
            return Math.round(numValue).toString()
        if (Math.abs(numValue) > 100000 || (Math.abs(numValue) < 0.001 && numValue !== 0))
            return numValue.toExponential(3)
        return numValue.toFixed(4).replace(/\.?0+$/, '')
    }

    function requestParameters() {
        if (!droneCommander) {
            statusLabel.text = "❌ DroneCommander not connected"
            return
        }
        if (!droneModel || !droneModel.isConnected) {
            statusLabel.text = "❌ Drone not connected"
            return
        }
        statusLabel.text = "📡 Requesting parameters from drone..."
        var success = droneCommander.requestAllParameters()
        if (!success)
            statusLabel.text = "❌ Failed to request parameters"
    }

    // ✅✅✅ THIS FUNCTION MUST BE CALLED!
    function markParameterEdited(paramName, newValue) {
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        console.log("✏️ markParameterEdited() called")
        console.log("   paramName:", paramName)
        console.log("   newValue:", newValue)
        console.log("   current editedCount:", editedParamsModel.count)
        
        var numValue = parseFloat(newValue)
        if (isNaN(numValue)) {
            console.log("   ❌ Invalid number:", newValue)
            return
        }
        
        // Check if parameter already exists in edited list
        var found = false
        for (var i = 0; i < editedParamsModel.count; i++) {
            if (editedParamsModel.get(i).name === paramName) {
                // Update existing entry
                editedParamsModel.setProperty(i, "value", numValue)
                found = true
                console.log("   ✓ Updated existing entry at index", i)
                break
            }
        }
        
        // Add new entry if not found
        if (!found) {
            editedParamsModel.append({
                name: paramName,
                value: numValue
            })
            console.log("   ✓ Added new entry")
        }
        
        console.log("   📝 Total edits:", editedParamsModel.count)
        statusLabel.text = "✏️ " + editedParamsModel.count + " parameter(s) modified (click Write to save)"
        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    function clearEditedParams() {
        console.log("🧹 Clearing edited parameters")
        editedParamsModel.clear()
        statusLabel.text = "✅ Parameters loaded - ready to edit"
    }

    // Helper function to check if parameter is edited
    function isParameterEdited(paramName) {
        for (var i = 0; i < editedParamsModel.count; i++) {
            if (editedParamsModel.get(i).name === paramName) {
                return true
            }
        }
        return false
    }

    // Helper function to get edited value
    function getEditedValue(paramName) {
        for (var i = 0; i < editedParamsModel.count; i++) {
            var item = editedParamsModel.get(i)
            if (item.name === paramName) {
                return item.value
            }
        }
        return null
    }

    function writeEditedParameters() {
        console.log("📝 writeEditedParameters() called")
        console.log("   editedCount:", editedParamsModel.count)
        
        writeDialog.show()
    }

    function confirmWriteParameters() {
        console.log("💾 confirmWriteParameters() called")
        
        if (!droneCommander) {
            writeDialog.errorMessage = "❌ DroneCommander not connected"
            writeDialog.errorState = true
            writeDialog.sendingState = false
            writeDialog.successState = false
            statusLabel.text = "❌ DroneCommander not connected"
            return
        }

        if (!droneModel || !droneModel.isConnected) {
            writeDialog.errorMessage = "❌ Drone not connected"
            writeDialog.errorState = true
            writeDialog.sendingState = false
            writeDialog.successState = false
            statusLabel.text = "❌ Drone not connected"
            return
        }

        if (editedParamsModel.count === 0) {
            writeDialog.errorMessage = "⚠️ No parameters have been edited"
            writeDialog.errorState = true
            writeDialog.sendingState = false
            writeDialog.successState = false
            statusLabel.text = "⚠️ No parameters have been edited"
            return
        }

        console.log("💾 Writing", editedParamsModel.count, "edited parameters to drone...")
        
        writeDialog.sendingState = true
        writeDialog.errorState = false
        writeDialog.successState = false
        writeDialog.errorMessage = ""
        statusLabel.text = "💾 Writing " + editedParamsModel.count + " parameter(s) to drone..."

        var paramsToSend = {}
        
        for (var i = 0; i < editedParamsModel.count; i++) {
            var item = editedParamsModel.get(i)
            paramsToSend[item.name] = item.value
            console.log("  ✓", item.name, "=", item.value)
        }
        
        var paramsJson = JSON.stringify(paramsToSend)
        console.log("📤 Sending JSON to backend:", paramsJson)
        console.log("📤 Parameter count:", editedParamsModel.count)

        try {
            var success = droneCommander.writeParameters(paramsJson)
            console.log("📬 writeParameters returned:", success)
            
            var checkTimer = Qt.createQmlObject('import QtQuick 2.15; Timer {}', writeDialog)
            checkTimer.interval = 100
            checkTimer.repeat = false
            checkTimer.triggered.connect(function() {
                writeDialog.sendingState = false
                
                if (success) {
                    writeDialog.successState = true
                    writeDialog.errorState = false
                    writeDialog.errorMessage = ""
                    statusLabel.text = "✅ Successfully wrote " + editedParamsModel.count + " parameter(s) to drone"
                    
                    console.log("✅ SUCCESS - Updating UI with new values")
                    
                    for (var i = 0; i < editedParamsModel.count; i++) {
                        var editedItem = editedParamsModel.get(i)
                        var paramName = editedItem.name
                        var newValue = editedItem.value
                        
                        console.log("  Updating", paramName, "in table to", newValue)
                        
                        for (var j = 0; j < paramModel.count; j++) {
                            var item = paramModel.get(j)
                            if (item.command === paramName) {
                                paramModel.setProperty(j, "value", newValue.toString())
                                console.log("    ✓ Updated row", j)
                                break
                            }
                        }
                    }
                    
                    clearEditedParams()
                    
                    var closeTimer = Qt.createQmlObject('import QtQuick 2.15; Timer {}', writeDialog)
                    closeTimer.interval = 3000
                    closeTimer.repeat = false
                    closeTimer.triggered.connect(function() {
                        writeDialog.visible = false
                        writeDialog.successState = false
                        writeDialog.errorState = false
                        closeTimer.destroy()
                    })
                    closeTimer.start()
                    
                } else {
                    console.log("❌ FAILED - Backend returned false")
                    writeDialog.errorState = true
                    writeDialog.successState = false
                    writeDialog.errorMessage = "❌ Failed to write parameters to drone (check connection)"
                    statusLabel.text = "❌ Failed to write parameters to drone"
                }
                
                checkTimer.destroy()
            })
            checkTimer.start()
            
        } catch (error) {
            console.log("❌ EXCEPTION in confirmWriteParameters:", error)
            writeDialog.sendingState = false
            writeDialog.errorState = true
            writeDialog.successState = false
            writeDialog.errorMessage = "❌ Error: " + error
            statusLabel.text = "❌ Error writing parameters: " + error
        }
    }

    function getFilteredCount() {
        if (searchText === "") return paramModel.count
        var count = 0
        for (var i = 0; i < paramModel.count; i++) {
            var item = paramModel.get(i)
            var cmd  = item.command ? item.command.toLowerCase() : ""
            var desc = item.desc    ? item.desc.toLowerCase()    : ""
            var opts = item.options ? item.options.toLowerCase() : ""
            if (cmd.includes(searchText) || desc.includes(searchText) || opts.includes(searchText))
                count++
        }
        return count
    }

    function executeReboot() {
        if (!droneCommander) {
            statusLabel.text = "❌ DroneCommander not connected"
            return
        }
        if (!droneModel || !droneModel.isConnected) {
            statusLabel.text = "❌ Drone not connected"
            return
        }
        
        statusLabel.text = "🔄 Sending reboot command..."
        var success = droneCommander.rebootAutopilot()
        
        if (success) {
            statusLabel.text = "✅ Reboot command sent. Reconnecting automatically..."
            Qt.callLater(function() {
                statusLabel.text = "⏳ Autopilot rebooting... Please wait."
            })
        } else {
            statusLabel.text = "❌ Reboot command failed"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── WRITE PARAMETERS DIALOG ────────────────────────────────────
        Rectangle {
            id: writeDialog
            visible: false
            anchors.fill: parent
            color: "#CC000000"
            z: 1001
            enabled: visible

            property bool sendingState: false
            property bool successState: false
            property bool errorState: false
            property string errorMessage: ""

            MouseArea {
                anchors.fill: parent
                enabled: parent.visible
                onClicked: {}
            }

            Rectangle {
                anchors.centerIn: parent
                width: 500
                height: Math.min(600, parent.height - 100)
                color: "#2a2a2a"
                border.color: accentColor
                border.width: 2
                radius: 8

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: writeDialog.sendingState ? "#ff9800" : accentColor

                            Text {
                                anchors.centerIn: parent
                                text: writeDialog.sendingState ? "⏳" : "✍️"
                                color: "white"
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }

                        Text {
                            text: writeDialog.errorState ? "❌ Error" :
                                  writeDialog.sendingState ? "⏳ Sending Parameters..." : 
                                  writeDialog.successState ? "✅ Parameters Written Successfully" :
                                  "Write Parameters to Drone"
                            color: writeDialog.errorState ? "#ff6b6b" : "white"
                            font.pixelSize: 18
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Button {
                            visible: !writeDialog.sendingState
                            text: "✕"
                            implicitWidth: 32
                            implicitHeight: 32
                            background: Rectangle {
                                color: parent.hovered ? "#3a3a3a" : "transparent"
                                radius: 16
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#aaa"
                                font.pixelSize: 18
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                writeDialog.visible = false
                                writeDialog.sendingState = false
                                writeDialog.successState = false
                                writeDialog.errorState = false
                                writeDialog.errorMessage = ""
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: "#3a3a3a"
                    }

                    Text {
                        text: "Changes to write: " + editedParamsModel.count + " parameter(s)"
                        color: "#ff9800"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#1a1a1a"
                        border.color: "#3a3a3a"
                        border.width: 1
                        radius: 4

                        ListView {
                            id: writeParamList
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            spacing: 4

                            model: ListModel { id: writeParamModel }

                            delegate: Rectangle {
                                width: writeParamList.width
                                height: 36
                                color: index % 2 === 0 ? "#222" : "#252525"
                                radius: 4

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    Text {
                                        text: model.status
                                        font.pixelSize: 14
                                        color: "white"
                                    }

                                    Text {
                                        text: model.paramName
                                        color: accentColor
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.preferredWidth: 200
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: "→"
                                        color: "#888"
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        text: model.newValue
                                        color: "#ff9800"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        visible: writeDialog.successState
                                        text: "✓"
                                        color: accentColor
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                width: 8
                                contentItem: Rectangle { 
                                    color: "#555"
                                    radius: 4
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        color: writeDialog.successState ? "#2a3a2a" : 
                               writeDialog.sendingState ? "#3a3a1a" : "#3a2a1a"
                        border.color: writeDialog.successState ? accentColor :
                                     writeDialog.sendingState ? "#ff9800" : "#ff6b6b"
                        border.width: 1
                        radius: 4
                        visible: writeDialog.sendingState || writeDialog.successState

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: writeDialog.successState ? "✅" :
                                      writeDialog.sendingState ? "⏳" : "⚠️"
                                font.pixelSize: 14
                            }

                            Text {
                                text: writeDialog.successState ? "All parameters written successfully" :
                                      writeDialog.sendingState ? "Sending to autopilot..." :
                                      "Ready to send"
                                color: writeDialog.successState ? accentColor : "#ff9800"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Item { Layout.fillWidth: true }

                        Button {
                            visible: !writeDialog.sendingState && !writeDialog.successState
                            text: "Cancel"
                            implicitWidth: 110
                            implicitHeight: 38
                            background: Rectangle {
                                color: parent.pressed ? "#3a3a3a" : (parent.hovered ? "#353535" : "#2a2a2a")
                                border.color: "#4a4a4a"
                                border.width: 2
                                radius: 6
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#cccccc"
                                font.pixelSize: 13
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                writeDialog.visible = false
                                writeDialog.sendingState = false
                                writeDialog.successState = false
                            }
                        }

                        Button {
                            visible: writeDialog.successState
                            text: "Close"
                            implicitWidth: 110
                            implicitHeight: 38
                            background: Rectangle {
                                color: parent.pressed ? "#3a5a3a" : (parent.hovered ? "#2f4f2f" : accentColor)
                                border.color: "#acd552"
                                border.width: 2
                                radius: 6
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "white"
                                font.pixelSize: 13
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                writeDialog.visible = false
                                writeDialog.successState = false
                            }
                        }

                        Button {
                            visible: !writeDialog.sendingState && !writeDialog.successState
                            implicitWidth: 130
                            implicitHeight: 38
                            background: Rectangle {
                                color: parent.pressed ? "#3a5a3a" : (parent.hovered ? "#4a6a4a" : accentColor)
                                border.color: "#acd552"
                                border.width: 2
                                radius: 6
                            }
                            contentItem: RowLayout {
                                spacing: 6
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "✍️"
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: "Write Now"
                                    color: "white"
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                            }
                            onClicked: {
                                console.log("✍️ Write Now clicked in dialog")
                                root.confirmWriteParameters()  // ✅ Use root. prefix
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }

            function show() {
                console.log("📋 Showing write dialog")
                console.log("   editedCount:", editedParamsModel.count)
                
                writeParamModel.clear()
                
                for (var i = 0; i < editedParamsModel.count; i++) {
                    var item = editedParamsModel.get(i)
                    writeParamModel.append({
                        status: "📝",
                        paramName: item.name,
                        newValue: root.formatValue(item.value.toString())  // ✅ Use root. prefix
                    })
                    console.log("   -", item.name, "=", item.value)
                }
                
                console.log("   Added", editedParamsModel.count, "items to dialog model")
                
                sendingState = false
                successState = false
                visible = true
            }
        }

        // ── TOP TOOLBAR ───────────────────────────────────────────────────
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
                    text: "Parameter Configuration"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                Rectangle {
                    width: 140; height: 36
                    color: "#2a2a2a"
                    border.color: accentColor
                    border.width: 2
                    radius: 4
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: searchText === "" ? "Total:" : "Filtered:"
                            color: "#aaa"; font.pixelSize: 11
                        }
                        Text {
                            text: searchText === "" ? paramModel.count
                                                    : root.getFilteredCount() + "/" + paramModel.count
                            color: accentColor; font.pixelSize: 16; font.bold: true
                        }
                    }
                }

                Rectangle {
                    width: 140; height: 36
                    color: editedCount > 0 ? "#3a2a1a" : "#2a2a2a"
                    border.color: editedCount > 0 ? "#ff9800" : gridColor
                    border.width: 2
                    radius: 4
                    visible: editedCount > 0
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "✏️ Edited:"
                            color: "#ff9800"
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            text: editedCount
                            color: "#ff9800"
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 250; height: 36
                    color: "#2a2a2a"
                    border.color: searchInput.activeFocus ? accentColor : gridColor
                    border.width: 2
                    radius: 4
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Text { text: "🔍"; color: "#888"; font.pixelSize: 14 }
                        TextField {
                            id: searchInput
                            Layout.fillWidth: true
                            placeholderText: "Search parameters..."
                            color: "white"
                            font.pixelSize: 12
                            background: Rectangle { color: "transparent" }
                            selectByMouse: true
                            onTextChanged: searchText = text.toLowerCase()
                            Keys.onEscapePressed: { text = ""; focus = false }
                        }
                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: clearArea.containsMouse ? "#444" : "transparent"
                            visible: searchInput.text.length > 0
                            Text {
                                anchors.centerIn: parent
                                text: "×"; color: "#aaa"
                                font.pixelSize: 16; font.bold: true
                            }
                            MouseArea {
                                id: clearArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: searchInput.text = ""
                            }
                        }
                    }
                }

                Button {
                    text: "📂 Load"
                    font.pixelSize: 12
                    implicitWidth: 90
                    implicitHeight: 36
                    hoverEnabled: true
                    background: Rectangle {
                        color: parent.pressed ? "#3a3a3a" : (parent.hovered ? "#2f2f2f" : "#2a2a2a")
                        border.color: accentColor
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                    }
                    onClicked: loadFileDialog.open()
                }

                Button {
                    text: "💾 Save"
                    font.pixelSize: 12
                    implicitWidth: 90
                    implicitHeight: 36
                    enabled: paramModel.count > 0
                    opacity: paramModel.count > 0 ? 1.0 : 0.5
                    hoverEnabled: true
                    background: Rectangle {
                        color: parent.pressed ? "#3a3a3a" : (parent.hovered ? "#2f2f2f" : "#2a2a2a")
                        border.color: accentColor
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: paramModel.count > 0 ? "white" : "#888"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                    }
                    onClicked: {
                        if (paramModel.count === 0) {
                            statusLabel.text = "⚠️ No parameters to save"
                            return
                        }
                        saveFileDialog.open()
                    }
                }

                Button {
                    text: "✍️ Write"
                    font.pixelSize: 12
                    implicitWidth: 90
                    implicitHeight: 36
                    
                    enabled: true
                    opacity: editedCount > 0 ? 1.0 : 0.6
                    hoverEnabled: true
                    
                    background: Rectangle {
                        color: parent.pressed ? "#3a5a3a" : (parent.hovered ? "#2f2f2f" : "#2a2a2a")
                        border.color: editedCount > 0 ? accentColor : gridColor
                        border.width: 2
                        radius: 4
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: editedCount > 0 ? "white" : "#999"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                        font.bold: true
                    }
                    
                    onClicked: {
                        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        console.log("✍️ WRITE BUTTON CLICKED")
                        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        console.log("editedCount:", editedParamsModel.count)
                        console.log("droneCommander:", droneCommander ? "EXISTS" : "NULL")
                        console.log("droneModel:", droneModel ? "EXISTS" : "NULL")
                        
                        if (droneModel) {
                            console.log("droneModel.isConnected:", droneModel.isConnected)
                        }
                        
                        console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        
                        root.writeEditedParameters()  // ✅ Use root. prefix
                    }
                }

                Button {
                    text: "🔄 Refresh"
                    font.pixelSize: 12
                    implicitWidth: 100
                    implicitHeight: 36
                    hoverEnabled: true
                    background: Rectangle {
                        color: parent.pressed ? "#3a3a3a" : (parent.hovered ? "#2f2f2f" : "#2a2a2a")
                        border.color: accentColor
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                    }
                    onClicked: root.requestParameters()  // ✅ Use root. prefix
                }

                Button {
                    text: "🔄 Reboot"
                    font.pixelSize: 12
                    implicitWidth: 100
                    implicitHeight: 36
                    hoverEnabled: true
                    background: Rectangle {
                        color: parent.pressed ? "#4a2a2a" : (parent.hovered ? "#3f2525" : "#2a2a2a")
                        border.color: "#ff6b6b"
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "#ff6b6b"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: parent.font.pixelSize
                    }
                    onClicked: root.executeReboot()  // ✅ Use root. prefix
                }
            }
        }

        Rectangle {
            id: progressContainer
            Layout.fillWidth: true
            height: 30
            color: "#1a1a1a"
            border.color: gridColor
            border.width: 1

            Rectangle {
                id: progressFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 0
                color: "#2a4a2a"
                visible: false
                
                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }
            }

            Text {
                id: statusLabel
                anchors.centerIn: parent
                text: "Ready — click 'Refresh' to load parameters from drone"
                color: "white"
                font.pixelSize: 12
                font.bold: true
                style: Text.Outline
                styleColor: "black"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                height: 40
                color: headerBg
                border.color: gridColor
                border.width: 1
                Row {
                    anchors.fill: parent
                    spacing: 0
                    HeaderCell { width: 280; headerText: "Parameter Name" }
                    HeaderCell { width: 120; headerText: "Value" }
                    HeaderCell { width: 100; headerText: "Units" }
                    HeaderCell { width: 250; headerText: "Range / Options" }
                    HeaderCell {
                        width: parent.width - 280 - 120 - 100 - 250
                        headerText: "Description"
                    }
                }
            }

            ListView {
                id: paramTable
                model: paramModel
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                delegate: Item {
                    width: paramTable.width
                    height: {
                        if (searchText === "") return 44
                        var cmd  = model.command ? model.command.toLowerCase() : ""
                        var desc = model.desc    ? model.desc.toLowerCase()    : ""
                        var opts = model.options ? model.options.toLowerCase() : ""
                        return (cmd.includes(searchText) || desc.includes(searchText) ||
                                opts.includes(searchText)) ? 44 : 0
                    }
                    visible: height > 0
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        color: index % 2 === 0 ? "#1a1a1a" : "#1e1e1e"
                        border.color: gridColor
                        border.width: 1

                        Rectangle {
                            anchors.fill: parent
                            color: root.isParameterEdited(model.command) ? "#2a3a1a" : rowHoverColor
                            opacity: root.isParameterEdited(model.command) ? 0.3 : (rowMouse.containsMouse ? 0.5 : 0)
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        Row {
                            anchors.fill: parent
                            spacing: 0

                            TableCell { 
                                width: 280
                                cellText: model.command
                                isBold: true 
                            }

                           TableCell {
    width: 120
    cellText: {
        var editedVal = root.getEditedValue(model.command)
        if (editedVal !== null) {
            return root.formatValue(editedVal.toString())
        }
        return root.formatValue(model.value)
    }
    isEditable: true
    parameterName: model.command
    
    // ✅ THIS IS THE KEY CONNECTION!
    onTextEdited: function(newValue) {
        console.log("📞 TableCell.onTextEdited received:", parameterName, "=", newValue)
        root.markParameterEdited(parameterName, newValue)
    }
}
                            TableCell {
                                width: 100
                                cellText: (model.units && model.units !== "") ? model.units : "—"
                                textColor: "#aaa"
                            }

                            TableCell {
                                width: 250
                                cellText: (model.options && model.options !== "") ? model.options : "—"
                                fontSize: 10
                            }

                            TableCell {
                                width: parent.width - 280 - 120 - 100 - 250
                                cellText: (model.desc && model.desc !== "") ? model.desc : "No description"
                                textColor: "#bbb"
                            }
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    width: 12
                    contentItem: Rectangle { color: "#555"; radius: 6 }
                    background: Rectangle {
                        color: "#2a2a2a"
                        border.color: gridColor
                        border.width: 1
                    }
                }
            }
        }
    }

    ListModel { id: paramModel }

    component HeaderCell: Rectangle {
        property string headerText: ""
        height: parent.height
        color: "transparent"
        border.color: gridColor
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: headerText
            color: "white"
            font.pixelSize: 12
            font.bold: true
        }
    }

component TableCell: Rectangle {
    property string cellText: ""
    property bool   isBold: false
    property bool   isEditable: false
    property color  textColor: "white"
    property int    fontSize: 12
    property string parameterName: ""
    
    // ✅ Internal signal for communication
    signal textEdited(string newValue)

    height: parent.height
    color: "transparent"
    border.color: gridColor
    border.width: 1

    Loader {
        anchors.fill: parent
        sourceComponent: isEditable ? editableCell : readOnlyCell
    }

    Component {
        id: readOnlyCell
        Text {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: Text.AlignVCenter
            text: cellText
            color: textColor
            font.pixelSize: fontSize
            font.bold: isBold
            elide: Text.ElideRight
            clip: true
        }
    }

    Component {
        id: editableCell
        Rectangle {
            anchors.fill: parent
            color: ti.activeFocus ? "#2a3a2a" : "transparent"
            border.color: ti.activeFocus ? accentColor : "transparent"
            border.width: 2
            clip: true

            TextInput {
                id: ti
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                text: cellText
                color: textColor
                font.pixelSize: fontSize
                font.bold: isBold
                selectByMouse: true
                selectionColor: accentColor
                clip: true

                property string startValue: ""

                onEditingFinished: {
                    console.log("🔧 TextInput.onEditingFinished")
                    console.log("   parameterName:", parameterName)
                    console.log("   text:", text)
                    console.log("   cellText:", cellText)
                    console.log("   startValue:", startValue)
                    
                    if (text !== cellText && startValue !== text) {
                        console.log("   ✓ Emitting textEdited signal with value:", text)
                        // ✅ Emit to parent TableCell
                        parent.parent.parent.textEdited(text)
                    } else {
                        console.log("   ✗ No change, skipping signal")
                    }
                }
                
                onActiveFocusChanged: {
                    if (activeFocus) {
                        startValue = text
                        selectAll()
                        console.log("✏️ Editing:", parameterName, "- startValue:", startValue)
                    }
                }
                
                Keys.onReturnPressed: {
                    console.log("⏎ Return pressed - finishing edit")
                    focus = false
                }
                Keys.onEscapePressed: {
                    console.log("⎋ Escape pressed - cancelling edit")
                    text = cellText
                    focus = false
                }
            }
        }
    }
}
}

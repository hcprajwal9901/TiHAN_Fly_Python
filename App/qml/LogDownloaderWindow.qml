import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Window {
    id: logDownloaderWindow
    title: "Log Downloader & Library"
    width: 900
    height: 600
    color: "#2b2b2b"
    
    // Signal to request opening a log in the browser
    signal requestOpenLog(string path)
    
    // Properties to hold selected log IDs for download
    property var selectedLogs: []
    property real currentSpeed: 0.0  // KB/s
    property bool clearingLogs: false  // True while waiting for erase confirmation

    // ── Safe helper: returns logDownloader if registered, else null ──────────
    // Accessing an undeclared QML context property directly throws ReferenceError
    // and crashes.  Wrapping in a property with typeof guards prevents that.
    property var _ld: (typeof logDownloader !== "undefined") ? logDownloader : null
    property var _lm: (typeof logManager   !== "undefined") ? logManager   : null
    
    ListModel { id: logListModel }
    
    // Connect to backend signals
    Connections {
        target: _ld
        enabled: _ld !== null
        ignoreUnknownSignals: true
        
        function onLogListReceived(logList) {
            logListModel.clear()
            for (var i = 0; i < logList.length; i++) {
                logListModel.append({
                    id: logList[i].id,
                    size: logList[i].size,
                    time_utc: logList[i].time_utc,
                    num_logs: logList[i].num_logs,
                    selected: false
                })
            }
            logOutput.append("Found " + logList.length + " log files on drone.")
        }
        
        function onLogDownloadMessage(msg) {
            logOutput.append(msg)
            logOutput.cursorPosition = logOutput.length
        }
        
        function onDownloadProgress(logId, bytesDownloaded, totalBytes) {
            var percent = (bytesDownloaded / totalBytes) * 100
            downloadProgressBar.value = percent
            progressText.text = "Downloading Log #" + logId + ": " + percent.toFixed(1) + "%"
        }
        
        function onDownloadComplete(logId, filepath) {
            logOutput.append("✅ Downloaded: " + filepath)
            if (_lm) _lm.refreshLogs()
            currentSpeed = 0
        }
        
        function onDownloadSpeed(speedKbps) {
            currentSpeed = speedKbps
        }

        function onLogsCleared() {
            clearingLogs = false
            logOutput.append("✅ Drone SD card logs cleared successfully.")
            if (_ld) _ld.requestLogList()
        }
    }

    // Confirmation dialog for log erase
    // CRASH FIX: anchors.centerIn cannot be used on a Dialog directly inside a
    // Window — use x/y positioning instead.
    Dialog {
        id: clearConfirmDialog
        title: "Clear All Logs?"
        modal: true
        x: (logDownloaderWindow.width  - width)  / 2
        y: (logDownloaderWindow.height - height) / 2
        width: 360

        contentItem: Column {
            spacing: 12
            padding: 16
            Text {
                text: "This will permanently erase ALL DataFlash logs from\nthe drone's SD card. This cannot be undone."
                color: "white"
                wrapMode: Text.Wrap
                width: clearConfirmDialog.width - 32
            }
            RowLayout {
                width: parent.width - 32
                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    onClicked: clearConfirmDialog.close()
                }
                Button {
                    text: "Yes, Clear All"
                    Layout.fillWidth: true
                    onClicked: {
                        clearConfirmDialog.close()
                        clearingLogs = true
                        logOutput.append("🗑️ Sending erase command to drone...")
                        if (_ld) _ld.clearLogs()
                    }
                }
            }
        }

        background: Rectangle { color: "#2b2b2b"; radius: 6; border.color: "#555"; border.width: 1 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10
        
        // Header
        RowLayout {
            spacing: 10
            Image {
                source: "../images/drone.png"
                sourceSize.width: 24
                sourceSize.height: 24
                visible: status === Image.Ready
            }
            Text {
                text: "Log Management"
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }
            
            Item { Layout.fillWidth: true }
        }
        
        // Tabs
        TabBar {
            id: bar
            width: parent.width
            
            TabButton {
                text: "Download from Drone"
            }
            TabButton {
                text: "Local Library"
            }
        }
        
        // Content
        StackLayout {
            width: parent.width
            Layout.fillHeight: true
            currentIndex: bar.currentIndex
            
            // TAB 1: DOWNLOADER
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                RowLayout {
                    anchors.fill: parent
                    spacing: 10
                    
                    // Left: Log List
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 350
                        spacing: 5
                        
                        Text { text: "Onboard Logs:"; color: "#bdc3c7"; font.bold: true }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "white"
                            clip: true
                            
                            ListView {
                                id: logListView
                                anchors.fill: parent
                                model: logListModel
                                clip: true
                                
                                delegate: Rectangle {
                                    width: logListView.width
                                    height: 24
                                    color: model.selected ? "#3498db" : (index % 2 == 0 ? "#ffffff" : "#f0f0f0")
                                    
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 5
                                        spacing: 5
                                        
                                        CheckBox {
                                            checked: model.selected
                                            onCheckedChanged: { model.selected = checked; updateSelectedLogs() }
                                            Layout.preferredHeight: 20
                                            Layout.preferredWidth: 20
                                        }
                                        
                                        Text { text: model.id; font.pixelSize: 12; Layout.preferredWidth: 30 }
                                        Text { 
                                            text: model.time_utc > 0 ? Qt.formatDateTime(new Date(model.time_utc * 1000), "dd-MM-yyyy hh:mm") : "Unknown Date"
                                            font.pixelSize: 12
                                            Layout.fillWidth: true
                                        }
                                        Text { text: model.size; font.pixelSize: 12; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        propagateComposedEvents: true
                                        onClicked: { model.selected = !model.selected; updateSelectedLogs() }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Right: Output & Controls
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        spacing: 10
                        
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            TextArea {
                                id: logOutput
                                readOnly: true
                                background: Rectangle { color: "#1e1e1e" }
                                color: "white"
                                font.family: "Consolas"
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                        }
                        
                        // Progress
                        ColumnLayout {
                            visible: downloadProgressBar.value > 0 && downloadProgressBar.value < 100
                            RowLayout {
                                Text { 
                                    id: progressText
                                    color: "white"
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                }
                                Text {
                                    id: speedText
                                    text: currentSpeed > 0 ? "(" + currentSpeed.toFixed(1) + " KB/s)" : ""
                                    color: "#3498db"
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }
                            ProgressBar {
                                id: downloadProgressBar
                                Layout.fillWidth: true
                                from: 0; to: 100; value: 0
                            }
                        }
                        
                        // Buttons
                        GridLayout {
                            columns: 2
                            rowSpacing: 5
                            columnSpacing: 10
                            
                            Button {
                                text: "Refresh Log List"
                                Layout.fillWidth: true
                                onClicked: if (_ld) _ld.requestLogList()
                            }
                            
                            Button {
                                text: "Download Selected"
                                Layout.fillWidth: true
                                onClicked: {
                                    updateSelectedLogs()
                                    if (selectedLogs.length > 0) {
                                        if (_ld) _ld.downloadLogs(selectedLogs)
                                    } else {
                                        logOutput.append("No logs selected!")
                                    }
                                }
                            }
                             
                            Button {
                                text: "Download All"
                                Layout.fillWidth: true
                                onClicked: {
                                    var allIds = []
                                    for(var i=0; i<logListModel.count; i++) allIds.push(logListModel.get(i).id)
                                    if (_ld) _ld.downloadLogs(allIds)
                                }
                            }
                            
                            Button {
                                text: clearingLogs ? "Clearing…" : "Clear Logs"
                                Layout.fillWidth: true
                                enabled: !clearingLogs
                                onClicked: clearConfirmDialog.open()
                            }
                        }
                    }
                }
            }
            
            // TAB 2: LOCAL LIBRARY
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    
                    RowLayout {
                        Button {
                            text: "Refresh Library"
                            onClicked: if (_lm) _lm.refreshLogs()
                        }
                        Text {
                            text: "Double-click a log to open in analyzer"
                            color: "#bdc3c7"
                            font.italic: true
                        }
                    }
                    
                    // Header Row
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        color: "#34495e"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 5
                            Text { text: "Filename"; color: "white"; font.bold: true; Layout.preferredWidth: 300 }
                            Text { text: "Date"; color: "white"; font.bold: true; Layout.preferredWidth: 150 }
                            Text { text: "Duration"; color: "white"; font.bold: true; Layout.preferredWidth: 100 }
                            Text { text: "Size"; color: "white"; font.bold: true; Layout.fillWidth: true }
                        }
                    }
                    
                    // List
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#ecf0f1"
                        
                        ListView {
                            id: localLogList
                            anchors.fill: parent
                            clip: true
                            model: _lm ? _lm.logModel : null
                            
                            delegate: Rectangle {
                                width: localLogList.width
                                height: 30
                                color: index % 2 == 0 ? "#ffffff" : "#f9f9f9"
                                
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    
                                    Text { text: model.filename; Layout.preferredWidth: 300; elide: Text.ElideMiddle }
                                    Text { text: model.date; Layout.preferredWidth: 150 }
                                    Text { text: model.duration; Layout.preferredWidth: 100 }
                                    Text { text: model.size; Layout.fillWidth: true }
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onDoubleClicked: {
                                        console.log("Opening log:", model.filepath)
                                        requestOpenLog(model.filepath)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    function updateSelectedLogs() {
        var ids = []
        for(var i=0; i<logListModel.count; i++) {
            if (logListModel.get(i).selected) ids.push(logListModel.get(i).id)
        }
        selectedLogs = ids
    }
    
    // CRASH FIX: guard with typeof before accessing context properties
    Component.onCompleted: {
        logOutput.append("Ready.")
        if (_ld) _ld.requestLogList()
    }
}

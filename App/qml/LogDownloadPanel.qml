import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: logDownloadWindow
    width: 800
    height: 600
    title: "Download Logs from Flight Controller"
    visible: true
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Toolbar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "#2c3e50"
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                
                Button {
                    text: "Refresh List"
                    enabled: droneModel.isConnected
                    onClicked: logDownloader.requestLogList()
                }
                
                Button {
                    text: "Download Selected"
                    enabled: logListView.currentIndex >= 0 && !downloadInProgress
                    onClicked: {
                        if (logListView.currentItem) {
                            logDownloader.downloadLog(logListView.currentItem.logId)
                        }
                    }
                }
                
                Button {
                    text: "Cancel"
                    enabled: downloadInProgress
                    onClicked: logDownloader.cancelDownload()
                }
                
                Item { Layout.fillWidth: true }
                
                Text {
                    text: droneModel.isConnected ? "Connected" : "Not Connected"
                    color: droneModel.isConnected ? "#27ae60" : "#e74c3c"
                    font.bold: true
                }
            }
        }
        
        // Log list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#34495e"
            
            ListView {
                id: logListView
                anchors.fill: parent
                anchors.margins: 10
                spacing: 5
                clip: true
                
                model: ListModel {
                    id: logListModel
                }
                
                delegate: Rectangle {
                    width: logListView.width
                    height: 60
                    color: ListView.isCurrentItem ? "#3498db" : "#2c3e50"
                    radius: 5
                    
                    property int logId: model.id
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 15
                        
                        // Checkbox
                        CheckBox {
                            id: selectCheckbox
                            checked: ListView.isCurrentItem
                            onClicked: logListView.currentIndex = index
                        }
                        
                        // Log info
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            
                            Text {
                                text: "Log #" + model.id
                                color: "white"
                                font.bold: true
                                font.pixelSize: 14
                            }
                            
                            RowLayout {
                                spacing: 20
                                
                                Text {
                                    text: "Size: " + (model.size / 1024 / 1024).toFixed(2) + " MB"
                                    color: "#bdc3c7"
                                    font.pixelSize: 12
                                }
                                
                                Text {
                                    text: "Date: " + new Date(model.time_utc * 1000).toLocaleString()
                                    color: "#bdc3c7"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: logListView.currentIndex = index
                    }
                }
                
                Text {
                    anchors.centerIn: parent
                    text: "No logs available.\nConnect to drone and click 'Refresh List'"
                    color: "#95a5a6"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    visible: logListModel.count === 0
                }
            }
        }
        
        // Download progress
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: downloadInProgress ? 100 : 0
            color: "#2c3e50"
            visible: downloadInProgress
            
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 200 }
            }
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10
                
                Text {
                    text: "Downloading Log #" + currentDownloadId
                    color: "white"
                    font.bold: true
                }
                
                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: downloadTotalBytes
                    value: downloadedBytes
                    
                    background: Rectangle {
                        implicitHeight: 20
                        color: "#34495e"
                        radius: 3
                    }
                    
                    contentItem: Item {
                        implicitHeight: 20
                        
                        Rectangle {
                            width: parent.width * (downloadedBytes / downloadTotalBytes)
                            height: parent.height
                            radius: 3
                            color: "#27ae60"
                        }
                    }
                }
                
                Text {
                    text: (downloadedBytes / 1024 / 1024).toFixed(2) + " / " + (downloadTotalBytes / 1024 / 1024).toFixed(2) + " MB (" + 
                          ((downloadedBytes / downloadTotalBytes) * 100).toFixed(1) + "%)"
                    color: "#bdc3c7"
                }
            }
        }
    }
    
    // State
    property bool downloadInProgress: false
    property int currentDownloadId: -1
    property int downloadedBytes: 0
    property int downloadTotalBytes: 1
    
    // Connections to backend
    Connections {
        target: logDownloader
        
        function onLogListReceived(logs) {
            logListModel.clear()
            for (var i = 0; i < logs.length; i++) {
                logListModel.append(logs[i])
            }
        }
        
        function onDownloadProgress(logId, bytesDownloaded, totalBytes) {
            downloadInProgress = true
            currentDownloadId = logId
            downloadedBytes = bytesDownloaded
            downloadTotalBytes = totalBytes
        }
        
        function onDownloadComplete(logId, filepath) {
            downloadInProgress = false
            console.log("Download complete: " + filepath)
            
            // Show success message
            successDialog.text = "Log #" + logId + " downloaded successfully!\n" + filepath
            successDialog.open()
        }
        
        function onDownloadError(error) {
            downloadInProgress = false
            errorDialog.text = "Download failed: " + error
            errorDialog.open()
        }
    }
    
    // Success dialog
    Dialog {
        id: successDialog
        title: "Download Complete"
        property alias text: successText.text
        standardButtons: Dialog.Ok
        
        Text {
            id: successText
            color: "#27ae60"
        }
    }
    
    // Error dialog
    Dialog {
        id: errorDialog
        title: "Download Error"
        property alias text: errorText.text
        standardButtons: Dialog.Ok
        
        Text {
            id: errorText
            color: "#e74c3c"
        }
    }
}

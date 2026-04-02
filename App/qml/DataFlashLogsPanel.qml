import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs 1.3 as OldDialogs
import Qt.labs.platform 1.1

Rectangle {
    id: dataFlashLogsPanel

    height: 280
    width: parent ? parent.width : 300

    color: "#ffffff"
    radius: 8
    border.color: "#cccccc"
    border.width: 1

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#f5f5f5" }
        GradientStop { position: 0.5; color: "#e0e0e0" }
        GradientStop { position: 1.0; color: "#d5d5d5" }
    }

    // ── Window references ────────────────────────────────────────────────────
    // Bind to the global instances pre-loaded in Main.qml to prevent 
    // memory corruption & PyQt garbage collection crashes during Loader lifecycles.
    property var logDownloaderWindow:    mainWindow ? mainWindow.globalLogDownloaderWindow : null
    property var logBrowserWindow:       mainWindow ? mainWindow.globalLogBrowserWindow : null


    // ── Deferred open after FileDialog closes ────────────────────────────────
    Timer {
        id: deferredOpenTimer
        interval: 150
        repeat:   false
        property string pendingPath: ""
        onTriggered: {
            if (pendingPath !== "") {
                _openLogBrowserWithPath(pendingPath)
                pendingPath = ""
            }
        }
    }

    // ── Wait-for-downloader timer (polls until Loader completes) ─────────────
    Timer {
        id: waitForDownloaderTimer
        interval: 50; repeat: true
        onTriggered: {
            if (mainWindow && mainWindow.globalLogDownloaderWindow) {
                stop()
                mainWindow.globalLogDownloaderWindow.show()
                mainWindow.globalLogDownloaderWindow.requestActivate()
            }
        }
    }

    // ── Wait-for-browser timer (polls until Loader completes) ────────────────
    Timer {
        id: waitForBrowserTimer
        interval: 50; repeat: true
        property string pendingPath: ""
        onTriggered: {
            if (mainWindow && mainWindow.globalLogBrowserWindow) {
                stop()
                _openLogBrowserWithPath(pendingPath)
                pendingPath = ""
            }
        }
    }



    // ── Cleanup on destruction ───────────────────────────────────────────────
    Component.onDestruction: {
        // Since the window components are now globally allocated in Main.qml
        // (to survive component un-loading from tab-switches), we no longer
        // close or destroy them when this panel is destroyed.
    }

    // ════════════════════════════════════════════════════════════════════════
    // Private helpers
    // ════════════════════════════════════════════════════════════════════════

    // Shows and activates the window, optionally loading a log path.
    function _openLogBrowserWithPath(path) {
        // If window isn't loaded yet, trigger load and defer
        if (!logBrowserWindow) {
            if (mainWindow) mainWindow.ensureLogBrowser()
            waitForBrowserTimer.pendingPath = path || ""
            waitForBrowserTimer.start()
            return
        }

        try {
            logBrowserWindow.show()
            logBrowserWindow.requestActivate()

            if (path && path !== "" && path !== "__open_only__") {
                if (typeof logBrowserWindow.loadExternalLog === "function") {
                    logBrowserWindow.loadExternalLog(path)
                } else {
                    console.warn("[DataFlashLogsPanel] loadExternalLog not found on LogBrowser")
                }
            }
        } catch(e) {
            console.error("[DataFlashLogsPanel] Error showing LogBrowser:", e)
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // File dialog
    // ════════════════════════════════════════════════════════════════════════

    FileDialog {
        id: logReviewFileDialog
        title: "Select DataFlash Log to Review"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Log files (*.bin *.log *.tlog)", "All files (*)"]
        folder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)

        onAccepted: {
            var raw  = file.toString()
            // Handle both file:/// (Windows) and file:// (Unix)
            var path = raw.replace(/^file:\/{2,3}/, "")
            console.log("[DataFlashLogsPanel] Log selected:", path)
            deferredOpenTimer.pendingPath = path
            deferredOpenTimer.start()
        }

        onRejected: {
            console.log("[DataFlashLogsPanel] Log selection cancelled")
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // UI
    // ════════════════════════════════════════════════════════════════════════

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 15
        width: parent.width - 40

        Text {
            text: "DataFlash Log Operations"
            color: "#333333"
            font.bold: true
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 5
        }

        // ── Download Logs ────────────────────────────────────────────────────
        Button {
            id: downloadBtn
            Layout.preferredWidth: 220
            Layout.preferredHeight: 60
            Layout.alignment: Qt.AlignHCenter

            background: Rectangle {
                color: parent.down ? "#d0d0d0" : (parent.hovered ? "#e0e0e0" : "#f0f0f0")
                radius: 4
                border.color: "#2ecc71"
                border.width: 1
            }

            contentItem: RowLayout {
                spacing: 10
                anchors.centerIn: parent
                Text { text: "📥"; font.pixelSize: 22; color: "#333333" }
                ColumnLayout {
                    spacing: 1
                    Text { text: "Download Logs";      color: "#333333"; font.bold: true; font.pixelSize: 14 }
                    Text { text: "Get logs from drone"; color: "#666666"; font.pixelSize: 10 }
                }
            }

            onClicked: {
                if (logDownloaderWindow) {
                    logDownloaderWindow.show()
                    logDownloaderWindow.requestActivate()
                } else {
                    // Trigger lazy load then show when ready
                    if (mainWindow) mainWindow.ensureLogDownloader()
                    waitForDownloaderTimer.start()
                }
            }
        }

        // ── Review Data Logs ─────────────────────────────────────────────────
        Button {
            id: reviewBtn
            Layout.preferredWidth: 220
            Layout.preferredHeight: 60
            Layout.alignment: Qt.AlignHCenter

            background: Rectangle {
                color: parent.down ? "#d0d0d0" : (parent.hovered ? "#e0e0e0" : "#f0f0f0")
                radius: 4
                border.color: "#3daee9"
                border.width: 1
            }

            contentItem: RowLayout {
                spacing: 10
                anchors.centerIn: parent
                Text { text: "📈"; font.pixelSize: 22; color: "#333333" }
                ColumnLayout {
                    spacing: 1
                    Text { text: "Review Data Logs";    color: "#333333"; font.bold: true; font.pixelSize: 14 }
                    Text { text: "Select file to analyze"; color: "#666666"; font.pixelSize: 10 }
                }
            }

            onClicked: {
                // Always open the FileDialog — _openLogBrowserWithPath is
                // called later via deferredOpenTimer, safely after dialog closes.
                logReviewFileDialog.open()
            }
        }
    }
}

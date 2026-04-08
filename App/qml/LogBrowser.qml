import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCharts 2.15
import QtQuick.Window 2.15

Window {
    id: logBrowserWindow
    width: 1400
    height: 800
    title: "Log Browser"

    // ── Shared cursor state ──────────────────────────────────────────────
    property double cursorTime: -1
    property bool isCursorActive: false
    property bool isLoading: false
    property string loadStatus: ""

    // ── Zoom/Pan state ───────────────────────────────────────────────────
    property double dataMinX: 0
    property double dataMaxX: 1
    property double dataMinY: 0
    property double dataMaxY: 1
    property double originalMinX: 0
    property double originalMaxX: 1
    property double originalMinY: 0
    property double originalMaxY: 1
    property double zoomLevel: 1.0
    property bool isDragging: false

    // ── Hover state ──────────────────────────────────────────────────────
    property var hoverData: ({})
    property bool hoverThrottleActive: false
    property double queuedHoverX: 0

    // ── Window-caching with global scale ─────────────────────────────────
    property double lastMinX: 0
    property double lastMaxX: 0
    property double globalCacheThreshold: 0

    // ── Y-axis hysteresis ────────────────────────────────────────────────
    property double lastYMin: 0
    property double lastYMax: 0
    property double yAxisHysteresis: 0.05   // 5 % change required

    // ── Window rebuild throttle ───────────────────────────────────────────
    property bool windowRebuildPending: false

    // ── Guard: accept graphDataReady only when not clearing ──────────────
    property bool acceptingGraphData: true

    // ── Manually tracked series count ─────────────────────────────────────
    // ChartView.count has NO NOTIFY signal, so using it in bindings causes
    // QML to re-evaluate every binding that references it on EVERY frame,
    // flooding the log with "depends on non-NOTIFYable properties" warnings
    // and hammering the Python backend hundreds of times per second.
    // We track this ourselves and update it explicitly on every series change.
    property int seriesCount: 0

    // ── Checkbox reset counter ────────────────────────────────────────────
    // Incremented by "Clear Graphs". Every field checkbox watches this via
    // a Connections block and resets itself. ListView virtualizes delegates
    // so we can't iterate them directly – the counter pattern is the correct
    // QML idiom for broadcasting a one-shot event into delegate items.
    property int clearVersion: 0

    // ────────────────────────────────────────────────────────────────────
    // Timers
    // ────────────────────────────────────────────────────────────────────

    // Hover throttle – 60 fps max
    Timer {
        id: hoverThrottleTimer
        interval: 16
        repeat: false
        onTriggered: {
            hoverThrottleActive = false
            if (seriesCount > 0)
                processHover(queuedHoverX)
        }
    }

    // Window rebuild throttle – debounce pan/zoom updates
    Timer {
        id: windowRebuildTimer
        interval: 20
        repeat: false
        onTriggered: {
            performWindowRebuild()
            windowRebuildPending = false
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // Helper functions
    // ────────────────────────────────────────────────────────────────────

    function processHover(mouseX) {
        if (seriesCount === 0) return
        var p   = Qt.point(mouseX, 0)
        var val = leftChart.mapToValue(p, leftChart.series(0))
        hoverData      = logBrowser.getNearestForAllSeries(val.x)
        cursorTime     = val.x
        isCursorActive = true
    }

    function updateVisibleWindow() {
        if (!windowRebuildPending) {
            windowRebuildPending = true
            windowRebuildTimer.start()
        }
    }

    function performWindowRebuild() {
        if (seriesCount === 0) return   // nothing to rebuild

        var deltaMin = Math.abs(leftAxisX.min - lastMinX)
        var deltaMax = Math.abs(leftAxisX.max - lastMaxX)
        if (deltaMin < globalCacheThreshold && deltaMax < globalCacheThreshold)
            return

        lastMinX = leftAxisX.min
        lastMaxX = leftAxisX.max

        var globalMinY = Number.MAX_VALUE
        var globalMaxY = -Number.MAX_VALUE

        var plotWidth = Math.floor(leftChart.plotArea.width)
        if (plotWidth < 100) plotWidth = 1000

        for (var i = 0; i < leftChart.count; i++) {
            var series     = leftChart.series(i)
            var windowData = logBrowser.getVisibleWindow(
                series.name,
                leftAxisX.min,
                leftAxisX.max,
                plotWidth
            )

            series.clear()
            var ts = windowData.timestamps
            var vs = windowData.values
            for (var j = 0; j < ts.length; j++)
                series.append(ts[j], vs[j])

            if (windowData.minY < globalMinY) globalMinY = windowData.minY
            if (windowData.maxY > globalMaxY) globalMaxY = windowData.maxY
        }

        if (globalMinY !== Number.MAX_VALUE) {
            var paddingY = (globalMaxY - globalMinY) * 0.1
            if (paddingY === 0) paddingY = 1.0
            var newMinY  = globalMinY - paddingY
            var newMaxY  = globalMaxY + paddingY
            var yRange   = lastYMax - lastYMin
            var changed  = yRange <= 0
            if (!changed) {
                var thresh = yRange * yAxisHysteresis
                changed = (Math.abs(newMinY - lastYMin) > thresh ||
                           Math.abs(newMaxY - lastYMax) > thresh)
            }
            if (changed) {
                leftAxisY.min = newMinY
                leftAxisY.max = newMaxY
                lastYMin = newMinY
                lastYMax = newMaxY
            }
        }
    }

    function loadExternalLog(path) {
        if (logBrowser) {
            console.log("Loading external log:", path)
            logBrowser.loadLog(path)
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // UI
    // ────────────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Toolbar ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "#2c3e50"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Button {
                    text: "Load Log"
                    enabled: !isLoading
                    onClicked: {
                        if (logBrowser) logBrowser.openFileDialogForReview()
                    }
                }

                Button {
                    text: "Clear Graphs"
                    enabled: !isLoading
                    onClicked: {
                        // ── CRASH FIX: disable cursor FIRST, THEN clear ──
                        // 1. Kill cursor so crosshair bindings stop firing
                        isCursorActive  = false
                        cursorTime      = -1
                        hoverData       = ({})

                        // 2. Stop timers – prevent pending rebuild running
                        //    on a half-cleared chart
                        hoverThrottleTimer.stop()
                        windowRebuildTimer.stop()
                        windowRebuildPending = false
                        hoverThrottleActive  = false

                        // 3. Block stale graphDataReady signals
                        acceptingGraphData = false

                        // 4. Tell backend to disconnect workers & wipe data
                        if (logBrowser) logBrowser.clearGraphs()

                        // 5. Remove all QML series
                        leftChart.removeAllSeries()

                        // 6. Update our manually-tracked count IMMEDIATELY
                        //    so no binding reads stale leftChart.count
                        seriesCount = 0

                        // 6b. Signal all visible delegate checkboxes to uncheck
                        //     (Connections inside each delegate responds to this)
                        clearVersion++

                        // 7. Reset axis ranges
                        leftAxisX.min = 0; leftAxisX.max = 10
                        leftAxisY.min = 0; leftAxisY.max = 10

                        // 8. Reset all tracking state
                        lastYMin = 0; lastYMax = 0
                        lastMinX = 0; lastMaxX = 0
                        dataMinX = 0; dataMaxX = 10
                        dataMinY = 0; dataMaxY = 10
                        originalMinX = 0; originalMaxX = 10
                        originalMinY = 0; originalMaxY = 10
                        zoomLevel = 1.0
                        globalCacheThreshold = 0

                        // 9. Re-enable after event loop flushes queued signals
                        graphDataGuardTimer.start()
                    }
                }

                // Guard timer – re-enables graphDataReady and checkbox interaction
                // after the Qt event loop has flushed all queued signals AND all
                // delegate Connections have responded to clearVersion change.
                Timer {
                    id: graphDataGuardTimer
                    interval: 300
                    repeat: false
                    onTriggered: acceptingGraphData = true
                }

                CheckBox {
                    id: smoothDataCheckbox
                    text: "Smooth Data"
                    checked: false
                    contentItem: Text {
                        text: smoothDataCheckbox.text
                        color: "white"
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: smoothDataCheckbox.indicator.width + smoothDataCheckbox.spacing
                    }
                }

                Item { Layout.fillWidth: true }

                BusyIndicator {
                    running: isLoading
                    visible: isLoading
                    width: 24; height: 24
                }
                Text {
                    visible: isLoading
                    text: loadStatus
                    color: "#f39c12"
                    font.pixelSize: 12
                }

                Text {
                    visible: !isLoading
                    text: (logBrowser && logBrowser.logFilepath)
                          ? "Loaded: " + logBrowser.logFilepath.split('/').pop()
                          : "No log loaded"
                    color: "white"
                }
            }
        }

        // ── Main content ─────────────────────────────────────────────────
        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            // ── Left panel – Message Tree ─────────────────────────────────
            Rectangle {
                SplitView.preferredWidth: 300
                SplitView.minimumWidth: 250
                color: "#2c3e50"

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 5
                    clip: true

                    ListView {
                        id: messageTree
                        width: parent.width
                        spacing: 2

                        model: logBrowser ? logBrowser.messageTypes : []

                        delegate: Column {
                            id: msgDelegate
                            width: ListView.view ? ListView.view.width : 300

                            property string messageType: modelData
                            property bool isExpanded: false

                            Rectangle {
                                width: parent.width
                                height: 30
                                color: msgDelegate.isExpanded ? "#34495e" : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    spacing: 10

                                    Text {
                                        text: msgDelegate.isExpanded ? "▼" : "▶"
                                        color: "#bdc3c7"
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        text: msgDelegate.messageType
                                        color: "white"
                                        font.bold: true
                                        font.pixelSize: 14
                                        Layout.fillWidth: true
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: msgDelegate.isExpanded = !msgDelegate.isExpanded
                                }
                            }

                            Column {
                                width: parent.width
                                visible: msgDelegate.isExpanded

                                Repeater {
                                    model: (msgDelegate.isExpanded && logBrowser)
                                           ? logBrowser.getAvailableChannels(msgDelegate.messageType)
                                           : null

                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 24
                                        color: "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 25

                                            CheckBox {
                                                id: fieldCheckbox
                                                text: modelData
                                                checked: false

                                                // ── Reset when Clear Graphs fires ──────────
                                                // clearVersion is incremented by the toolbar
                                                // button. Setting checked=false here triggers
                                                // onCheckedChanged, but acceptingGraphData is
                                                // already false so no backend call is made,
                                                // and removeAllSeries() was already called so
                                                // the series lookup returns null (harmless).
                                                Connections {
                                                    target: logBrowserWindow
                                                    function onClearVersionChanged() {
                                                        fieldCheckbox.checked = false
                                                    }
                                                }

                                                contentItem: Text {
                                                    text: fieldCheckbox.text
                                                    color: "#ecf0f1"
                                                    font.pixelSize: 12
                                                    verticalAlignment: Text.AlignVCenter
                                                    leftPadding: fieldCheckbox.indicator.width + fieldCheckbox.spacing
                                                }

                                                indicator: Rectangle {
                                                    implicitWidth: 14
                                                    implicitHeight: 14
                                                    x: fieldCheckbox.leftPadding
                                                    y: parent.height / 2 - height / 2
                                                    radius: 2
                                                    border.color: fieldCheckbox.down ? "#2ecc71" : "#bdc3c7"

                                                    Rectangle {
                                                        width: 8; height: 8
                                                        x: 3; y: 3
                                                        radius: 1
                                                        color: "#2ecc71"
                                                        visible: fieldCheckbox.checked
                                                    }
                                                }

                                                onCheckedChanged: {
                                                    if (checked) {
                                                        // Only request data when user is actively
                                                        // enabling a series (not during a clear reset)
                                                        if (!acceptingGraphData) return
                                                        lastYMin = 0
                                                        lastYMax = 0
                                                        logBrowser.requestGraphData(
                                                            msgDelegate.messageType,
                                                            modelData, 0,
                                                            smoothDataCheckbox.checked)
                                                    } else {
                                                        // If we're clearing, series are already gone
                                                        if (!acceptingGraphData) return
                                                        var seriesName = msgDelegate.messageType + "." + modelData
                                                        var s = leftChart.series(seriesName)
                                                        if (s) {
                                                            leftChart.removeSeries(s)
                                                            seriesCount = Math.max(0, seriesCount - 1)
                                                            lastYMin = 0
                                                            lastYMax = 0
                                                            if (seriesCount > 0)
                                                                updateVisibleWindow()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Right panel – Graph ───────────────────────────────────────
            ColumnLayout {
                SplitView.fillWidth: true
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#1a1a1a"

                    ChartView {
                        id: leftChart
                        anchors.fill: parent
                        antialiasing: false
                        animationOptions: ChartView.NoAnimation
                        backgroundColor: "#1e1e1e"
                        legend.visible: true
                        legend.alignment: Qt.AlignTop
                        legend.labelColor: "#dddddd"

                        ValueAxis {
                            id: leftAxisX
                            titleText: "Time (s)"
                            labelsColor: "#cccccc"
                            gridLineColor: "#404040"
                            labelsFont.pixelSize: 11
                        }
                        ValueAxis {
                            id: leftAxisY
                            titleText: "Value"
                            labelsColor: "#cccccc"
                            gridLineColor: "#404040"
                            labelsFont.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton

                            property point  panStart: Qt.point(0, 0)
                            property double panStartAxisMinX: 0
                            property double panStartAxisMaxX: 0

                            onPressed: {
                                panStart         = Qt.point(mouse.x, mouse.y)
                                panStartAxisMinX = leftAxisX.min
                                panStartAxisMaxX = leftAxisX.max
                                isDragging       = true
                            }

                            onReleased: {
                                isDragging = false
                                updateVisibleWindow()
                            }

                            onPositionChanged: {
                                if (pressed && isDragging) {
                                    if (seriesCount === 0) return

                                    var curPos   = leftChart.mapToValue(Qt.point(mouse.x, mouse.y), leftChart.series(0))
                                    var startPos = leftChart.mapToValue(panStart, leftChart.series(0))
                                    var deltaX   = startPos.x - curPos.x

                                    var newMinX = panStartAxisMinX + deltaX
                                    var newMaxX = panStartAxisMaxX + deltaX
                                    var range   = newMaxX - newMinX

                                    if (newMinX < dataMinX) { newMinX = dataMinX; newMaxX = dataMinX + range }
                                    if (newMaxX > dataMaxX) { newMaxX = dataMaxX; newMinX = dataMaxX - range }

                                    leftAxisX.min = newMinX
                                    leftAxisX.max = newMaxX
                                } else {
                                    // Hover
                                    if (!hoverThrottleActive && seriesCount > 0) {
                                        hoverThrottleActive = true
                                        queuedHoverX        = mouse.x
                                        hoverThrottleTimer.start()
                                    } else {
                                        queuedHoverX = mouse.x
                                    }
                                }
                            }

                            onWheel: {
                                if (seriesCount === 0) return

                                var zoomFactor = wheel.angleDelta.y > 0 ? 0.9 : 1.1
                                var p          = Qt.point(wheel.x, wheel.y)
                                var cursorVal  = leftChart.mapToValue(p, leftChart.series(0))
                                var rangeX     = leftAxisX.max - leftAxisX.min
                                var newRangeX  = rangeX * zoomFactor
                                var ratio      = (cursorVal.x - leftAxisX.min) / rangeX

                                var newMinX    = cursorVal.x - newRangeX * ratio
                                var newMaxX    = cursorVal.x + newRangeX * (1 - ratio)

                                if (newMinX < dataMinX) newMinX = dataMinX
                                if (newMaxX > dataMaxX) newMaxX = dataMaxX

                                var clampedRange = newMaxX - newMinX
                                var minRange     = (dataMaxX - dataMinX) * 0.01
                                if (clampedRange < minRange) return

                                leftAxisX.min = newMinX
                                leftAxisX.max = newMaxX
                                zoomLevel     = (originalMaxX - originalMinX) / clampedRange

                                updateVisibleWindow()
                            }

                            onDoubleClicked: {
                                leftAxisX.min = originalMinX
                                leftAxisX.max = originalMaxX
                                leftAxisY.min = originalMinY
                                leftAxisY.max = originalMaxY
                                zoomLevel     = 1.0
                                updateVisibleWindow()
                            }
                        }

                        // ── Crosshair – vertical line ─────────────────────
                        // Guard: only render when seriesCount > 0 to avoid
                        // series(0) null-ptr crash and binding storm from
                        // non-NOTIFYable leftChart.count
                        Rectangle {
                            visible: isCursorActive && seriesCount > 0
                            x: {
                                if (!isCursorActive || seriesCount === 0) return 0
                                return leftChart.mapToPosition(
                                    Qt.point(cursorTime, 0), leftChart.series(0)).x
                            }
                            y:      leftChart.plotArea.y
                            width:  1
                            height: leftChart.plotArea.height
                            color:  "#888888"
                        }

                        // ── Crosshair – horizontal line (first series) ────
                        Rectangle {
                            visible: {
                                if (!isCursorActive || seriesCount === 0) return false
                                var sName = leftChart.series(0).name
                                return hoverData[sName] !== undefined
                            }
                            x: leftChart.plotArea.x
                            y: {
                                if (!isCursorActive || seriesCount === 0) return 0
                                var sName = leftChart.series(0).name
                                var d     = hoverData[sName]
                                if (!d) return 0
                                return leftChart.mapToPosition(
                                    Qt.point(0, d.value), leftChart.series(0)).y
                            }
                            width:  leftChart.plotArea.width
                            height: 1
                            color:  "#888888"
                        }

                        // ── Tooltip box ───────────────────────────────────
                        Rectangle {
                            visible: isCursorActive && Object.keys(hoverData).length > 0
                            x: 10; y: 10
                            width:  tooltipColumn.width + 20
                            height: tooltipColumn.height + 16
                            color:  "#dd000000"
                            radius: 6

                            Column {
                                id: tooltipColumn
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "Time: " + cursorTime.toFixed(4) + " s"
                                    color: "#f1c40f"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Repeater {
                                    model: Math.max(0, seriesCount)
                                    delegate: Row {
                                        spacing: 8
                                        Rectangle {
                                            width: 8; height: 8
                                            radius: 4
                                            color: leftChart.series(index).color
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: {
                                                var s  = leftChart.series(index)
                                                var d  = hoverData[s.name]
                                                return d ? s.name + ": " + d.value.toFixed(4)
                                                         : s.name + ": --"
                                            }
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Flight summary bar ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#34495e"

            GridLayout {
                anchors.fill: parent
                anchors.margins: 10
                columns: 4

                Text { text: "Duration:";     color: "white" }
                Text {
                    text: (logBrowser && logBrowser.flightSummary && logBrowser.flightSummary.duration)
                          ? logBrowser.flightSummary.duration.toFixed(1) + "s" : "N/A"
                    color: "#3498db"
                }

                Text { text: "Max Altitude:"; color: "white" }
                Text {
                    text: (logBrowser && logBrowser.flightSummary && logBrowser.flightSummary.max_altitude)
                          ? logBrowser.flightSummary.max_altitude.toFixed(1) + "m" : "N/A"
                    color: "#3498db"
                }

                Text { text: "Max Speed:";    color: "white" }
                Text {
                    text: (logBrowser && logBrowser.flightSummary && logBrowser.flightSummary.max_speed)
                          ? logBrowser.flightSummary.max_speed.toFixed(1) + "m/s" : "N/A"
                    color: "#3498db"
                }

                Text { text: "Start Time:";   color: "white" }
                Text {
                    text: (logBrowser && logBrowser.flightSummary && logBrowser.flightSummary.start_time)
                          ? new Date(logBrowser.flightSummary.start_time * 1000).toLocaleString()
                          : "N/A"
                    color: "#3498db"
                }
            }
        }
    }



    // ────────────────────────────────────────────────────────────────────
    // Graph data handler
    // ────────────────────────────────────────────────────────────────────

    Connections {
        target: logBrowser

        function onLogCleared() {
            // Backend has reset _current_log → messageTypes now returns [].
            // Force the ListView to re-evaluate its model BEFORE the new parse
            // result arrives so Qt never sees a negative model-size delta.
            messageTree.model = []
        }

        function onLoadProgress(msg) {
            if (msg === "") {
                isLoading  = false
                loadStatus = ""
            } else {
                isLoading  = true
                loadStatus = msg
            }
        }

        function onLogLoaded() {
            // Parse finished — restore the live binding so the tree populates.
            messageTree.model = logBrowser ? logBrowser.messageTypes : []
        }

        function onFileDialogResult(path) {
            // Path chosen from openFileDialogForReview() Python slot.
            // Load it directly — no deferral needed inside the LogBrowser window.
            logBrowser.loadLog(path)
        }

        function onGraphDataReady(channelName, timestamps, values, axisId) {
            // Drop stale signals arriving during/after a clear
            if (!acceptingGraphData) return
            if (!timestamps || timestamps.length === 0) return

            // Remove old series with same name
            var existing = leftChart.series(channelName)
            if (existing) {
                leftChart.removeSeries(existing)
                seriesCount = Math.max(0, seriesCount - 1)
            }

            var series = leftChart.createSeries(
                ChartView.SeriesTypeLine, channelName, leftAxisX, leftAxisY)
            series.width = 2
            // Enable GPU rendering BEFORE appending any data.
            // Setting useOpenGL after append() triggers an internal QtCharts
            // renderer reset that frequently segfaults, especially on Windows.
            series.useOpenGL = true
            seriesCount = seriesCount + 1  // track manually – ChartView.count has no NOTIFY

            // ── Append loop ──────────────────────────────────────────────
            // series.replace(array) does NOT exist in the QML API (C++ only)
            // and crashes. series.append(x, y) is the correct QML method.
            // The backend now sends ≤500 pts so this loop is 3× faster than
            // the previous 1500-point version.
            var newMinX = timestamps[0]
            var newMaxX = timestamps[timestamps.length - 1]
            var newMinY =  Number.MAX_VALUE
            var newMaxY = -Number.MAX_VALUE

            for (var i = 0; i < timestamps.length; i++) {
                series.append(timestamps[i], values[i])
                if (values[i] < newMinY) newMinY = values[i]
                if (values[i] > newMaxY) newMaxY = values[i]
            }
            if (newMinY === Number.MAX_VALUE) { newMinY = 0; newMaxY = 1 }

            // ── Update axis bounds ────────────────────────────────────────
            if (seriesCount === 1) {
                dataMinX = newMinX
                dataMaxX = newMaxX
                dataMinY = newMinY
                dataMaxY = newMaxY
                originalMinX = dataMinX
                originalMaxX = dataMaxX

                leftAxisX.min = dataMinX
                leftAxisX.max = dataMaxX

                var paddingY = (newMaxY - newMinY) * 0.1
                if (paddingY === 0) paddingY = 1.0
                leftAxisY.min = newMinY - paddingY
                leftAxisY.max = newMaxY + paddingY

                originalMinY = leftAxisY.min
                originalMaxY = leftAxisY.max

                globalCacheThreshold = (dataMaxX - dataMinX) * 0.002
                lastYMin = leftAxisY.min
                lastYMax = leftAxisY.max
            } else {
                if (newMinX < leftAxisX.min) leftAxisX.min = newMinX
                if (newMaxX > leftAxisX.max) leftAxisX.max = newMaxX

                var curMinY  = Math.min(leftAxisY.min, newMinY)
                var curMaxY  = Math.max(leftAxisY.max, newMaxY)
                var pY       = (curMaxY - curMinY) * 0.1
                if (pY === 0) pY = 1.0
                leftAxisY.min = curMinY - pY
                leftAxisY.max = curMaxY + pY

                originalMinX = leftAxisX.min
                originalMaxX = leftAxisX.max
                originalMinY = leftAxisY.min
                originalMaxY = leftAxisY.max
                lastYMin     = leftAxisY.min
                lastYMax     = leftAxisY.max
            }

            updateVisibleWindow()
        }
    }
}

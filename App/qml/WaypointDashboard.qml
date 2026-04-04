// WaypointDashboard.qml — TiHAN Mission Planner
// ─────────────────────────────────────────────────────────────────────────
// This dashboard binds to `missionManager` (modules/mission_manager.py)
// which implements the full MAVLink Mission Sub-Protocol (upload, download,
// clear, set current, timeouts, retries, MISSION_ITEM_INT encoding).
// ─────────────────────────────────────────────────────────────────────────
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: waypointDashboard

    // ── External bindings ─────────────────────────────────────────────────
    property var  mapView:        null   // reference to MapViewQML
    property int  activeMissionWP: -1   // updated by MISSION_CURRENT

    // ── Internal state ────────────────────────────────────────────────────
    property bool expanded:       false
    property int  selectedRow:    -1
    property var  missionItems:   []    // [{seq,command,lat,lon,alt,param1,param2,frame}]
    property var  missionStats:   ({wpCount: 0, distKm: 0, eteSec: 0})

    // kept for backward-compat with older callers
    property var  waypoints:      []
    property var  waypointData:   null
    property int  selectedWaypointIndex: -1

    signal executeWaypointCommand(int index, string commandType, var waypointData)

    // ── Size ──────────────────────────────────────────────────────────────
    width:  expanded ? 470 : 46
    height: expanded ? 660 : 46
    color:  "#111318"
    radius: 6
    border.color: "#2a2d35"
    border.width: 1
    opacity: 0.97
    z: 100

    Behavior on width  { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    // ── Connect missionManager signals ────────────────────────────────────
    Connections {
        target: typeof missionManager !== "undefined" ? missionManager : null

        function onMissionChanged(items) {
            console.log("[WPDash] missionChanged:", items.length, "items")
            waypointDashboard.missionItems = items

            // Push map markers so the map stays in sync
            if (waypointDashboard.mapView && items.length > 0) {
                waypointDashboard.mapView.clearAllMarkers()
                for (var i = 0; i < items.length; i++) {
                    var it = items[i]
                    if (it.lat !== 0 || it.lon !== 0) {
                        var cmdType = it.command ? it.command.toLowerCase() : "waypoint"
                        waypointDashboard.mapView.addMarker(
                            parseFloat(it.lat), parseFloat(it.lon),
                            parseFloat(it.alt || 10), 5, cmdType)
                    }
                }
            }
        }

        function onStatsChanged(stats) {
            waypointDashboard.missionStats = stats
        }

        function onCurrentWPChanged(seq) {
            waypointDashboard.activeMissionWP = seq
        }

        function onFeedback(msg) {
            console.log("[MissionMgr]", msg)
        }
    }

    // Also listen for droneCommander feedback to show success/error feedback
    Connections {
        target: typeof droneCommander !== "undefined" ? droneCommander : null
        function onMissionCurrentChanged(seq) {
            waypointDashboard.activeMissionWP = seq
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // COLLAPSED STATE — just the toggle button
    // ══════════════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        visible: !expanded
        color: "transparent"

        Rectangle {
            width: 46; height: 46
            radius: 6
            color: collapseBtn.pressed ? "#1e88e5" : (collapseBtn.hovered ? "#1a2035" : "#111318")
            border.color: "#1e88e5"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Column {
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: 3
                    Rectangle { width: 20; height: 2; radius: 1; color: "#1e88e5" }
                }
            }

            MouseArea {
                id: collapseBtn
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: expanded = true
            }

            ToolTip { visible: collapseBtn.containsMouse; text: "Mission Planner"; delay: 400 }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // EXPANDED STATE
    // ══════════════════════════════════════════════════════════════════════
    Item {
        anchors.fill: parent
        visible: expanded

        // ── TITLE BAR ─────────────────────────────────────────────────────
        Rectangle {
            id: titleBar
            width: parent.width
            height: 38
            color: "#0d0f14"
            radius: 6

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                spacing: 8

                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: "#1e88e5"
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 900 }
                        NumberAnimation { to: 1.0; duration: 900 }
                    }
                }

                Text {
                    text: "MISSION PLANNER"
                    color: "#e8eaf6"
                    font { pixelSize: 12; bold: true; letterSpacing: 1.2; family: "Segoe UI" }
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: wpCountBadge.implicitWidth + 12
                    height: 18; radius: 9
                    color: "#1e2a3a"
                    visible: missionItems.length > 0

                    Text {
                        id: wpCountBadge
                        anchors.centerIn: parent
                        text: missionItems.length + " WP"
                        color: "#64b5f6"
                        font { pixelSize: 9; bold: true }
                    }
                }
            }

            // Close button
            Rectangle {
                width: 24; height: 24; radius: 4
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: closeBtn.pressed ? "#c62828" : (closeBtn.hovered ? "#331a1a" : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }

                Text { anchors.centerIn: parent; text: "✕"; color: "#ef5350"; font.pixelSize: 11 }
                MouseArea { id: closeBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: expanded = false }
            }
        }

        // ── TOOLBAR ───────────────────────────────────────────────────────
        Rectangle {
            id: toolbar
            anchors.top: titleBar.bottom
            anchors.topMargin: 1
            width: parent.width
            height: 68
            color: "#131620"

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                // Row 1 — add items
                Row {
                    spacing: 3
                    height: 26

                    Repeater {
                        model: [
                            { label: "+ WP",       color: "#1565c0", tip: "Add waypoint at last map click" },
                            { label: "+ Takeoff",  color: "#2e7d32", tip: "Insert Takeoff at WP1"          },
                            { label: "+ Land",     color: "#e65100", tip: "Append Landing"                  },
                            { label: "+ RTL",      color: "#6a1b9a", tip: "Append Return-to-Launch"         },
                            { label: "⟳ Loop",    color: "#00695c", tip: "Append DO_JUMP loop"             }
                        ]

                        delegate: TBarBtn {
                            label: modelData.label; accentColor: modelData.color; tipText: modelData.tip
                            height: 26
                            onActivated: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (!mm) return
                                var ll = waypointDashboard.mapView
                                         ? waypointDashboard.mapView.lastClickedCoordinate
                                         : null
                                var lat = ll ? ll.latitude  : 0
                                var lon = ll ? ll.longitude : 0
                                switch (index) {
                                    case 0: mm.insertItem(missionItems.length, lat, lon, 50, "WAYPOINT"); break
                                    case 1: mm.addTakeoff(lat, lon, 20); break
                                    case 2: mm.addLanding(lat, lon);     break
                                    case 3: mm.addRTL();                 break
                                    case 4: mm.addLoop();                break
                                }
                            }
                        }
                    }
                }

                // Row 2 — mission management
                Row {
                    spacing: 3
                    height: 26

                    Repeater {
                        model: [
                            { label: "↑ Upload",   color: "#0277bd", tip: "Upload mission to drone"       },
                            { label: "↓ Download", color: "#37474f", tip: "Download mission from drone"   },
                            { label: "🗑 Clear",   color: "#b71c1c", tip: "Clear mission on drone"        },
                            { label: "💾 Save",    color: "#283593", tip: "Save mission to file"          },
                            { label: "📂 Load",    color: "#1b5e20", tip: "Load mission from file"        }
                        ]

                        delegate: TBarBtn {
                            label: modelData.label; accentColor: modelData.color; tipText: modelData.tip
                            height: 26
                            onActivated: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (!mm && index < 3) return
                                switch (index) {
                                    case 0: waypointDashboard.doUpload();          break
                                    case 1: if (mm) mm.downloadMission();          break
                                    case 2: if (mm) mm.clearMission();             break
                                    case 3: waypointDashboard.doSave();            break
                                    case 4: waypointDashboard.doLoad();            break
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── COLUMN HEADERS ────────────────────────────────────────────────
        Rectangle {
            id: colHeaders
            anchors.top: toolbar.bottom
            anchors.topMargin: 1
            width: parent.width
            height: 24
            color: "#0a0c10"

            Row {
                anchors.fill: parent
                anchors.leftMargin: 6
                spacing: 0

                Repeater {
                    model: [
                        { label: "#",        w: 30  },
                        { label: "Command",  w: 100 },
                        { label: "Lat",      w: 82  },
                        { label: "Lon",      w: 82  },
                        { label: "Alt(m)",   w: 50  },
                        { label: "Actions",  w: 80  }
                    ]
                    delegate: Text {
                        width: modelData.w
                        text: modelData.label
                        color: "#78909c"
                        font { pixelSize: 9; bold: true; letterSpacing: 0.5 }
                        verticalAlignment: Text.AlignVCenter
                        height: parent.height
                    }
                }
            }
        }

        // ── MISSION TABLE ─────────────────────────────────────────────────
        Rectangle {
            id: tableArea
            anchors.top: colHeaders.bottom
            anchors.topMargin: 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: editDrawer.visible ? editDrawer.top : statsBar.top
            anchors.bottomMargin: 1
            color: "#0d0f14"
            clip: true

            ListView {
                id: missionList
                anchors.fill: parent
                model:  missionItems
                spacing: 1
                clip:   true
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { radius: 3; color: "#1e88e5"; opacity: 0.7 }
                    background: Rectangle { color: "#1a1d26" }
                }

                delegate: Rectangle {
                    id: wpRow
                    width:  missionList.width
                    height: 30
                    color: {
                        if (modelData.seq === activeMissionWP)  return "#0d2137"
                        if (model.index === selectedRow)        return "#161d2c"
                        return model.index % 2 === 0 ? "#111318" : "#0f1117"
                    }
                    border.color: {
                        if (modelData.seq === activeMissionWP) return "#1e88e5"
                        if (model.index === selectedRow)       return "#2d3748"
                        return "transparent"
                    }
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        spacing: 0

                        // Seq number
                        Rectangle {
                            width: 30; height: parent.height
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.seq === 0 ? "H" : modelData.seq
                                color: modelData.seq === 0 ? "#ef5350"
                                       : (modelData.seq === activeMissionWP ? "#42a5f5" : "#78909c")
                                font { pixelSize: 9; bold: true }
                            }
                        }

                        // Command badge
                        Rectangle {
                            width: 100; height: parent.height
                            color: "transparent"

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                width: cmdLabel.implicitWidth + 10
                                height: 16; radius: 3
                                color: cmdBadgeColor(modelData.command)

                                Text {
                                    id: cmdLabel
                                    anchors.centerIn: parent
                                    text: modelData.command || "WAYPOINT"
                                    color: "white"
                                    font { pixelSize: 8; bold: true }
                                }
                            }
                        }

                        // Lat
                        Text {
                            width: 82; height: parent.height
                            text: (modelData.lat || 0).toFixed(5)
                            color: modelData.lat ? "#cfd8dc" : "#37474f"
                            font.pixelSize: 8
                            verticalAlignment: Text.AlignVCenter
                        }

                        // Lon
                        Text {
                            width: 82; height: parent.height
                            text: (modelData.lon || 0).toFixed(5)
                            color: modelData.lon ? "#cfd8dc" : "#37474f"
                            font.pixelSize: 8
                            verticalAlignment: Text.AlignVCenter
                        }

                        // Alt
                        Text {
                            width: 50; height: parent.height
                            text: (modelData.alt || 0).toFixed(0)
                            color: "#80cbc4"
                            font.pixelSize: 8
                            verticalAlignment: Text.AlignVCenter
                        }

                        // Action buttons
                        Row {
                            width: 80; height: parent.height
                            spacing: 3
                            anchors.verticalCenter: parent.verticalCenter

                            // Edit
                            IconBtn {
                                icon: "✎"; tipText: "Edit"; accentColor: "#1e88e5"
                                onActivated: {
                                    selectedRow = model.index
                                    selectedWaypointIndex = model.index
                                    loadEditorFor(model.index)
                                }
                            }
                            // Move up
                            IconBtn {
                                icon: "↑"; tipText: "Move up"; accentColor: "#546e7a"
                                onActivated: {
                                    var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                    if (mm) mm.moveItemUp(model.index)
                                }
                            }
                            // Move down
                            IconBtn {
                                icon: "↓"; tipText: "Move dn"; accentColor: "#546e7a"
                                onActivated: {
                                    var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                    if (mm) mm.moveItemDown(model.index)
                                }
                            }
                            // Delete
                            IconBtn {
                                icon: "✕"; tipText: "Delete"; accentColor: "#ef5350"
                                onActivated: {
                                    var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                    if (mm) { mm.removeItem(model.index); if (selectedRow >= missionItems.length) selectedRow = -1 }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectedRow = model.index
                            selectedWaypointIndex = model.index
                            loadEditorFor(model.index)
                        }
                        onDoubleClicked: {
                            // Jump to WP on double-click
                            var mm = (typeof missionManager !== "undefined") ? missionManager : null
                            if (mm && modelData.seq > 0) mm.setCurrentWP(modelData.seq)
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: missionList.count === 0
                    text: "No mission items\n\nClick map to place\nwaypoints, then\nuse toolbar above"
                    color: "#37474f"
                    font { pixelSize: 11; family: "Segoe UI" }
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 1.5
                }
            }
        }

        // ── INLINE EDIT DRAWER ────────────────────────────────────────────
        Rectangle {
            id: editDrawer
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: statsBar.top
            height: visible ? 200 : 0
            visible: selectedRow >= 0 && selectedRow < missionItems.length
            color: "#0c1020"
            border.color: "#1e2a3a"
            border.width: 1
            clip: true

            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7

                Text {
                    text: selectedRow >= 0 ? "Edit Waypoint #" + (selectedRow) : ""
                    color: "#64b5f6"
                    font { pixelSize: 10; bold: true }
                }

                // Command selector
                Row { spacing: 8; height: 26

                    Text { text: "Command:"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 65 }

                    ComboBox {
                        id: editCmdCombo
                        width: 130; height: 24
                        model: ["WAYPOINT","TAKEOFF","LAND","RTL","LOITER_UNLIM","DO_JUMP","DO_LAND_START"]

                        background: Rectangle { color: "#1a1d26"; border.color: "#2a3040"; border.width: 1; radius: 3 }
                        contentItem: Text {
                            leftPadding: 8
                            text: editCmdCombo.displayText; color: "#cfd8dc"
                            font.pixelSize: 9; verticalAlignment: Text.AlignVCenter
                        }
                        delegate: ItemDelegate {
                            width: editCmdCombo.width; height: 22
                            contentItem: Text { text: modelData; color: "#cfd8dc"; font.pixelSize: 9; leftPadding: 8; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { color: highlighted ? "#1e3050" : "#1a1d26" }
                        }
                        popup: Popup {
                            y: editCmdCombo.height
                            width: editCmdCombo.width
                            padding: 0
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                model: editCmdCombo.delegateModel
                                clip: true
                            }
                            background: Rectangle { color: "#1a1d26"; border.color: "#2a3040"; border.width: 1; radius: 3 }
                        }
                        onActivated: {
                            var mm = (typeof missionManager !== "undefined") ? missionManager : null
                            if (mm && selectedRow >= 0) mm.setItemField(selectedRow, "command", currentText)
                        }
                    }
                }

                // Altitude
                Row { spacing: 8; height: 26

                    Text { text: "Altitude (m):"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 65 }

                    Rectangle {
                        width: 90; height: 24; radius: 3
                        color: "#1a1d26"; border.color: editAlt.activeFocus ? "#1e88e5" : "#2a3040"; border.width: 1

                        TextInput {
                            id: editAlt
                            anchors.fill: parent; anchors.margins: 6
                            color: "#80cbc4"; font.pixelSize: 9
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            validator: DoubleValidator { bottom: 0; top: 5000 }

                            onEditingFinished: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (mm && selectedRow >= 0) mm.setItemField(selectedRow, "alt", parseFloat(text))
                            }
                        }
                    }

                    Text { text: "Frame:"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 40 }

                    Text {
                        text: selectedRow >= 0 && selectedRow < missionItems.length
                              ? (missionItems[selectedRow].frame === 3 ? "REL_ALT" : "ABS")
                              : "--"
                        color: "#ffcc80"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Lat / Lon
                Row { spacing: 8; height: 26

                    Text { text: "Lat:"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 25 }
                    Rectangle {
                        width: 110; height: 24; radius: 3
                        color: "#1a1d26"; border.color: editLat.activeFocus ? "#1e88e5" : "#2a3040"; border.width: 1
                        TextInput {
                            id: editLat
                            anchors.fill: parent; anchors.margins: 6
                            color: "#cfd8dc"; font.pixelSize: 9
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (mm && selectedRow >= 0) mm.setItemField(selectedRow, "lat", parseFloat(text))
                            }
                        }
                    }

                    Text { text: "Lon:"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 25 }
                    Rectangle {
                        width: 110; height: 24; radius: 3
                        color: "#1a1d26"; border.color: editLon.activeFocus ? "#1e88e5" : "#2a3040"; border.width: 1
                        TextInput {
                            id: editLon
                            anchors.fill: parent; anchors.margins: 6
                            color: "#cfd8dc"; font.pixelSize: 9
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (mm && selectedRow >= 0) mm.setItemField(selectedRow, "lon", parseFloat(text))
                            }
                        }
                    }
                }

                // Param1 / Param2 (for DO_JUMP, loiter, etc.)
                Row { spacing: 8; height: 26
                    visible: selectedRow >= 0 && selectedRow < missionItems.length
                             && (missionItems[selectedRow].command === "DO_JUMP"
                                 || missionItems[selectedRow].command === "LOITER_TURNS"
                                 || missionItems[selectedRow].command === "LOITER_TIME")

                    Text { text: "P1:"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 25 }
                    Rectangle {
                        width: 60; height: 24; radius: 3
                        color: "#1a1d26"; border.color: editP1.activeFocus ? "#1e88e5" : "#2a3040"; border.width: 1
                        TextInput {
                            id: editP1
                            anchors.fill: parent; anchors.margins: 6
                            color: "#ffcc80"; font.pixelSize: 9
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (mm && selectedRow >= 0) mm.setItemField(selectedRow, "param1", parseFloat(text))
                            }
                        }
                    }

                    Text { text: "P2:"; color: "#78909c"; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter; width: 25 }
                    Rectangle {
                        width: 60; height: 24; radius: 3
                        color: "#1a1d26"; border.color: editP2.activeFocus ? "#1e88e5" : "#2a3040"; border.width: 1
                        TextInput {
                            id: editP2
                            anchors.fill: parent; anchors.margins: 6
                            color: "#ffcc80"; font.pixelSize: 9
                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                            onEditingFinished: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (mm && selectedRow >= 0) mm.setItemField(selectedRow, "param2", parseFloat(text))
                            }
                        }
                    }
                }

                // Close drawer
                Row { spacing: 6

                    Rectangle {
                        width: 80; height: 24; radius: 3
                        color: applyBtn.pressed ? "#1565c0" : (applyBtn.hovered ? "#1e3050" : "#1a1d26")
                        border.color: "#1e88e5"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "Apply"; color: "#64b5f6"; font { pixelSize: 9; bold: true } }
                        MouseArea { id: applyBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: selectedRow = -1 }
                    }

                    Rectangle {
                        width: 80; height: 24; radius: 3
                        color: delBtn2.pressed ? "#b71c1c" : (delBtn2.hovered ? "#331a1a" : "#1a1d26")
                        border.color: "#ef5350"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "Delete WP"; color: "#ef5350"; font { pixelSize: 9; bold: true } }
                        MouseArea {
                            id: delBtn2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var mm = (typeof missionManager !== "undefined") ? missionManager : null
                                if (mm && selectedRow >= 0) {
                                    mm.removeItem(selectedRow)
                                    selectedRow = -1
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── STATS BAR ─────────────────────────────────────────────────────
        Rectangle {
            id: statsBar
            anchors.bottom: parent.bottom
            anchors.left:   parent.left
            anchors.right:  parent.right
            height: 28
            color: "#090b0e"
            radius: 6

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                spacing: 12

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (missionStats.wpCount || 0) + " WPs"
                    color: "#64b5f6"; font { pixelSize: 9; bold: true }
                }

                Rectangle { width: 1; height: 14; color: "#2a3040"; anchors.verticalCenter: parent.verticalCenter }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Dist: " + (missionStats.distKm || 0).toFixed(2) + " km"
                    color: "#80cbc4"; font.pixelSize: 9
                }

                Rectangle { width: 1; height: 14; color: "#2a3040"; anchors.verticalCenter: parent.verticalCenter }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ETE: ~" + formatEte(missionStats.eteSec || 0)
                    color: "#ffcc80"; font.pixelSize: 9
                }

                Rectangle { width: 1; height: 14; color: "#2a3040"; anchors.verticalCenter: parent.verticalCenter }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: activeMissionWP >= 0 ? "Active: #" + activeMissionWP : "Idle"
                    color: activeMissionWP >= 0 ? "#42a5f5" : "#37474f"
                    font { pixelSize: 9; bold: activeMissionWP >= 0 }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // REUSABLE COMPONENTS (inline components)
    // ══════════════════════════════════════════════════════════════════════

    // Small toolbar button component
    component TBarBtn: Rectangle {
        property string label: ""
        property string accentColor: "#1e88e5"
        property string tipText: ""
        signal activated()

        width: tbLbl.implicitWidth + 12
        height: 26
        radius: 3
        color: tbArea.pressed ? Qt.darker(accentColor, 1.5) : (tbArea.hovered ? "#1a2035" : "#111318")
        border.color: accentColor
        border.width: 1
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            id: tbLbl
            anchors.centerIn: parent
            text: label
            color: accentColor
            font { pixelSize: 9; bold: true }
        }

        MouseArea {
            id: tbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }

        ToolTip { visible: tbArea.containsMouse; text: tipText; delay: 500 }
    }

    // Small icon action button
    component IconBtn: Rectangle {
        property string icon: "✎"
        property string tipText: ""
        property string accentColor: "#1e88e5"
        signal activated()

        width: 18; height: 18; radius: 3
        color: iArea.pressed ? Qt.darker(accentColor, 1.5) : (iArea.hovered ? "#1a2035" : "transparent")
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Behavior on color { ColorAnimation { duration: 80 } }

        Text {
            anchors.centerIn: parent
            text: icon; color: accentColor
            font { pixelSize: 10; bold: true }
        }

        MouseArea {
            id: iArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }

        ToolTip { visible: iArea.containsMouse; text: tipText; delay: 400 }
    }

    // ══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════

    function formatEte(sec) {
        if (sec <= 0) return "--"
        var m = Math.floor(sec / 60)
        var s = Math.floor(sec % 60)
        return m + "m " + s + "s"
    }

    function cmdBadgeColor(cmd) {
        switch (cmd) {
            case "TAKEOFF":       return "#2e7d32"
            case "LAND":          return "#e65100"
            case "RTL":           return "#6a1b9a"
            case "DO_JUMP":       return "#00695c"
            case "DO_LAND_START": return "#4a148c"
            case "LOITER_UNLIM":  return "#1565c0"
            case "LOITER_TURNS":  return "#1565c0"
            case "LOITER_TIME":   return "#1565c0"
            case "DO_CHANGE_SPEED": return "#455a64"
            default:              return "#1e3a5f"
        }
    }

    function loadEditorFor(idx) {
        if (idx < 0 || idx >= missionItems.length) return
        var it = missionItems[idx]
        var cmdStr = it.command || "WAYPOINT"
        var ci = editCmdCombo.find(cmdStr)
        if (ci >= 0) editCmdCombo.currentIndex = ci
        editAlt.text = (it.alt || 0).toFixed(1)
        editLat.text = (it.lat || 0).toFixed(6)
        editLon.text = (it.lon || 0).toFixed(6)
        editP1.text  = (it.param1 || 0).toFixed(0)
        editP2.text  = (it.param2 || 0).toFixed(0)
    }

    function doUpload() {
        var mm = (typeof missionManager !== "undefined") ? missionManager : null

        if (missionItems.length > 0 && mm) {
            // Upload local items to FC via spec-compliant protocol
            mm.uploadMission(missionItems)
            return
        }

        // Fallback: upload from map markers if internal list is empty
        if (mapView && mm) {
            var markers = mapView.getAllMarkers ? mapView.getAllMarkers() : []
            if (markers.length > 0) {
                mm.uploadMissionFromMap(markers)
                return
            }
        }

        // Final fallback: use old droneCommander.uploadMission
        var dc = (typeof droneCommander !== "undefined") ? droneCommander : null
        if (dc && mapView) {
            var m2 = mapView.getAllMarkers ? mapView.getAllMarkers() : []
            if (m2.length > 0) dc.uploadMission(m2)
        }
    }

    function doSave() {
        var mm = (typeof missionManager !== "undefined") ? missionManager : null
        if (!mm) return
        var jsonStr = mm.toJson()
        if (!jsonStr || jsonStr === "") return

        // Use Qt file dialog for save
        try {
            var dialog = Qt.createQmlObject(
                'import QtQuick.Dialogs 1.3; FileDialog { title: "Save Mission"; selectExisting: false; nameFilters: ["Mission files (*.json)", "All files (*)"]; }',
                waypointDashboard, "saveDialog")
            if (dialog) {
                dialog.onAccepted.connect(function() {
                    var path = dialog.fileUrl.toString().replace("file://", "")
                    writeTextFile(path, jsonStr)
                    dialog.destroy()
                })
                dialog.open()
            }
        } catch (e) {
            console.warn("Save dialog error:", e)
            // Fallback: use waypointsSaver if available
            var saver = (typeof waypointsSaver !== "undefined") ? waypointsSaver : null
            if (saver) {
                saver.save_file("/tmp/mission_backup.json", jsonStr)
            }
        }
    }

    function doLoad() {
        var mm = (typeof missionManager !== "undefined") ? missionManager : null
        if (!mm) return

        try {
            var dialog = Qt.createQmlObject(
                'import QtQuick.Dialogs 1.3; FileDialog { title: "Load Mission"; selectExisting: true; nameFilters: ["Mission files (*.json)", "All files (*)"]; }',
                waypointDashboard, "loadDialog")
            if (dialog) {
                dialog.onAccepted.connect(function() {
                    var path = dialog.fileUrl.toString().replace("file://", "")
                    var text = readTextFile(path)
                    if (text) {
                        mm.fromJson(text)
                    }
                    dialog.destroy()
                })
                dialog.open()
            }
        } catch (e) {
            console.warn("Load dialog error:", e)
        }
    }

    // JS file I/O helpers (Qt5 XHR for local files)
    function writeTextFile(path, content) {
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("PUT", "file://" + path, false)
            xhr.send(content)
            return xhr.status === 0
        } catch (e) { console.warn("writeTextFile error:", e); return false }
    }

    function readTextFile(path) {
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + path, false)
            xhr.send()
            return xhr.responseText
        } catch (e) { console.warn("readTextFile error:", e); return "" }
    }

    // ── Old API shims (backward compat with older callers) ─────────────────
    function show()   { visible = true;  expanded = true  }
    function hide()   { expanded = false }
    function updateWaypoints(newWaypoints) {
        // Legacy: populate internal list from plain [{lat,lng,altitude,commandType}]
        if (!newWaypoints) { missionItems = []; return }
        var result = []
        for (var i = 0; i < newWaypoints.length; i++) {
            var wp = newWaypoints[i]
            result.push({
                seq:     i,
                command: (wp.commandType || wp.command || "WAYPOINT").toUpperCase(),
                lat:     wp.lat || wp.latitude  || 0,
                lon:     wp.lng || wp.longitude || 0,
                alt:     wp.altitude || 10,
                param1:  0, param2: 0, frame: 3
            })
        }
        missionItems = result
    }
}
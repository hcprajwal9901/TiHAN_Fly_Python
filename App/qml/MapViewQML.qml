// MapViewQML_merged.qml
// ═══════════════════════════════════════════════════════════════════════════
//  MERGED VERSION — combines every feature from both source files:
//
//  FROM FILE 1  ▸  videoOverlay (camera PiP panel)
//                  • 5 tabs: Video / Controls / Gimbal / Cameras / Stream
//                  • RTSP stream image + 30-fps refresh timer
//                  • Animated HUD (vignette, scanlines, sweep-line, crosshair,
//                    corner brackets, top/bottom data bars)
//                  • "NO SIGNAL" idle state
//                  • cameraControls / gimbalControls / multiCameraPanel /
//                    streamPanel sub-components
//
//  FROM FILE 2  ▸  Multi-provider map Loader (Google / Bing / OSM)
//                  • switchMapProvider(), cycleMapType(), cycleMapProvider()
//                  • Provider selection Menu + state preservation
//                  • Distance calculations & route stats overlay
//                    (totalRouteDistance, distanceCovered, distanceRemaining)
//                  • Cursor-coordinate tracker
//                  • Drone info panel (top-left)
//                  • Map controls sidebar (zoom / center / provider / mode btns)
//                  • Extended survey patterns: rectangle + circle
//                  • Route canvas: directional arrows + per-segment distance labels
//                  • Legacy runJavaScript() compatibility shim
//                  • showBuiltinControls toggle property
//                  • currentHeading telemetry property
// ═══════════════════════════════════════════════════════════════════════════
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtLocation 5.15
import QtPositioning 5.15

Item {
    id: root
    width: 700
    height: 500

    // =========================================================================
    // STATE PRESERVATION (provider switching)
    // =========================================================================
    property var  pendingCenter:       QtPositioning.coordinate(0, 0)
    property real pendingZoom:         2
    property int  pendingMapTypeIndex: 0

    // =========================================================================
    // MAP PROVIDER
    // =========================================================================
    property string selectedProvider:         "google"
    property bool   providerSwitchInProgress: false

    // =========================================================================
    // MARKER / EDITING STATE
    // =========================================================================
    property bool addMarkersMode:      false
    property var  lastClickedCoordinate: null
    property bool isEditable:          true
    property bool showBuiltinControls: true   // false when embedded elsewhere

    // =========================================================================
    // POLYGON / SURVEY
    // =========================================================================
    property bool polygonSurveyMode: false
    property var  polygonCorners:    []
    property real surveyAltitude:    50
    property real surveyOverlap:     70
    property real surveySidelap:     60
    property real surveyAngle:       0
    property real surveySpeed:       10
    property real surveyLineSpacing: 50
    property string surveyPattern:   "horizontal"

    // =========================================================================
    // MISSION / FLIGHT PATH
    // =========================================================================
    property var  uploadedMissionPath: []
    property bool showUploadedPath:    false
    property color missionPathColor:   "#0080FF"
    property real  missionPathWidth:   4

    property var  actualFlightPath:     []
    property int  currentWaypointIndex: -1
    property bool missionActive:        false
    property var  missionWaypoints:     []
    property int  lastReachedWaypoint:  -1
    property int  _routeTrigger:        0
    property int  _flightPathTrigger:   0

    // Corner drag state
    property int  draggedCornerIndex: -1
    property bool isDraggingCorner:   false

    // =========================================================================
    // NFZ HOVER TOOLTIP STATE
    // =========================================================================
    property string nfzHoverText:    ""
    property real   nfzHoverX:       0
    property real   nfzHoverY:       0
    property bool   nfzHoverVisible: false

    // =========================================================================
    // DRONE TELEMETRY
    // =========================================================================
    property real currentLat:     typeof droneModel !== "undefined" && droneModel ? droneModel.droneLat     : 0
    property real currentLon:     typeof droneModel !== "undefined" && droneModel ? droneModel.droneLon     : 0
    property real currentAlt:     typeof droneModel !== "undefined" && droneModel ? droneModel.droneAlt     : 0
    property real currentHeading: typeof droneModel !== "undefined" && droneModel ? droneModel.droneHeading : 0
    property bool isDroneConnected:      (typeof droneModel !== "undefined" && droneModel) ? droneModel.isConnected : false
    property bool hasValidDroneLocation: currentLat !== 0 && currentLon !== 0 && !isNaN(currentLat) && !isNaN(currentLon)

    // =========================================================================
    // DISTANCE / ROUTE STATS
    // =========================================================================
    property string distanceUnit:       "km"   // "m" or "km"
    property real   totalRouteDistance: 0
    property real   distanceCovered:    0
    property real   distanceRemaining:  totalRouteDistance > 0 ? Math.max(0, totalRouteDistance - distanceCovered) : 0

    // =========================================================================
    // LEGACY MARKERS ARRAY (JS mirror of markersModel)
    // =========================================================================
    property var markers: []

    // =========================================================================
    // SIGNALS
    // =========================================================================
    signal markerAdded(real lat, real lon)
    signal markerMoved(int index)
    signal markerDeleted(int index)
    signal locationClicked(real lat, real lon)

    // =========================================================================
    // DEBUG / CHANGE HANDLERS
    // =========================================================================
    onCurrentLatChanged:            { root.updateDistanceCovered() }
    onCurrentLonChanged:            { root.updateDistanceCovered() }
    onIsDroneConnectedChanged:      console.log("🔌 Drone connected:", isDroneConnected)
    onHasValidDroneLocationChanged: console.log("📍 Valid location:", hasValidDroneLocation, "Lat:", currentLat, "Lon:", currentLon)

    // =========================================================================
    // CONNECTIONS — droneModel mission path
    // =========================================================================
    Connections {
        target: typeof droneModel !== 'undefined' ? droneModel : null
        function onMissionPathUpdated(waypoints) {
            if (waypoints && waypoints.length > 0)
                root.setUploadedMissionPath(waypoints)
        }
    }

    // =========================================================================
    // MARKERS MODEL
    // =========================================================================
    ListModel {
        id: markersModel
        onCountChanged: {
            console.log("📊 markersModel count changed:", count)
            root._routeTrigger++
            if (typeof root.updateRoutePath !== "undefined") root.updateRoutePath()
            root.updateTotalDistance()
            root.updateDistanceCovered()
        }
    }

    onPolygonCornersChanged: {
        if (typeof polygonDashboard !== "undefined") {
            if (polygonCorners.length > 0) {
                polygonDashboard.updatePolygonData(polygonCorners)
                if (!polygonDashboard.dashboardVisible) polygonDashboard.show()
            } else {
                polygonDashboard.hide()
            }
        }
        // polygonCanvas.requestPaint() // REMOVED: replaced with MapPolygon
    }

    onMarkerMoved: {
        root._routeTrigger++
        root.updateTotalDistance()
        root.updateDistanceCovered()
    }

    // =========================================================================
    // FLIGHT PATH RECORDER
    // =========================================================================
    Timer {
        id: pathRecordTimer
        interval: 1000
        running: false // root.isDroneConnected && root.hasValidDroneLocation
        repeat:   true
        onTriggered: {
            if (root.hasValidDroneLocation) {
                var temp = root.actualFlightPath
                temp.push({ lat: root.currentLat, lng: root.currentLon, timestamp: Date.now() })
                if (temp.length > 100) temp.shift()
                root.actualFlightPath = temp
                root._flightPathTrigger++
            }
        }
    }

    // =========================================================================
    // NFZ PROXIMITY — driven by Python nfzManager signals
    // =========================================================================
    Connections {
        target: (typeof nfzManager !== 'undefined' && nfzManager) ? nfzManager : null

        // Fires every 2 s while drone is within 500 m of any NFZ boundary
        function onDroneNearNFZ(zoneName, distanceM) {
            nfzProximityText.text     = "\u26a0\ufe0f  Approaching: " + zoneName
            nfzProximityDistText.text = distanceM > 0
                ? "Distance to boundary: " + distanceM.toFixed(0) + " m"
                : "\u26d4 Inside No-Fly Zone!"
            nfzProximityBanner.opacity = 1
            nfzProximityBannerTimer.restart()
        }

        // Fires when drone moves back outside the 500 m proximity radius
        function onDroneExitedProximity() {
            nfzProximityBanner.opacity = 0
        }

        // Fires when drone enters an NFZ (also keep red banner if needed)
        function onDroneInNFZ(zoneName) {
            nfzProximityText.text     = "\u26d4  INSIDE NO-FLY ZONE"
            nfzProximityDistText.text = zoneName
            nfzProximityBanner.opacity = 1
            nfzProximityBannerTimer.restart()
        }
    }

    // =========================================================================
    // AUTO-CENTER TIMER
    // =========================================================================
    Timer {
        interval: 500
        running:  true
        repeat:   true
        property bool hasTriggeredInitialCenter: false
        property bool previousConnectionState:   false
        onTriggered: {
            var cur = root.isDroneConnected && root.hasValidDroneLocation
            if (cur && (!previousConnectionState || !hasTriggeredInitialCenter)) {
                if (mapLoader.item) {
                    mapLoader.item.center    = QtPositioning.coordinate(root.currentLat, root.currentLon)
                    mapLoader.item.zoomLevel = 18
                    hasTriggeredInitialCenter = true
                }
            } else if (!cur && previousConnectionState) {
                if (mapLoader.item) {
                    mapLoader.item.center    = QtPositioning.coordinate(0, 0)
                    mapLoader.item.zoomLevel = 2
                }
                hasTriggeredInitialCenter = false
            }
            previousConnectionState = cur
        }
    }

    // =========================================================================
    // MAP RELOAD TIMER (provider switching)
    // =========================================================================
    Timer {
        id: reloadTimer
        interval: 100
        repeat:   false
        onTriggered: {
            console.log("🔄 Reloading map for provider:", root.selectedProvider)
            mapLoader.sourceComponent = null
            Qt.callLater(function() { mapLoader.sourceComponent = mapComponent })
        }
    }

    // =========================================================================
    // OUTER BACKGROUND RECTANGLE
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0a"
        radius: 8
        border.color: "#404040"
        border.width: 1

        // ── PLUGINS ──────────────────────────────────────────────────────────
        Plugin {
            id: googlePlugin
            name: "google"
            PluginParameter { name: "googlemaps.mapping.cache.memory.size"; value: 104857600  }
            PluginParameter { name: "googlemaps.mapping.cache.disk.size";   value: 2147483648 }
            Component.onCompleted: console.log("✅ Google Plugin Loaded")
        }
        Plugin { id: bingPlugin; name: "bing"; Component.onCompleted: console.log("✅ Bing Plugin Loaded") }
        Plugin {
            id: osmPlugin; name: "osm"
            PluginParameter { name: "osm.mapping.highdpi_tiles"; value: true }
            Component.onCompleted: console.log("✅ OSM Plugin Loaded")
        }

        // ── MAP COMPONENT ─────────────────────────────────────────────────────
        Component {
            id: mapComponent
            Map {
                id: internalMap
                anchors.fill: parent
                color: "#1e1e1e"  // Prevents white flashes when QML scene graph redraws
                layer.enabled: true // Force FBO texture caching to prevent Qt5 Map rendering dropouts on overlay hover
                plugin: root.selectedProvider === "google" ? googlePlugin :
                        root.selectedProvider === "bing"   ? bingPlugin   : osmPlugin
                zoomLevel: 2
                minimumZoomLevel: 1
                maximumZoomLevel: 20

                function applyHybridMapType() {
                    if (supportedMapTypes.length === 0) return
                    if (root.selectedProvider === "osm") {
                        for (var s = 0; s < supportedMapTypes.length; s++) {
                            var sn = supportedMapTypes[s].name.toLowerCase()
                            if (sn.indexOf("street") !== -1 || supportedMapTypes[s].style === MapType.StreetMap) {
                                activeMapType = supportedMapTypes[s]; return
                            }
                        }
                        activeMapType = supportedMapTypes[0]; return
                    }
                    for (var i = 0; i < supportedMapTypes.length; i++) {
                        var tn = supportedMapTypes[i].name.toLowerCase()
                        if (tn.indexOf("hybrid") !== -1 || supportedMapTypes[i].style === MapType.HybridMap) {
                            activeMapType = supportedMapTypes[i]; return
                        }
                    }
                    activeMapType = supportedMapTypes[supportedMapTypes.length - 1]
                }

                onSupportedMapTypesChanged: { if (supportedMapTypes.length > 0) applyHybridMapType() }

                Component.onCompleted: {
                    console.log("🗺️ Map Instance Created. Provider:", root.selectedProvider)
                    if (supportedMapTypes.length > 0) applyHybridMapType()
                    if (root.pendingCenter.isValid) center    = root.pendingCenter
                    if (root.pendingZoom > 0)       zoomLevel = root.pendingZoom
                }

                // ── NFZ CIRCLES ───────────────────────────────────────────────
                MapItemView {
                    id: nfzCircleView
                    model: (typeof nfzManager !== 'undefined' && nfzManager) ? nfzManager.nfzZones : []
                    delegate: MapQuickItem {
                        coordinate: QtPositioning.coordinate(
                            modelData ? modelData.centroid_lat : 0,
                            modelData ? modelData.centroid_lon : 0)
                        anchorPoint.x: nfzCircleContainer.width  / 2
                        anchorPoint.y: nfzCircleContainer.height / 2
                        zoomLevel: 0
                        visible: internalMap.zoomLevel >= 10

                        sourceItem: Item {
                            id: nfzCircleContainer
                            property real zoneRadiusMeters:   modelData ? (modelData.radius_m || 5000) : 5000
                            property real latRad:             (modelData ? modelData.centroid_lat : 0) * Math.PI / 180.0
                            property real earthCircumference: 40075016.686
                            property real pixelsPerMeter:     (256.0 * Math.pow(2.0, internalMap.zoomLevel)) /
                                                              (earthCircumference * Math.cos(latRad))
                            property real radiusPx: zoneRadiusMeters * pixelsPerMeter
                            width:  radiusPx * 2
                            height: radiusPx * 2

                            Connections {
                                target: internalMap
                                function onZoomLevelChanged() {
                                    nfzCircleContainer.pixelsPerMeter =
                                        (256.0 * Math.pow(2.0, internalMap.zoomLevel)) /
                                        (nfzCircleContainer.earthCircumference * Math.cos(nfzCircleContainer.latRad))
                                }
                            }

                            Rectangle {
                                id: nfzCircleShape
                                anchors.fill: parent
                                radius: width / 2
                                color:        "#55E8506A"
                                border.color: "#AAC0392B"
                                border.width: 2
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                onEntered: {
                                    nfzCircleShape.color        = "#77E8506A"
                                    nfzCircleShape.border.color = "#CCE8506A"
                                    var sp = internalMap.fromCoordinate(
                                        QtPositioning.coordinate(
                                            modelData ? modelData.centroid_lat : 0,
                                            modelData ? modelData.centroid_lon : 0))
                                    root.nfzHoverText    = modelData ? (modelData.name || "NFZ Zone") : "NFZ Zone"
                                    root.nfzHoverX       = sp.x
                                    root.nfzHoverY       = sp.y
                                    root.nfzHoverVisible = true
                                }
                                onExited: {
                                    nfzCircleShape.color        = "#55E8506A"
                                    nfzCircleShape.border.color = "#AAC0392B"
                                    root.nfzHoverVisible = false
                                }
                                onPositionChanged: {
                                    var sp = internalMap.fromCoordinate(
                                        QtPositioning.coordinate(
                                            modelData ? modelData.centroid_lat : 0,
                                            modelData ? modelData.centroid_lon : 0))
                                    root.nfzHoverX = sp.x
                                    root.nfzHoverY = sp.y
                                }
                            }
                        }
                    }
                }
                // END NFZ CIRCLES

                // ── MAP CLICK / DOUBLE-CLICK HANDLER ─────────────────────────
                
                // ── HARDWARE ACCELERATED OVERLAYS ─────────────────────────
                MapPolygon {
                    id: surveyPolygon
                    color: "#4CFDB280"
                    border.color: "#FF9900"
                    border.width: 3
                    path: {
                        var polyPath = []
                        for (var i = 0; i < root.polygonCorners.length; i++) {
                            polyPath.push(QtPositioning.coordinate(root.polygonCorners[i].lat, root.polygonCorners[i].lng))
                        }
                        return polyPath
                    }
                    visible: root.polygonCorners.length > 0
                }

                MapPolyline {
                    id: routePolyline
                    line.width: 3
                    line.color: "#FF0000"
                    path: {
                        var dummy = root._routeTrigger
                        var dummy2 = markersModel.count
                        var route = []
                        for (var i = 0; i < markersModel.count; i++) {
                            route.push(QtPositioning.coordinate(markersModel.get(i).lat, markersModel.get(i).lng))
                        }
                        return route
                    }
                }

                MapPolyline {
                    id: droneTrailPolyline
                    line.width: 3
                    line.color: "#00FF00"
                    path: {
                        var dummy = root._flightPathTrigger
                        var route = []
                        for (var i = 0; i < root.actualFlightPath.length; i++) {
                            route.push(QtPositioning.coordinate(root.actualFlightPath[i].lat, root.actualFlightPath[i].lng))
                        }
                        return route
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: false
                    acceptedButtons: Qt.LeftButton
                    z: 50
                    onClicked: {
                        root.nfzHoverVisible = false
                        var coord = internalMap.toCoordinate(Qt.point(mouse.x, mouse.y))
                        if (coord.isValid) {
                            if (root.polygonSurveyMode) {
                                root.polygonCorners.push({ lat: coord.latitude, lng: coord.longitude })
                                root.polygonCornersChanged()
                                // polygonCanvas.requestPaint() // REMOVED
                                return
                            } else if (root.addMarkersMode) {
                                // ── NFZ RESTRICTION CHECK ──────────────────
                                var nfzResult = root.isPointInNFZ(coord.latitude, coord.longitude)
                                if (nfzResult.inside) {
                                    root.showNFZWarning("⛔ No-Fly Zone: " + nfzResult.zoneName)
                                    return
                                }
                                // ───────────────────────────────────────────
                                root.addMarker(coord.latitude, coord.longitude, 10, 5, "waypoint")
                            }
                            root.lastClickedCoordinate = coord
                            root.locationClicked(coord.latitude, coord.longitude)
                        }
                    }
                    onDoubleClicked: {
                        var coord = internalMap.toCoordinate(Qt.point(mouse.x, mouse.y))
                        internalMap.center = coord
                        if (internalMap.zoomLevel < internalMap.maximumZoomLevel)
                            internalMap.zoomLevel += 1
                    }
                }
            }
        }
        // END mapComponent

        // ── MAP LOADER ────────────────────────────────────────────────────────
        Loader {
            id: mapLoader
            anchors.fill: parent
            sourceComponent: mapComponent
            asynchronous: false
            onLoaded: {
                console.log("✅ Map Loader finished. Provider:", root.selectedProvider)
                root.providerSwitchInProgress = false
            }
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.error("❌ Map loading error!")
                    root.providerSwitchInProgress = false
                }
            }
        }

        // ── POLYGON CANVAS (REMOVED: REPLACED W/ MAPPOLYGON) ──────────────

        // ── POLYGON CORNER DOTS ───────────────────────────────────────────────
        Repeater {
            model: root.polygonCorners.length
            Item {
                id: cornerDot
                width: 30; height: 30
                property var coordinate:  QtPositioning.coordinate(root.polygonCorners[index].lat, root.polygonCorners[index].lng)
                property var screenPos:   mapLoader.item ? mapLoader.item.fromCoordinate(coordinate) : Qt.point(-999,-999)
                property int cornerIndex: index
                x: screenPos.x - width  / 2
                y: screenPos.y - height / 2
                z: 500 + index
                visible: mapLoader.item && screenPos.x >= 0 && screenPos.y >= 0
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                        var cx = width / 2, cy = height / 2
                        ctx.beginPath(); ctx.arc(cx, cy, 12, 0, Math.PI * 2); ctx.fillStyle = "#FF990040"; ctx.fill()
                        ctx.beginPath(); ctx.arc(cx, cy, 8,  0, Math.PI * 2); ctx.fillStyle = "#FF9900";   ctx.fill()
                        ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.stroke()
                        ctx.beginPath(); ctx.arc(cx, cy, 4,  0, Math.PI * 2); ctx.fillStyle = "#FFCC66";   ctx.fill()
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    hoverEnabled: true
                    drag.target: parent; drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0; drag.maximumX: mapLoader.width
                    drag.minimumY: 0; drag.maximumY: mapLoader.height
                    property bool wasDragged: false
                    onPressed: { if (mouse.button === Qt.LeftButton) { wasDragged = false; root.draggedCornerIndex = cornerDot.cornerIndex; root.isDraggingCorner = true } }
                    onPositionChanged: {
                        if (drag.active && mapLoader.item) {
                            wasDragged = true
                            var np = Qt.point(cornerDot.x + cornerDot.width / 2, cornerDot.y + cornerDot.height / 2)
                            var nc = mapLoader.item.toCoordinate(np)
                            if (nc.isValid) { root.polygonCorners[cornerDot.cornerIndex] = { lat: nc.latitude, lng: nc.longitude }; /* polygonCanvas.requestPaint() */ }
                        }
                    }
                    onReleased: {
                        if (wasDragged && mapLoader.item) {
                            var np = Qt.point(cornerDot.x + cornerDot.width / 2, cornerDot.y + cornerDot.height / 2)
                            var nc = mapLoader.item.toCoordinate(np)
                            if (nc.isValid) { root.polygonCorners[cornerDot.cornerIndex] = { lat: nc.latitude, lng: nc.longitude }; root.polygonCornersChanged() }
                            wasDragged = false
                        }
                        root.isDraggingCorner = false; root.draggedCornerIndex = -1
                    }
                    onClicked: { if (mouse.button === Qt.RightButton && !wasDragged) { root.polygonCorners.splice(cornerDot.cornerIndex, 1); root.polygonCornersChanged() } }
                    onEntered: { if (!root.isDraggingCorner) parent.scale = 1.3 }
                    onExited:  { if (!root.isDraggingCorner) parent.scale = 1.0 }
                }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Connections {
                    target: mapLoader.item
                    function onCenterChanged()    { if (mapLoader.item) cornerDot.screenPos = mapLoader.item.fromCoordinate(cornerDot.coordinate) }
                    function onZoomLevelChanged() { if (mapLoader.item) cornerDot.screenPos = mapLoader.item.fromCoordinate(cornerDot.coordinate) }
                }
            }
        }

        // ── CUSTOM MARKER OVERLAYS ────────────────────────────────────────────
        Repeater {
            id: markerOverlays
            model: markersModel
            Item {
                id: markerPin
                width: 45; height: 55
                property var  coordinate:      QtPositioning.coordinate(model.lat, model.lng)
                property var  screenPos:       mapLoader.item ? mapLoader.item.fromCoordinate(coordinate) : Qt.point(-999, -999)
                property bool isHome:          model.index === 0
                property bool isPolygonCorner: model.commandType === "polygon_corner"
                x: screenPos.x - width  / 2
                y: screenPos.y - height
                z: 1000 + model.index
                visible: mapLoader.item && screenPos.x >= 0 && screenPos.y >= 0 &&
                         screenPos.x <= mapLoader.width && screenPos.y <= mapLoader.height

                Image {
                    id: markerImage; anchors.fill: parent; source: "../images/mk.png"
                    fillMode: Image.PreserveAspectFit; smooth: true; antialiasing: true
                    visible: !markerPin.isPolygonCorner
                    onStatusChanged: { if (status === Image.Error) { markerImage.visible = false; fallbackPin.visible = true } }
                }
                Canvas {
                    id: fallbackPin; anchors.fill: parent; visible: markerPin.isPolygonCorner
                    onPaint: {
                        var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                        var pc = markerPin.isPolygonCorner ? "#FF6600" : (markerPin.isHome ? "#FF0000" : "#2196F3")
                        ctx.fillStyle = pc; ctx.strokeStyle = "white"; ctx.lineWidth = 2
                        ctx.beginPath(); ctx.arc(22, 17, 14, 0, Math.PI * 2)
                        ctx.moveTo(22, 31); ctx.lineTo(22, 50); ctx.lineTo(8, 31)
                        ctx.arc(22, 17, 14, Math.PI * 0.7, Math.PI * 2.3)
                        ctx.closePath(); ctx.fill(); ctx.stroke()
                    }
                }
                Rectangle {
                    id: labelBg
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    anchors.verticalCenterOffset: -8
                    width: 24; height: 24; radius: 12
                    visible: !markerPin.isPolygonCorner
                    color: {
                        if (markerPin.isHome) return "#e74c3c"
                        var ct = model.commandType || "waypoint"
                        switch (ct) { case "takeoff": return "#27ae60"; case "land": return "#f39c12"; default: return "#3498db" }
                    }
                    border.color: "white"; border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: { if (markerPin.isHome) return "H"; var ct = model.commandType || "waypoint"; switch (ct) { case "takeoff": return "T"; case "land": return "L"; default: return "W" } }
                        font.pixelSize: 16; font.bold: true; font.family: "Ubuntu"; color: "white"
                    }
                }
                Rectangle {
                    id: numberBadge
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: labelBg.top; anchors.bottomMargin: 3
                    width: 22; height: 20; radius: 10
                    color: "#2c3e50"; border.color: "white"; border.width: 2
                    visible: model.index >= 0
                    Text { anchors.centerIn: parent; text: model.index + 1; font.pixelSize: 12; font.bold: true; font.family: "Ubuntu"; color: "white" }
                }
                Rectangle {
                    id: altitudeBadge
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom; anchors.topMargin: 2
                    width: altText.width + 10; height: 18; radius: 4
                    color: "#34495e"; opacity: 0.95
                    visible: model.altitude > 0; border.color: "white"; border.width: 1
                    Text { id: altText; anchors.centerIn: parent; text: "⬆ " + model.altitude.toFixed(0) + "m"; font.pixelSize: 10; font.bold: true; font.family: "Ubuntu"; color: "white" }
                }
                MouseArea {
                    id: markerMouseArea; anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    hoverEnabled: true
                    drag.target: parent; drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0; drag.maximumX: mapLoader.width
                    drag.minimumY: 0; drag.maximumY: mapLoader.height
                    property bool wasDragged: false
                    onPressed: { if (mouse.button === Qt.LeftButton) { wasDragged = false; markerPin.z = 2000 } }
                    onPositionChanged: { if (drag.active) { wasDragged = true } }
                    onClicked: {
                        if (mouse.button === Qt.LeftButton && !wasDragged) {
                            if (typeof showMarkerPopupForIndex !== "undefined") showMarkerPopupForIndex(model.index)
                            else if (typeof mainWindow !== "undefined" && typeof mainWindow.showMarkerPopupForIndex !== "undefined") mainWindow.showMarkerPopupForIndex(model.index)
                        }
                    }
                    onReleased: {
                        markerPin.z = 1000 + model.index
                        if (wasDragged && mapLoader.item) {
                            var np = Qt.point(markerPin.x + markerPin.width / 2, markerPin.y + markerPin.height)
                            var nc = mapLoader.item.toCoordinate(np)
                            if (nc.isValid) {
                                markersModel.set(model.index, { lat: nc.latitude, lng: nc.longitude, altitude: model.altitude, speed: model.speed, commandType: model.commandType })
                                root.syncMarkersArrayFromModel(); root.markersChanged(); root.markerMoved(model.index)
                            }
                            wasDragged = false
                        }
                    }
                    onEntered: { if (!drag.active) parent.scale = 1.15 }
                    onExited:  { if (!drag.active) parent.scale = 1.0  }
                }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Connections {
                    target: mapLoader.item
                    function onCenterChanged()    { if (mapLoader.item) markerPin.screenPos = mapLoader.item.fromCoordinate(markerPin.coordinate) }
                    function onZoomLevelChanged() { if (mapLoader.item) markerPin.screenPos = mapLoader.item.fromCoordinate(markerPin.coordinate) }
                }
            }
        }
        // END marker overlays

        // ── CURRENT WAYPOINT PULSE RING ───────────────────────────────────────
        Repeater {
            model: missionActive ? 1 : 0
            Item {
                id: currentWaypointRing; width: 80; height: 80
                visible: currentWaypointIndex >= 0 && currentWaypointIndex < markersModel.count
                property var targetWaypoint: currentWaypointIndex >= 0 ? markersModel.get(currentWaypointIndex) : null
                property var coordinate:     targetWaypoint ? QtPositioning.coordinate(targetWaypoint.lat, targetWaypoint.lng) : QtPositioning.coordinate(0, 0)
                property var screenPos:      mapLoader.item ? mapLoader.item.fromCoordinate(coordinate) : Qt.point(-999,-999)
                x: screenPos.x - width / 2; y: screenPos.y - height / 2; z: 999
                Canvas {
                    anchors.fill: parent; property real pulseSize: 0
                    NumberAnimation on pulseSize { from: 0; to: 1; duration: 1500; loops: Animation.Infinite }
                    onPulseSizeChanged: requestPaint()
                    onPaint: { var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height); ctx.beginPath(); ctx.arc(width/2, height/2, 30*pulseSize, 0, Math.PI*2); ctx.strokeStyle = "#00FF00"; ctx.lineWidth = 3; ctx.globalAlpha = 1 - pulseSize; ctx.stroke() }
                }
                Connections {
                    target: mapLoader.item
                    function onCenterChanged()    { if (mapLoader.item) currentWaypointRing.screenPos = mapLoader.item.fromCoordinate(currentWaypointRing.coordinate) }
                    function onZoomLevelChanged() { if (mapLoader.item) currentWaypointRing.screenPos = mapLoader.item.fromCoordinate(currentWaypointRing.coordinate) }
                }
            }
        }

        // ── DRONE OVERLAY ITEM ────────────────────────────────────────────────
        Item {
            id: droneMarkerOverlay
            width: 60; height: 60
            visible: root.isDroneConnected && root.hasValidDroneLocation
            z: 2000
            property var coordinate: QtPositioning.coordinate(root.currentLat, root.currentLon)
            function updatePosition() {
                if (!mapLoader.item) return
                var pos = mapLoader.item.fromCoordinate(coordinate)
                x = pos.x - width / 2; y = pos.y - height / 2
            }
            Component.onCompleted: updatePosition()
            onCoordinateChanged: { updatePosition() }
            Image {
                id: droneHomeIcon; anchors.fill: parent; source: "../images/home.png"
                fillMode: Image.PreserveAspectFit; smooth: true; antialiasing: true
                rotation: root.currentHeading
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                onStatusChanged: { if (status === Image.Error) fallbackDroneMarker.visible = true }
            }
            Rectangle {
                id: fallbackDroneMarker; anchors.fill: parent; radius: 30
                color: "#00e676"; border.color: "white"; border.width: 3; visible: false
                Text { anchors.centerIn: parent; text: "🚁"; font.pixelSize: 28; font.bold: true }
            }
            Connections { target: mapLoader.item; function onCenterChanged() { droneMarkerOverlay.updatePosition() } function onZoomLevelChanged() { droneMarkerOverlay.updatePosition() } }
            Connections {
                target: root
                function onCurrentLatChanged() { droneMarkerOverlay.coordinate = QtPositioning.coordinate(root.currentLat, root.currentLon) }
                function onCurrentLonChanged() { droneMarkerOverlay.coordinate = QtPositioning.coordinate(root.currentLat, root.currentLon) }
            }
        }

        // ── NFZ HOVER TOOLTIP ─────────────────────────────────────────────────
        Rectangle {
            id: nfzHoverTooltip
            visible: root.nfzHoverVisible
            x: Math.max(4, Math.min(root.nfzHoverX - width / 2, parent.width - width - 4))
            y: Math.max(4, root.nfzHoverY - height - 16)
            width: nfzHoverLabel.implicitWidth + 24; height: nfzHoverLabel.implicitHeight + 12
            radius: 18; color: "#F5F5FF"; border.color: "#CC3333"; border.width: 1.5; z: 3500
            opacity: root.nfzHoverVisible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Text { id: nfzHoverLabel; anchors.centerIn: parent; text: root.nfzHoverText; color: "#CC0000"; font.pixelSize: 12; font.bold: true; font.family: "Ubuntu" }
            Canvas {
                width: 14; height: 8; anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.bottom
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(width, 0); ctx.lineTo(width / 2, height); ctx.closePath()
                    ctx.fillStyle = "#F5F5FF"; ctx.fill(); ctx.strokeStyle = "#CC3333"; ctx.lineWidth = 1.5; ctx.stroke()
                }
            }
        }

        // ── NFZ WARNING BANNER (red – waypoint placement blocked) ─────────────
        Rectangle {
            id: nfzWarningBanner
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 16
            width: nfzWarningText.implicitWidth + 48
            height: 46
            radius: 10
            color: "#CC000000"
            border.color: "#FF3B30"
            border.width: 2
            z: 9000
            opacity: 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

            Row {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    text: "⛔"
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    id: nfzWarningText
                    text: "Waypoint blocked: No-Fly Zone"
                    color: "#FF5F57"
                    font.pixelSize: 14
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Timer {
                id: nfzWarningTimer
                interval: 3000
                repeat: false
                onTriggered: nfzWarningBanner.opacity = 0
            }
        }

        // ── NFZ PROXIMITY WARNING BANNER (yellow – 500 m alert) ───────────────
        Rectangle {
            id: nfzProximityBanner
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: nfzWarningBanner.visible ? (nfzWarningBanner.y + nfzWarningBanner.height + 8) : 16
            width: nfzProximityText.implicitWidth + 52
            height: 50
            radius: 10
            color: "#E6181818"
            border.color: "#FFB800"
            border.width: 2
            z: 8900
            opacity: 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            // pulsing glow
            SequentialAnimation on border.width {
                running: nfzProximityBanner.visible
                loops: Animation.Infinite
                NumberAnimation { to: 3; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 2; duration: 600; easing.type: Easing.InOutSine }
            }

            Row {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    text: "⚠️"
                    font.pixelSize: 22
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        id: nfzProximityText
                        text: "Approaching No-Fly Zone"
                        color: "#FFD600"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Text {
                        id: nfzProximityDistText
                        text: ""
                        color: "#FFECB3"
                        font.pixelSize: 11
                    }
                }
            }

            Timer {
                id: nfzProximityBannerTimer
                interval: 5000
                repeat: false
                onTriggered: nfzProximityBanner.opacity = 0
            }
        }

        // ── NFZ SIDE PANEL ────────────────────────────────────────────────────
        Item {
            id: nfzPanel
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: 23; anchors.rightMargin: 10
            width:  nfzPanelExpanded ? 260 : 55
            height: nfzPanelExpanded ? Math.min(nfzListView.contentHeight + 56, 380) : 40
            z: 1100
            property bool nfzPanelExpanded: false
            Behavior on width  { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Rectangle {
                anchors.fill: parent; color: "#E0000000"; radius: 7
                border.color: nfzPanel.nfzPanelExpanded ? "#CC2222" : "#666666"; border.width: 1
                Rectangle {
                    id: nfzPanelHeader
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    height: 36; color: "transparent"; clip: true
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nfzPanel.nfzPanelExpanded = !nfzPanel.nfzPanelExpanded }
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Text { text: "🚫"; font.pixelSize: 20; color: "#FFFFFF"; anchors.verticalCenter: parent.verticalCenter }
                        Text { visible: nfzPanel.nfzPanelExpanded; text: "No-Fly Zones (" + ((typeof nfzManager !== 'undefined' && nfzManager) ? nfzManager.nfzCount : 0) + ")"; font.pixelSize: 11; font.bold: true; color: "#FF6666"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: nfzPanel.nfzPanelExpanded ? "▲" : "▼"; color: "#AAAAAA"; font.pixelSize: 11 }
                }
                ListView {
                    id: nfzListView
                    visible: nfzPanel.nfzPanelExpanded
                    anchors.top: nfzPanelHeader.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                    clip: true; spacing: 3
                    model: (typeof nfzManager !== 'undefined' && nfzManager) ? nfzManager.nfzZones : []
                    delegate: Rectangle {
                        width: nfzListView.width; height: nfzItemCol.implicitHeight + 10
                        color: "#20FFFFFF"; radius: 4; border.color: "#55FF0000"; border.width: 1
                        Column {
                            id: nfzItemCol; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 8; spacing: 2
                            Text { text: modelData ? (modelData.name || "Unknown") : ""; color: "#FFFFFF"; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight; width: parent.width - 8 }
                            Text { text: modelData ? (modelData.geometry_type + " · " + modelData.centroid_lat.toFixed(4) + ", " + modelData.centroid_lon.toFixed(4)) : ""; color: "#AAAAAA"; font.pixelSize: 9 }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData && mapLoader.item) { mapLoader.item.center = QtPositioning.coordinate(modelData.centroid_lat, modelData.centroid_lon); mapLoader.item.zoomLevel = 11 } } }
                    }
                }
            }
        }

        // ── NFZ BREACH BANNER ─────────────────────────────────────────────────
        Rectangle {
            id: nfzBreachBanner
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 8
            width: nfzBreachText.implicitWidth + 40; height: 40; radius: 8
            color: "#DD8B0000"; border.color: "#FF0000"; border.width: 2
            visible: false; z: 2100; opacity: _breachOpacity
            property real   _breachOpacity: 1.0
            property string breachedZone:   ""
            Connections {
                target: (typeof nfzManager !== 'undefined') ? nfzManager : null; enabled: target !== null
                function onDroneInNFZ(zoneName)  { nfzBreachBanner.breachedZone = zoneName; nfzBreachBanner.visible = true; nfzBreachAnim.restart() }
                function onDroneExitedNFZ()      { nfzBreachBanner.visible = false; nfzBreachAnim.stop() }
                function onNfzDataChanged()      { console.log("🚫 MAP: NFZ updated –", nfzManager ? nfzManager.nfzCount : 0, "zones") }
            }
            SequentialAnimation {
                id: nfzBreachAnim; loops: Animation.Infinite; running: false
                NumberAnimation { target: nfzBreachBanner; property: "_breachOpacity"; to: 0.35; duration: 450 }
                NumberAnimation { target: nfzBreachBanner; property: "_breachOpacity"; to: 1.0;  duration: 450 }
            }
            Row { anchors.centerIn: parent; spacing: 8
                Text { text: "🚨"; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                Text { id: nfzBreachText; text: "NFZ BREACH: " + nfzBreachBanner.breachedZone; color: "#FFFFFF"; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // ── DRONE INFO PANEL (top-left) ───────────────────────────────────────
        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 10
            width: 200; height: root.isDroneConnected && root.hasValidDroneLocation ? 120 : (root.isDroneConnected ? 60 : 40)
            color: "#1a1a1a"; opacity: 0.9; radius: 6
            border.color: root.isDroneConnected ? "#00bcd4" : "#404040"; border.width: 1; z: 500
            Behavior on height { NumberAnimation { duration: 200 } }
            Column { anchors.fill: parent; anchors.margins: 8; spacing: 4
                Text { text: root.isDroneConnected ? "Drone Connected" : "Drone Disconnected"; color: root.isDroneConnected ? "#00e676" : "#f44336"; font.bold: true; font.pixelSize: 15 }
                Text { visible: root.isDroneConnected && !root.hasValidDroneLocation; text: "⏳ Waiting for GPS..."; color: "#ffa726"; font.pixelSize: 12 }
                Column { visible: root.isDroneConnected && root.hasValidDroneLocation; spacing: 2
                    Text { text: "Position: " + root.currentLat.toFixed(6) + "°, " + root.currentLon.toFixed(6) + "°"; color: "#e0e0e0"; font.pixelSize: 11 }
                    Text { text: "Altitude: "  + root.currentAlt.toFixed(1)     + "m";  color: "#e0e0e0"; font.pixelSize: 11 }
                    Text { text: "Heading: "   + root.currentHeading.toFixed(1) + "°"; color: "#e0e0e0"; font.pixelSize: 11 }
                }
            }
        }

        // ── CURSOR / ZOOM INFO PANEL (bottom-left) ────────────────────────────
        Rectangle {
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 10
            width: 300; height: 50
            color: "#1a1a1a"; opacity: 0.9; radius: 6
            border.color: "#404040"; border.width: 1; z: 500
            Column { anchors.fill: parent; anchors.margins: 8; spacing: 4
                Text { id: cursorText; text: "Cursor: 0.000000°, 0.000000°"; color: "#e0e0e0"; font.pixelSize: 11 }
                Text {
                    property var activeMap: mapLoader.item
                    text: "Zoom: " + (activeMap ? Math.round(activeMap.zoomLevel) : "-") + " | " +
                          (activeMap && activeMap.activeMapType ? activeMap.activeMapType.name : "Loading...") +
                          " | " + root.selectedProvider.toUpperCase()
                    color: "#e0e0e0"; font.pixelSize: 11
                }
            }
        }

        // ── CURSOR TRACKER ────────────────────────────────────────────────────
        MouseArea {
            anchors.fill: parent; hoverEnabled: true
            propagateComposedEvents: true; acceptedButtons: Qt.NoButton; z: -1
            onPositionChanged: {
                if (mapLoader.item) {
                    var coord = mapLoader.item.toCoordinate(Qt.point(mouse.x, mouse.y))
                    if (coord.isValid) cursorText.text = "Cursor: " + coord.latitude.toFixed(6) + "°, " + coord.longitude.toFixed(6) + "°"
                }
            }
        }

        // ── MAP CONTROLS PANEL (right side) ───────────────────────────────────
        Rectangle {
            id: mapControlsPanel
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: 72; anchors.rightMargin: 10
            width: 55; height: 280
            color: "#1a1a1a"; opacity: 0.9; radius: 8
            border.color: "#404040"; border.width: 1; z: 500
            visible: root.showBuiltinControls
            Column { anchors.centerIn: parent; spacing: 10
                // Zoom In
                Rectangle { width: 40; height: 40; radius: 20; color: "#2a2a2a"; border.color: "#00bcd4"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "+"; color: "#00bcd4"; font.pixelSize: 20; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: root.zoomIn() }
                }
                // Zoom Out
                Rectangle { width: 40; height: 40; radius: 20; color: "#2a2a2a"; border.color: "#00bcd4"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "-"; color: "#00bcd4"; font.pixelSize: 20; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: root.zoomOut() }
                }
                // Center on Drone
                Rectangle { width: 40; height: 40; radius: 20; color: "#2a2a2a"; border.color: root.hasValidDroneLocation ? "#00e676" : "#404040"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "⌖"; color: root.hasValidDroneLocation ? "#00e676" : "#404040"; font.pixelSize: 20 }
                    MouseArea { anchors.fill: parent; enabled: root.hasValidDroneLocation; onClicked: root.centerOnDrone() }
                }
                // Cycle Map Type
                Rectangle { width: 40; height: 40; radius: 20; color: "#2a2a2a"; border.color: "#00bcd4"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "🗺"; color: "#00bcd4"; font.pixelSize: 16 }
                    MouseArea { anchors.fill: parent; onClicked: root.cycleMapType() }
                }
                // Provider Switcher
                Rectangle { width: 40; height: 40; radius: 20; color: "#2a2a2a"; border.color: providerSwitchInProgress ? "#ffa500" : "#00bcd4"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: providerSwitchInProgress ? "⏳" : "🌍"; color: "#00bcd4"; font.pixelSize: 16 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !providerSwitchInProgress; onClicked: { var p = root.cycleMapProvider(); console.log("🌐 Switched provider to:", p) } }
                }
                // Add Marker Mode Toggle (hidden from toolbar UI)
                Rectangle { visible: false; width: 40; height: 40; radius: 20; color: root.addMarkersMode ? "#ff4081" : "#2a2a2a"; border.color: "#ff4081"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "📍"; color: root.addMarkersMode ? "white" : "#ff4081"; font.pixelSize: 16 }
                    MouseArea { anchors.fill: parent; onClicked: { root.addMarkersMode = !root.addMarkersMode; console.log("📍 Waypoint mode:", root.addMarkersMode ? "ENABLED" : "DISABLED") } }
                }
                // Polygon Survey Mode Toggle (hidden from toolbar UI)
                Rectangle { visible: false; width: 40; height: 40; radius: 20; color: root.polygonSurveyMode ? "#ff9800" : "#2a2a2a"; border.color: "#ff9800"; border.width: 1; anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "⬡"; color: root.polygonSurveyMode ? "white" : "#ff9800"; font.pixelSize: 18 }
                    MouseArea { anchors.fill: parent; onClicked: { root.polygonSurveyMode = !root.polygonSurveyMode; console.log("⬡ Polygon mode:", root.polygonSurveyMode ? "ENABLED" : "DISABLED") } }
                }
            }
        }

        // ── ROUTE STATS OVERLAY (bottom-right) ───────────────────────────────
        Item {
            id: routeStatsOverlay
            anchors.bottom: parent.bottom; anchors.right: parent.right
            anchors.margins: 15; anchors.bottomMargin: 25
            width: 220; height: 160
            visible: markersModel.count > 0; z: 999
            Rectangle { anchors.fill: parent; color: "#121212"; opacity: 0.55; radius: 12; border.color: "#4e4c4c"; border.width: 1 }
            Column { anchors.fill: parent; anchors.margins: 12; spacing: 8
                Row { width: parent.width; spacing: 10
                    Text { text: "Waypoints:";  color: "#fafafa"; font.pixelSize: 12; width: 100; font.weight: Font.Medium }
                    Text { text: markersModel.count; color: "white"; font.bold: true; font.pixelSize: 12 }
                }
                Row { width: parent.width; spacing: 10
                    Text { text: "Total Dist:"; color: "#fcfbfb"; font.pixelSize: 12; width: 100; font.weight: Font.Medium }
                    Text { text: root.formatDistance(root.totalRouteDistance); color: "#00e676"; font.bold: true; font.pixelSize: 12 }
                }
                Row { width: parent.width; spacing: 10
                    Text { text: "Covered:";    color: "#ffffff"; font.pixelSize: 12; width: 100; font.weight: Font.Medium }
                    Text { text: root.formatDistance(root.distanceCovered); color: "#29b6f6"; font.bold: true; font.pixelSize: 12 }
                }
                Row { width: parent.width; spacing: 10
                    Text { text: "Remaining:";  color: "#fffdfd"; font.pixelSize: 12; width: 100; font.weight: Font.Medium }
                    Text { text: root.formatDistance(root.distanceRemaining); color: "#ff9800"; font.bold: true; font.pixelSize: 12 }
                }
                Rectangle { width: parent.width; height: 1; color: "#404040" }
                Row { spacing: 10; anchors.horizontalCenter: parent.horizontalCenter
                    Text { text: "Unit:"; color: "#fffcfc"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; font.weight: Font.Medium }
                    Rectangle { width: 60; height: 24; radius: 4; color: "#333"; border.color: "#555"
                        Text { anchors.centerIn: parent; text: root.distanceUnit.toUpperCase(); color: "white"; font.bold: true; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.distanceUnit = (root.distanceUnit === "km") ? "m" : "km" }
                    }
                }
            }
        }

    } // end outer Rectangle

    // =========================================================================
    // CANVASES OUTSIDE OUTER RECT
    // =========================================================================

    Canvas {
        id: actualPathCanvas; anchors.fill: parent; z: 101; visible: false
        property int pathLength: root.actualFlightPath.length
        property var  mapCenter: mapLoader.item ? mapLoader.item.center    : QtPositioning.coordinate(0,0)
        property int  mapZoom:   mapLoader.item ? mapLoader.item.zoomLevel : 2
        onPathLengthChanged: requestPaint(); onMapCenterChanged: requestPaint(); onMapZoomChanged: requestPaint()
        Connections { target: mapLoader.item; function onCenterChanged() { actualPathCanvas.requestPaint() } function onZoomLevelChanged() { actualPathCanvas.requestPaint() } }
        onPaint: {
            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
            if (!mapLoader.item || root.actualFlightPath.length < 2) return
            var pts = []
            for (var i = 0; i < root.actualFlightPath.length; i++) { var sp = mapLoader.item.fromCoordinate(QtPositioning.coordinate(root.actualFlightPath[i].lat, root.actualFlightPath[i].lng)); if (sp.x >= 0 && sp.y >= 0) pts.push(sp) }
            if (pts.length < 2) return
            ctx.save(); ctx.beginPath(); ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.lineWidth = 4; ctx.strokeStyle = "#00FF00"; ctx.shadowColor = "#00FF0080"; ctx.shadowBlur = 8
            ctx.moveTo(pts[0].x, pts[0].y); for (var k = 1; k < pts.length; k++) ctx.lineTo(pts[k].x, pts[k].y)
            ctx.stroke(); ctx.restore()
        }
    }

    Canvas {
        id: missionPathCanvas; anchors.fill: parent; z: 98
        visible: root.showUploadedPath && root.uploadedMissionPath.length > 0
        property int pathLength: root.uploadedMissionPath.length
        property var  mapCenter: mapLoader.item ? mapLoader.item.center    : QtPositioning.coordinate(0,0)
        property int  mapZoom:   mapLoader.item ? mapLoader.item.zoomLevel : 2
        onPathLengthChanged: requestPaint()
        onMapCenterChanged:  { if (visible && pathLength > 0) requestPaint() }
        onMapZoomChanged:    { if (visible && pathLength > 0) requestPaint() }
        onVisibleChanged:    { if (visible && pathLength > 0) requestPaint() }
        Connections { target: root; function onUploadedMissionPathChanged() { missionPathCanvas.requestPaint() } function onShowUploadedPathChanged() { if (root.showUploadedPath && root.uploadedMissionPath.length > 0) missionPathCanvas.requestPaint() } }
        Connections { target: mapLoader.item; function onCenterChanged() { if (missionPathCanvas.visible) missionPathCanvas.requestPaint() } function onZoomLevelChanged() { if (missionPathCanvas.visible) missionPathCanvas.requestPaint() } }
        onPaint: {
            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
            if (!root.showUploadedPath || !mapLoader.item || root.uploadedMissionPath.length < 2) return
            var pts = []
            for (var i = 0; i < root.uploadedMissionPath.length; i++) { var sp = mapLoader.item.fromCoordinate(QtPositioning.coordinate(root.uploadedMissionPath[i].lat, root.uploadedMissionPath[i].lng)); if (sp.x >= 0 && sp.y >= 0) pts.push(sp) }
            if (pts.length < 2) return
            ctx.save()
            ctx.beginPath(); ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.lineWidth = root.missionPathWidth; ctx.strokeStyle = root.missionPathColor; ctx.shadowColor = root.missionPathColor; ctx.shadowBlur = 12
            ctx.moveTo(pts[0].x, pts[0].y); for (var k = 1; k < pts.length; k++) ctx.lineTo(pts[k].x, pts[k].y)
            ctx.stroke(); ctx.shadowBlur = 0
            for (var j = 0; j < pts.length; j++) {
                var pt = pts[j]
                ctx.beginPath(); ctx.arc(pt.x, pt.y, 6, 0, Math.PI * 2); ctx.fillStyle = root.missionPathColor; ctx.fill()
                ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.stroke()
                ctx.fillStyle = "white"; ctx.font = "bold 10px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"
                ctx.fillText((j + 1).toString(), pt.x, pt.y)
            }
            ctx.restore()
        }
    }

    Canvas {
        id: droneTrailCanvas; anchors.fill: parent; z: 1999; visible: false
        property int pathLength: root.actualFlightPath.length
        property var  mapCenter: mapLoader.item ? mapLoader.item.center    : QtPositioning.coordinate(0,0)
        property int  mapZoom:   mapLoader.item ? mapLoader.item.zoomLevel : 2
        onPathLengthChanged: requestPaint(); onMapCenterChanged: requestPaint(); onMapZoomChanged: requestPaint()
        Connections { target: mapLoader.item; function onCenterChanged() { droneTrailCanvas.requestPaint() } function onZoomLevelChanged() { droneTrailCanvas.requestPaint() } }
        onPaint: {
            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
            if (!mapLoader.item || root.actualFlightPath.length < 2) return
            var pts = []
            for (var i = 0; i < root.actualFlightPath.length; i++) { var sp = mapLoader.item.fromCoordinate(QtPositioning.coordinate(root.actualFlightPath[i].lat, root.actualFlightPath[i].lng)); if (sp.x >= 0 && sp.y >= 0) pts.push(sp) }
            if (pts.length < 2) return
            ctx.save()
            for (var i = 0; i < pts.length - 1; i++) {
                var alpha = 0.3 + (i / (pts.length - 1)) * 0.7
                ctx.beginPath(); ctx.moveTo(pts[i].x, pts[i].y); ctx.lineTo(pts[i+1].x, pts[i+1].y)
                ctx.strokeStyle = "rgba(0,255,255," + alpha + ")"; ctx.lineWidth = 4
                ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.shadowColor = "rgba(0,255,255,0.8)"; ctx.shadowBlur = 8; ctx.stroke()
            }
            ctx.shadowBlur = 0
            if (pts.length > 0) { var s = pts[0]; ctx.beginPath(); ctx.arc(s.x, s.y, 8, 0, Math.PI * 2); ctx.fillStyle = "#00FF00"; ctx.fill(); ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.stroke(); ctx.fillStyle = "white"; ctx.font = "bold 10px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText("S", s.x, s.y) }
            ctx.restore()
        }
    }

    property bool showVideoOverlay: true

    // =========================================================================
    // VIDEO OVERLAY — Camera PiP Panel (from File 1)
    // =========================================================================
    Rectangle {
        id: videoOverlay
        visible: showVideoOverlay
        width:  Math.min(parent.width * 0.36, parent.width - 24)
        height: parent.height * 0.38
        anchors.right:   parent.right
        anchors.bottom:  parent.bottom
        anchors.margins: 12
        radius: 10
        z: 5000
        clip: true
        color: "#0E0E0E"
        border.color: "#2A82DA"
        border.width: 1.5
        layer.enabled: true

        property string activeTab: "video"

        // ─── HEADER ──────────────────────────────────────────────────────────
        Rectangle {
            id: overlayHeader
            height: 36; width: parent.width
            color: "#161616"; radius: 10
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: parent.width; height: parent.radius; color: parent.color }
            Row {
                anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 12; spacing: 8
                Text { text: "CAMERA SYSTEM"; color: "#D0D0D0"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.5; leftPadding: 4 }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                Rectangle {
                    width: 7; height: 7; radius: 4; color: "#00FF41"; anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.2; duration: 600 } NumberAnimation { to: 1.0; duration: 600 } }
                }
                Text { text: "LIVE"; color: "#00FF41"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.2 }
            }
            MouseArea { anchors.fill: parent; drag.target: videoOverlay; cursorShape: Qt.SizeAllCursor }
        }

        // ─── TAB BAR ─────────────────────────────────────────────────────────
        Rectangle {
            id: tabBar
            anchors.top: overlayHeader.bottom
            height: 38; width: parent.width
            color: "#111111"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2A82DA"; opacity: 0.4 }
            Row {
                anchors.centerIn: parent; spacing: 4
                Repeater {
                    model: [
                        { name: "Video",    tabId: "video"    },
                        { name: "Controls", tabId: "controls" },
                        { name: "Gimbal",   tabId: "gimbal"   },
                        { name: "Cameras",  tabId: "multi"    },
                        { name: "Stream",   tabId: "stream"   }
                    ]
                    Rectangle {
                        id: tabBtn
                        property bool isActive: videoOverlay.activeTab === modelData.tabId
                        width: tabLabel.implicitWidth + 18; height: 28; radius: 5
                        color: isActive ? "#2A82DA" : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: tabLabel; anchors.centerIn: parent; text: modelData.name
                            color: tabBtn.isActive ? "#FFFFFF" : "#888888"
                            font.pixelSize: 11; font.bold: tabBtn.isActive; font.letterSpacing: 0.5
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: videoOverlay.activeTab = modelData.tabId }
                    }
                }
            }
        }

        // ─── VIDEO SCREEN ─────────────────────────────────────────────────────
        Rectangle {
            id: videoScreen
            anchors.top: tabBar.bottom
            width: parent.width
            height: parent.height - 74   // header(36) + tabs(38)
            color: "#020608"; clip: true

            // RTSP stream frame
            Image {
                id: streamImage; anchors.fill: parent; z: 0
                fillMode: Image.PreserveAspectFit; cache: false; asynchronous: false
                visible: typeof cameraModel !== "undefined" && cameraModel.isStreaming
                source: ""; antialiasing: true
            }
            Timer {
                id: streamRefreshTimer; interval: 33; repeat: true
                running: typeof cameraModel !== "undefined" && cameraModel.isStreaming
                onTriggered: { if (streamImage.visible) { streamImage.source = ""; streamImage.source = "image://rtspframes/frame" } }
            }

            // Vignette
            Canvas {
                anchors.fill: parent; z: 1; opacity: 1.0
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    var grad = ctx.createRadialGradient(width/2, height/2, height*0.22, width/2, height/2, height*0.78)
                    grad.addColorStop(0, "rgba(0,0,0,0)"); grad.addColorStop(1, "rgba(0,0,0,0.72)")
                    ctx.fillStyle = grad; ctx.fillRect(0, 0, width, height)
                }
                Component.onCompleted: requestPaint()
            }

            // Scanlines
            Canvas {
                anchors.fill: parent; z: 2; opacity: 0.045
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#FFFFFF"; ctx.lineWidth = 1
                    for (var y = 0; y < height; y += 3) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke() }
                }
                Component.onCompleted: requestPaint()
            }

            // Animated sweep scan-line
            Rectangle {
                id: sweepLine; width: parent.width; height: 2; z: 3; opacity: 0.0; color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "transparent" }
                        GradientStop { position: 0.45; color: "transparent" }
                        GradientStop { position: 0.50; color: "#4042A0FF"  }
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1.0;  color: "transparent" }
                    }
                }
                SequentialAnimation {
                    running: true; loops: Animation.Infinite
                    NumberAnimation { target: sweepLine; property: "y"; from: 0; to: videoScreen.height; duration: 3200; easing.type: Easing.Linear }
                    PauseAnimation { duration: 800 }
                }
                onYChanged: opacity = (y > 0 && y < videoScreen.height) ? 0.9 : 0.0
            }

            // Corner brackets
            Canvas {
                anchors.fill: parent; z: 4; opacity: 0.85
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#2A82DA"; ctx.lineWidth = 2; ctx.shadowColor = "#2A82DA"; ctx.shadowBlur = 6
                    var L = 22, M = 12
                    ctx.beginPath(); ctx.moveTo(M, M+L); ctx.lineTo(M, M);          ctx.lineTo(M+L, M);          ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(width-M-L, M); ctx.lineTo(width-M, M); ctx.lineTo(width-M, M+L); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(M, height-M-L); ctx.lineTo(M, height-M); ctx.lineTo(M+L, height-M); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(width-M-L, height-M); ctx.lineTo(width-M, height-M); ctx.lineTo(width-M, height-M-L); ctx.stroke()
                    ctx.shadowBlur = 0
                }
                Component.onCompleted: requestPaint()
            }

            // Crosshair
            Canvas {
                anchors.fill: parent; z: 5; opacity: 0.55
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    var cx = width/2, cy = height/2
                    ctx.strokeStyle = "#2A82DA"; ctx.shadowColor = "#2A82DA"; ctx.shadowBlur = 5; ctx.lineWidth = 1.2
                    ctx.beginPath(); ctx.moveTo(cx-70, cy); ctx.lineTo(cx-16, cy); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(cx+16, cy); ctx.lineTo(cx+70, cy); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(cx, cy-55); ctx.lineTo(cx, cy-16); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(cx, cy+16); ctx.lineTo(cx, cy+55); ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy, 13, 0, Math.PI*2); ctx.stroke()
                    ctx.shadowBlur = 0; ctx.fillStyle = "#4A9AEA"; ctx.beginPath(); ctx.arc(cx, cy, 2.5, 0, Math.PI*2); ctx.fill()
                    ctx.shadowBlur = 3
                    var r = 13, t = 5
                    ctx.beginPath(); ctx.moveTo(cx, cy-r); ctx.lineTo(cx, cy-r-t); ctx.moveTo(cx, cy+r); ctx.lineTo(cx, cy+r+t); ctx.moveTo(cx-r, cy); ctx.lineTo(cx-r-t, cy); ctx.moveTo(cx+r, cy); ctx.lineTo(cx+r+t, cy); ctx.stroke()
                    ctx.shadowBlur = 0
                }
                Component.onCompleted: requestPaint()
            }

            // Top HUD Bar
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 10
                height: 22; color: "transparent"; z: 10
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Repeater {
                        model: [{ t: "1920×1080" }, { t: "30 FPS" }, { t: "CH 1 · RGB" }]
                        Rectangle {
                            width: lbl.implicitWidth + 10; height: 16; radius: 3; color: "#0D1A26"; border.color: "#1A4A70"; border.width: 1
                            Text { id: lbl; anchors.centerIn: parent; text: modelData.t; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; font.bold: true }
                        }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4; color: "#FF3B30"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.25; duration: 500 } NumberAnimation { to: 1.0; duration: 500 } }
                    }
                    Text { text: "00:00:00"; color: "#FF5F57"; font.pixelSize: 10; font.family: "Monospace"; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            // Bottom HUD Bar
            Rectangle {
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 10
                height: 24; color: "transparent"; z: 10
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Repeater {
                        model: [{ label: "ALT", value: "---  m" }, { label: "SPD", value: "---  m/s" }, { label: "HDG", value: "---  °" }]
                        Rectangle {
                            width: rowL.implicitWidth + 14; height: 18; radius: 3; color: "#07111B"; border.color: "#153048"; border.width: 1
                            Row { id: rowL; anchors.centerIn: parent; spacing: 4
                                Text { text: modelData.label; color: "#3A6A9A"; font.pixelSize: 8; font.family: "Monospace"; font.bold: true }
                                Text { text: modelData.value; color: "#5AADFF"; font.pixelSize: 8; font.family: "Monospace" }
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: zt.implicitWidth + 14; height: 18; radius: 3; color: "#07111B"; border.color: "#153048"; border.width: 1
                    Text { id: zt; anchors.centerIn: parent; text: "ZOOM  1.0×"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace" }
                }
            }

            // NO SIGNAL idle state
            Column {
                visible: !(typeof cameraModel !== "undefined" && cameraModel.isStreaming)
                anchors.centerIn: parent; spacing: 10; z: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; text: "📡"; font.pixelSize: 32; opacity: 0.18
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.30; duration: 900; easing.type: Easing.InOutSine } NumberAnimation { to: 0.10; duration: 900; easing.type: Easing.InOutSine } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; text: "NO  SIGNAL"; color: "#1C3A58"; font.pixelSize: 16; font.bold: true; font.letterSpacing: 6
                    SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.55; duration: 1100 } NumberAnimation { to: 1.0; duration: 1100 } }
                }
                Canvas {
                    width: 160; height: 6; anchors.horizontalCenter: parent.horizontalCenter
                    onPaint: { var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height); ctx.strokeStyle = "#1A3A5A"; ctx.lineWidth = 1; ctx.setLineDash([6, 5]); ctx.beginPath(); ctx.moveTo(0, 3); ctx.lineTo(width, 3); ctx.stroke() }
                    Component.onCompleted: requestPaint()
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Awaiting RTSP stream connection"; color: "#1A3A5A"; font.pixelSize: 9; font.letterSpacing: 0.8; font.family: "Monospace" }
            }
        }

        // ─── DYNAMIC CONTROL PANEL (expands below video screen on non-video tabs)
        Loader {
            id: controlPanelLoader
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: videoOverlay.activeTab !== "video" ? 70 : 0
            visible: height > 0; clip: true
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            sourceComponent: {
                if (videoOverlay.activeTab === "controls") return cameraControlsComp
                if (videoOverlay.activeTab === "gimbal")   return gimbalControlsComp
                if (videoOverlay.activeTab === "multi")    return multiCameraPanelComp
                if (videoOverlay.activeTab === "stream")   return streamPanelComp
                return null
            }
        }

        // ─── SUB-COMPONENTS ───────────────────────────────────────────────────
        Component {
            id: cameraControlsComp
            Rectangle {
                color: "#131313"; border.color: "#222222"; border.width: 1
                Row {
                    anchors.centerIn: parent; spacing: 10
                    Rectangle {
                        width: snapTxt.implicitWidth + 18; height: 28; radius: 6
                        color: snapMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: snapTxt; anchors.centerIn: parent; text: "📸 Snap"; color: "#CCCCCC"; font.pixelSize: 10 }
                        MouseArea { id: snapMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof cameraModel !== "undefined") cameraModel.takeSnapshot() }
                    }
                    Rectangle {
                        id: recBtn
                        property bool recording: (typeof cameraModel !== "undefined") && cameraModel.isRecording
                        width: recTxt.implicitWidth + 18; height: 28; radius: 6
                        color: recording ? "#3A0A0A" : (recMa.containsMouse ? "#252525" : "#1A1A1A")
                        border.color: recording ? "#FF3B30" : "#3A3A3A"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: recTxt; anchors.centerIn: parent; text: recBtn.recording ? "⏹ Stop" : "⏺ Rec"; color: recBtn.recording ? "#FF5F57" : "#CCCCCC"; font.pixelSize: 10 }
                        MouseArea { id: recMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (typeof cameraModel === "undefined") return; if (cameraModel.isRecording) cameraModel.stopRecording(); else cameraModel.startRecording() } }
                    }
                    Rectangle { width: 28; height: 28; radius: 6; color: ziMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1; Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: "＋"; color: "#CCCCCC"; font.pixelSize: 14 }
                        MouseArea { id: ziMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof cameraModel !== "undefined") cameraModel.zoomIn() }
                    }
                    Rectangle { width: 28; height: 28; radius: 6; color: zoMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1; Behavior on color { ColorAnimation { duration: 80 } }
                        Text { anchors.centerIn: parent; text: "－"; color: "#CCCCCC"; font.pixelSize: 14 }
                        MouseArea { id: zoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof cameraModel !== "undefined") cameraModel.zoomOut() }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: (typeof cameraModel !== "undefined") ? cameraModel.zoomLabel : "1×"; color: "#5AADFF"; font.pixelSize: 10; font.family: "Monospace" }
                    Rectangle { width: cntrTxt.implicitWidth + 18; height: 28; radius: 6; color: cntrMa.containsMouse ? "#252525" : "#1A1A1A"; border.color: "#3A3A3A"; border.width: 1; Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: cntrTxt; anchors.centerIn: parent; text: "⊙ Center"; color: "#CCCCCC"; font.pixelSize: 10 }
                        MouseArea { id: cntrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (typeof droneCommander !== "undefined") droneCommander.centerGimbal() }
                    }
                }
            }
        }

        Component {
            id: gimbalControlsComp
            Rectangle {
                color: "#131313"; border.color: "#222222"; border.width: 1
                property real gimbalPitch: 0.0
                property real gimbalYaw:   0.0
                property real gimbalRoll:  0.0
                function sendGimbal() { if (typeof droneCommander !== "undefined") droneCommander.setGimbalAngle(gimbalPitch, gimbalYaw, gimbalRoll) }
                Row {
                    anchors.centerIn: parent; spacing: 20
                    Column { spacing: 4
                        Text { text: "PITCH"; color: "#666"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Slider { id: pitchSlider; width: 100; from: -90; to: 30; value: 0; onValueChanged: { parent.parent.parent.gimbalPitch = value; parent.parent.parent.sendGimbal() } }
                        Text { text: Math.round(pitchSlider.value) + "°"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    Column { spacing: 4
                        Text { text: "YAW"; color: "#666"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Slider { id: yawSlider; width: 100; from: -180; to: 180; value: 0; onValueChanged: { parent.parent.parent.gimbalYaw = value; parent.parent.parent.sendGimbal() } }
                        Text { text: Math.round(yawSlider.value) + "°"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    Column { spacing: 4
                        Text { text: "ROLL"; color: "#666"; font.pixelSize: 9; font.letterSpacing: 1 }
                        Slider { id: rollSlider; width: 70; from: -30; to: 30; value: 0; onValueChanged: { parent.parent.parent.gimbalRoll = value; parent.parent.parent.sendGimbal() } }
                        Text { text: Math.round(rollSlider.value) + "°"; color: "#5AADFF"; font.pixelSize: 9; font.family: "Monospace"; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
        }

        Component {
            id: multiCameraPanelComp
            Rectangle {
                color: "#0D1117"; border.color: "#1E2A38"; border.width: 1
                property string selectedCam: (typeof cameraModel !== "undefined") ? cameraModel.activeCameraId : "cam1"
                Row {
                    anchors.centerIn: parent; spacing: 10
                    Repeater {
                        model: [{ label: "📷  Camera 1", camId: "cam1" }, { label: "📷  Camera 2", camId: "cam2" }, { label: "🌡  Thermal IR", camId: "thermal" }]
                        Rectangle {
                            id: camBtn
                            property bool isActive: parent.parent.parent.selectedCam === modelData.camId
                            width: camBtnLabel.implicitWidth + 20; height: 28; radius: 14
                            color: isActive ? "#1A4A80" : "#111A24"; border.color: isActive ? "#2A82DA" : "#243040"; border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { id: camBtnLabel; anchors.centerIn: parent; text: modelData.label; color: camBtn.isActive ? "#FFFFFF" : "#6A8FAA"; font.pixelSize: 10; font.bold: camBtn.isActive; Behavior on color { ColorAnimation { duration: 120 } } }
                            ToolTip.visible: hov.containsMouse; ToolTip.delay: 400
                            ToolTip.text: { if (modelData.camId === "cam1") return "Camera 1 (RGB)"; if (modelData.camId === "cam2") return "Camera 2 (RGB)"; return "Thermal IR" }
                            MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (typeof cameraModel !== "undefined") cameraModel.switchCamera(modelData.camId); camBtn.parent.parent.parent.selectedCam = modelData.camId } }
                        }
                    }
                }
            }
        }

        Component {
            id: streamPanelComp
            Rectangle {
                id: streamRoot; color: "#0D1117"; border.color: "#1E2A38"; border.width: 1
                property bool connected: (typeof cameraModel !== "undefined") && cameraModel.isStreaming
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Rectangle {
                        width: 220; height: 28; radius: 6; color: "#080F18"
                        border.color: streamRoot.connected ? "#00C853" : "#1A3A5A"; border.width: 1
                        TextInput {
                            id: streamUrlInput; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 8
                            text: ""; color: "#5AADFF"; font.pixelSize: 10; font.family: "Monospace"; clip: true; readOnly: streamRoot.connected
                            Text { visible: parent.text === ""; text: "rtsp://192.168.1.10:8554/stream"; color: "#2A4A6A"; font.pixelSize: 10; font.family: "Monospace"; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Rectangle {
                        width: streamBtnLabel.implicitWidth + 22; height: 28; radius: 6
                        color: streamBtnMa.containsMouse ? (streamRoot.connected ? "#3A0A0A" : "#1A3A22") : (streamRoot.connected ? "#2A0808" : "#0F2218")
                        border.color: streamRoot.connected ? "#FF3B30" : "#00C853"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { id: streamBtnLabel; anchors.centerIn: parent; text: streamRoot.connected ? "⏹  Disconnect" : "▶  Connect"; color: streamRoot.connected ? "#FF5F57" : "#00E676"; font.pixelSize: 10; font.bold: true; font.family: "Monospace" }
                        MouseArea { id: streamBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (typeof cameraModel === "undefined") return; if (cameraModel.isStreaming) cameraModel.disconnectStream(); else cameraModel.connectStream(streamUrlInput.text) } }
                    }
                }
            }
        }

    } // end videoOverlay Rectangle

    // =========================================================================
    // PROVIDER SELECTION MENU
    // =========================================================================
    Menu {
        id: providerMenu
        enter: Transition {}
        exit: Transition {}
        background: Rectangle {
            color: "#1a1a1a"
            border.color: "#00bcd4"
            border.width: 1
            radius: 6
            clip: true
        }
        MenuItem {
            text: "Google Maps"    + (root.selectedProvider === "google" ? " ●" : "")
            enabled: root.selectedProvider !== "google"
            onTriggered: root.switchMapProvider("google")
            ToolTip.visible: false
            background: Rectangle { color: parent.hovered ? "#00bcd4" : "#1a1a1a"; radius: 4 }
            contentItem: Text { text: parent.text; color: parent.enabled ? "#e0e0e0" : "#666666"; font.pixelSize: 13 }
        }
        MenuItem {
            text: "OpenStreetMap" + (root.selectedProvider === "osm"    ? " ●" : "")
            enabled: root.selectedProvider !== "osm"
            onTriggered: root.switchMapProvider("osm")
            ToolTip.visible: false
            background: Rectangle { color: parent.hovered ? "#00bcd4" : "#1a1a1a"; radius: 4 }
            contentItem: Text { text: parent.text; color: parent.enabled ? "#e0e0e0" : "#666666"; font.pixelSize: 13 }
        }
        MenuItem {
            text: "Bing Maps"     + (root.selectedProvider === "bing"   ? " ●" : "")
            enabled: root.selectedProvider !== "bing"
            onTriggered: root.switchMapProvider("bing")
            ToolTip.visible: false
            background: Rectangle { color: parent.hovered ? "#00bcd4" : "#1a1a1a"; radius: 4 }
            contentItem: Text { text: parent.text; color: parent.enabled ? "#e0e0e0" : "#666666"; font.pixelSize: 13 }
        }
    }

    // =========================================================================
    // PUBLIC API FUNCTIONS
    // =========================================================================

    function updateRoutePath() { if (typeof routeCanvas !== 'undefined') routeCanvas.requestPaint() }

    // =========================================================================
    // NFZ RESTRICTION HELPERS
    // =========================================================================

    // Returns { inside: bool, zoneName: string }
    function isPointInNFZ(lat, lng) {
        if (typeof nfzManager === 'undefined' || !nfzManager || !nfzManager.nfzZones)
            return { inside: false, zoneName: "" }
        var zones = nfzManager.nfzZones
        for (var i = 0; i < zones.length; i++) {
            var z = zones[i]
            if (!z) continue
            var cLat = z.centroid_lat || 0
            var cLon = z.centroid_lon || 0
            var radius = z.radius_m   || 5000
            var dist = calculateDistance(lat, lng, cLat, cLon)
            if (dist < radius)
                return { inside: true, zoneName: z.name || ("NFZ Zone " + (i + 1)) }
        }
        return { inside: false, zoneName: "" }
    }

    // Show the red warning banner for 3 seconds
    function showNFZWarning(message) {
        nfzWarningText.text = message || "⛔ Waypoint blocked: No-Fly Zone"
        nfzWarningBanner.opacity = 1
        nfzWarningTimer.restart()
        console.warn("🚫 NFZ BLOCK:", message)
    }

    // Returns { distance: meters_to_boundary, zoneName: string }
    // distance = distToCenter - radius  (negative means inside, we clamp to 0)
    function getNFZProximity(lat, lng) {
        if (typeof nfzManager === 'undefined' || !nfzManager || !nfzManager.nfzZones)
            return { distance: -1, zoneName: "" }
        var zones   = nfzManager.nfzZones
        var minDist = 999999999
        var minName = ""
        for (var i = 0; i < zones.length; i++) {
            var z = zones[i]
            if (!z) continue
            var cLat   = z.centroid_lat || 0
            var cLon   = z.centroid_lon || 0
            var radius = z.radius_m     || 5000
            var distToCenter = calculateDistance(lat, lng, cLat, cLon)
            var distToBoundary = distToCenter - radius   // negative = inside NFZ
            if (distToBoundary < minDist) {
                minDist = distToBoundary
                minName = z.name || ("NFZ Zone " + (i + 1))
            }
        }
        return { distance: minDist, zoneName: minName }
    }

    // Show the yellow 500 m proximity warning (stays until drone moves away)
    function showNFZProximityWarning(result) {
        var dist = result.distance
        var name = result.zoneName
        nfzProximityText.text    = "⚠️  Approaching: " + name
        nfzProximityDistText.text = dist > 0
            ? "Distance to boundary: " + dist.toFixed(0) + " m"
            : "⛔ Inside No-Fly Zone!"
        nfzProximityBanner.opacity = 1
        nfzProximityBannerTimer.restart()
        console.warn("⚠️ NFZ PROXIMITY:", name, "dist=", dist.toFixed(0), "m")
    }

    function addMarker(lat, lng, altitude, speed, commandType) {
        markersModel.append({ lat: lat, lng: lng, altitude: altitude || 10, speed: speed || 5, commandType: commandType || "waypoint" })
        markers.push({ lat: lat, lng: lng, altitude: altitude || 10, speed: speed || 5, commandType: commandType || "waypoint" })
        markersChanged(); markerAdded(lat, lng)
    }

    function deleteMarker(index) {
        if (index >= 0 && index < markersModel.count) {
            markersModel.remove(index); markers.splice(index, 1)
            markersChanged(); markerDeleted(index)
        }
    }

    function centerOnDrone() {
        if (root.hasValidDroneLocation && mapLoader.item) {
            mapLoader.item.center    = QtPositioning.coordinate(root.currentLat, root.currentLon)
            mapLoader.item.zoomLevel = 15
        }
    }

    function zoomIn()  { if (mapLoader.item) mapLoader.item.zoomLevel = Math.min(mapLoader.item.zoomLevel + 1, mapLoader.item.maximumZoomLevel) }
    function zoomOut() { if (mapLoader.item) mapLoader.item.zoomLevel = Math.max(mapLoader.item.zoomLevel - 1, mapLoader.item.minimumZoomLevel) }

    function switchMapProvider(providerName) {
        if (providerSwitchInProgress || providerName === selectedProvider) return
        console.log("🔄 Switching to", providerName)
        providerSwitchInProgress = true
        if (mapLoader.item) {
            pendingCenter = mapLoader.item.center
            pendingZoom   = mapLoader.item.zoomLevel
            for (var i = 0; i < mapLoader.item.supportedMapTypes.length; i++) {
                if (mapLoader.item.activeMapType === mapLoader.item.supportedMapTypes[i]) { pendingMapTypeIndex = i; break }
            }
        }
        selectedProvider = providerName
        reloadTimer.start()
    }

    function cycleMapType() {
        if (!mapLoader.item || mapLoader.item.supportedMapTypes.length === 0) return "Map not ready"
        var types = mapLoader.item.supportedMapTypes
        var ci = -1
        for (var i = 0; i < types.length; i++) { if (mapLoader.item.activeMapType === types[i]) { ci = i; break } }
        mapLoader.item.activeMapType = types[(ci + 1) % types.length]
        return mapLoader.item.activeMapType.name
    }

    function cycleMapProvider() {
        var providers = ["google", "bing", "osm"]
        var next = providers[(providers.indexOf(selectedProvider) + 1) % providers.length]
        switchMapProvider(next)
        return { google: "Google Maps", bing: "Bing Maps", osm: "OpenStreetMap" }[next] || next
    }

    function syncMarkersArrayFromModel() {
        var u = []
        for (var i = 0; i < markersModel.count; i++) {
            var it = markersModel.get(i)
            u.push({ lat: it.lat, lng: it.lng, altitude: it.altitude, speed: it.speed, commandType: it.commandType })
        }
        markers = u
    }

    function updateMarkerAltitude(index, altitude)    { if (index >= 0 && index < markersModel.count) { markersModel.setProperty(index, "altitude", altitude);    syncMarkersArrayFromModel(); markersChanged() } }
    function updateMarkerSpeed(index, speed)          { if (index >= 0 && index < markersModel.count) { markersModel.setProperty(index, "speed", speed);          syncMarkersArrayFromModel(); markersChanged() } }
    function updateMarkerCommand(index, commandType)  {
        if (index >= 0 && index < markersModel.count) {
            markersModel.setProperty(index, "commandType", commandType)
            if (index < markers.length) markers[index].commandType = commandType
            syncMarkersArrayFromModel(); markersChanged()
        }
    }
    function updateMarkerPosition(index, lat, lng) {
        if (index >= 0 && index < markersModel.count) {
            markersModel.setProperty(index, "lat", lat); markersModel.setProperty(index, "lng", lng)
            syncMarkersArrayFromModel(); markersChanged(); markerMoved(index)
        }
    }

    function getAllMarkers()  { return markers }
    function getMarkersJSON() { return JSON.stringify(markers) }

    function clearAllMarkers() {
        markersModel.clear(); markers = []
        polygonCorners = []; polygonCornersChanged()
        // Also clear the blue mission-path line drawn after Send Waypoints and
        // the green actual-flight-path line — otherwise they linger on the map.
        clearUploadedMissionPath()
        clearActualPath()
        markersChanged()
    }

    // Replace the local markers with a new set without clearing actual/uploaded paths
    function setMarkersOnly(newMarkers) {
        markersModel.clear()
        markers = []
        for (var i = 0; i < newMarkers.length; i++) {
            var m = newMarkers[i]
            markersModel.append({
                lat: m.lat, 
                lng: m.lng, 
                altitude: m.altitude || 10, 
                speed: m.speed || 5, 
                commandType: m.commandType || "waypoint"
            })
            markers.push({
                lat: m.lat, lng: m.lng, 
                altitude: m.altitude || 10, 
                speed: m.speed || 5, 
                commandType: m.commandType || "waypoint"
            })
        }
        markersChanged()
    }


    function clearPolygon() { polygonCorners = []; polygonCornersChanged(); polygonCanvas.requestPaint() }

    function startMissionTracking() {
        missionWaypoints = []
        for (var i = 0; i < markersModel.count; i++) { var wp = markersModel.get(i); missionWaypoints.push({ lat: wp.lat, lng: wp.lng, altitude: wp.altitude }) }
        actualFlightPath = []; currentWaypointIndex = 0; missionActive = true; pathRecordTimer.start()
        console.log("mavlink: Mission tracking started")
    }

    function stopMissionTracking() { missionActive = false; currentWaypointIndex = -1; pathRecordTimer.stop(); console.log("mavlink: Mission tracking stopped") }
    function clearActualPath()     { actualFlightPath = []; actualPathCanvas.requestPaint() }

    function setUploadedMissionPath(waypoints) {
        uploadedMissionPath = []
        for (var i = 0; i < waypoints.length; i++) {
            var wp = waypoints[i]
            uploadedMissionPath.push({ lat: wp.lat || wp.x || 0, lng: wp.lng || wp.y || 0, altitude: wp.altitude || wp.z || 0 })
        }
        showUploadedPath = true; missionPathCanvas.requestPaint()
    }

    function clearUploadedMissionPath() { uploadedMissionPath = []; showUploadedPath = false; missionPathCanvas.requestPaint() }

    function checkWaypointProgress() {
        if (currentWaypointIndex < 0 || currentWaypointIndex >= markersModel.count) return
        var tw = markersModel.get(currentWaypointIndex)
        if (calculateDistance(currentLat, currentLon, tw.lat, tw.lng) < 3) {
            currentWaypointIndex++
            if (currentWaypointIndex >= markersModel.count) { missionActive = false; currentWaypointIndex = -1 }
        }
    }

    // =========================================================================
    // DISTANCE HELPERS
    // =========================================================================

    function calculateDistance(lat1, lon1, lat2, lon2) {
        var R = 6371e3
        var phi1 = lat1 * Math.PI / 180, phi2 = lat2 * Math.PI / 180
        var dPhi = (lat2 - lat1) * Math.PI / 180, dLam = (lon2 - lon1) * Math.PI / 180
        var a = Math.sin(dPhi/2)*Math.sin(dPhi/2) + Math.cos(phi1)*Math.cos(phi2)*Math.sin(dLam/2)*Math.sin(dLam/2)
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }

    function formatDistance(meters) {
        return distanceUnit === "km" ? (meters / 1000).toFixed(2) + " km" : meters.toFixed(0) + " m"
    }

    function distToSegmentSquared(p, v, w) {
        var l2 = (v.x-w.x)*(v.x-w.x) + (v.y-w.y)*(v.y-w.y)
        if (l2 === 0) return (p.x-v.x)*(p.x-v.x) + (p.y-v.y)*(p.y-v.y)
        var t = Math.max(0, Math.min(1, ((p.x-v.x)*(w.x-v.x) + (p.y-v.y)*(w.y-v.y)) / l2))
        return (p.x-v.x-t*(w.x-v.x))*(p.x-v.x-t*(w.x-v.x)) + (p.y-v.y-t*(w.y-v.y))*(p.y-v.y-t*(w.y-v.y))
    }

    function updateTotalDistance() {
        var dist = 0
        for (var i = 0; i < markersModel.count - 1; i++) {
            var p1 = markersModel.get(i), p2 = markersModel.get(i+1)
            dist += calculateDistance(p1.lat, p1.lng, p2.lat, p2.lng)
        }
        totalRouteDistance = dist
    }

    function updateDistanceCovered() {
        if (!isDroneConnected || !hasValidDroneLocation || markersModel.count < 2) { distanceCovered = 0; return }
        var minDist = 99999999, activeIdx = 0
        var dp = { x: currentLat, y: currentLon }
        for (var i = 0; i < markersModel.count - 1; i++) {
            var p1 = markersModel.get(i), p2 = markersModel.get(i+1)
            var d2 = distToSegmentSquared(dp, { x: p1.lat, y: p1.lng }, { x: p2.lat, y: p2.lng })
            if (d2 < minDist) { minDist = d2; activeIdx = i }
        }
        var covered = 0
        for (var j = 0; j < activeIdx; j++) { var m1 = markersModel.get(j), m2 = markersModel.get(j+1); covered += calculateDistance(m1.lat, m1.lng, m2.lat, m2.lng) }
        var s1 = markersModel.get(activeIdx), s2 = markersModel.get(activeIdx+1)
        covered += Math.min(calculateDistance(s1.lat, s1.lng, s2.lat, s2.lng), calculateDistance(s1.lat, s1.lng, currentLat, currentLon))
        distanceCovered = covered
    }

    // =========================================================================
    // SURVEY PATTERN GENERATION (all 5 patterns: horizontal, vertical,
    //   crosshatch [File 1+2], rectangle, circle [File 2 additions])
    // =========================================================================
    function generateSurveyPattern() {
        if (polygonCorners.length < 3) { console.log("❌ Need at least 3 corners"); return }
        console.log("🛰️ GENERATING SURVEY GRID - Pattern:", surveyPattern)

        var minLat = 999, maxLat = -999, minLon = 999, maxLon = -999
        for (var i = 0; i < polygonCorners.length; i++) {
            if (polygonCorners[i].lat < minLat) minLat = polygonCorners[i].lat
            if (polygonCorners[i].lat > maxLat) maxLat = polygonCorners[i].lat
            if (polygonCorners[i].lng < minLon) minLon = polygonCorners[i].lng
            if (polygonCorners[i].lng > maxLon) maxLon = polygonCorners[i].lng
        }
        var centerLat = (minLat + maxLat) / 2, centerLon = (minLon + maxLon) / 2
        var latToM = 111320, lonToM = 111320 * Math.cos(centerLat * Math.PI / 180)
        var gsdWidth = (6.17 * surveyAltitude) / 4.0
        var lineSpacing = gsdWidth * (1 - surveySidelap / 100)

        function latLonToXY(lat, lon) { return { x: (lon - centerLon) * lonToM, y: (lat - centerLat) * latToM } }
        function xyToLatLon(x, y)     { return { lat: centerLat + y / latToM, lng: centerLon + x / lonToM } }
        function rotatePoint(x, y, a) { var c = Math.cos(a), s = Math.sin(a); return { x: x*c - y*s, y: x*s + y*c } }
        function linePolyIntersect(y, poly) {
            var xs = []
            for (var i = 0; i < poly.length; i++) {
                var p1 = poly[i], p2 = poly[(i+1) % poly.length]
                if ((p1.y <= y && p2.y > y) || (p2.y <= y && p1.y > y)) xs.push(p1.x + (y - p1.y) * (p2.x - p1.x) / (p2.y - p1.y))
            }
            xs.sort(function(a,b) { return a - b }); return xs
        }

        var polygonXY = []
        for (var p = 0; p < polygonCorners.length; p++) polygonXY.push(latLonToXY(polygonCorners[p].lat, polygonCorners[p].lng))

        var surveyWaypoints = []

        function generateSweep(angleOffset) {
            var ar = angleOffset * Math.PI / 180
            var rp = []
            for (var r = 0; r < polygonXY.length; r++) rp.push(rotatePoint(polygonXY[r].x, polygonXY[r].y, -ar))
            var mnX=999999, mxX=-999999, mnY=999999, mxY=-999999
            for (var b = 0; b < rp.length; b++) { if (rp[b].x < mnX) mnX = rp[b].x; if (rp[b].x > mxX) mxX = rp[b].x; if (rp[b].y < mnY) mnY = rp[b].y; if (rp[b].y > mxY) mxY = rp[b].y }
            var ltr = true
            for (var l = 0; ; l++) {
                var y = mnY + l * lineSpacing; if (y > mxY) break
                var xi = linePolyIntersect(y, rp)
                if (xi.length >= 2) {
                    var sx = ltr ? xi[0] : xi[xi.length-1], ex = ltr ? xi[xi.length-1] : xi[0]
                    var s = rotatePoint(sx, y, ar), e = rotatePoint(ex, y, ar)
                    surveyWaypoints.push(xyToLatLon(s.x, s.y)); surveyWaypoints.push(xyToLatLon(e.x, e.y))
                    ltr = !ltr
                }
            }
        }

        if (surveyPattern === "horizontal") {
            generateSweep(surveyAngle)
        } else if (surveyPattern === "vertical") {
            generateSweep(surveyAngle + 90)
        } else if (surveyPattern === "crosshatch") {
            generateSweep(surveyAngle); generateSweep(surveyAngle + 90)
        } else if (surveyPattern === "rectangle") {
            var mnX=999999, mxX=-999999, mnY=999999, mxY=-999999
            for (var i = 0; i < polygonXY.length; i++) { if (polygonXY[i].x < mnX) mnX = polygonXY[i].x; if (polygonXY[i].x > mxX) mxX = polygonXY[i].x; if (polygonXY[i].y < mnY) mnY = polygonXY[i].y; if (polygonXY[i].y > mxY) mxY = polygonXY[i].y }
            var corners = [{ x: mnX, y: mnY }, { x: mxX, y: mnY }, { x: mxX, y: mxY }, { x: mnX, y: mxY }, { x: mnX, y: mnY }]
            for (var c = 0; c < corners.length; c++) surveyWaypoints.push(xyToLatLon(corners[c].x, corners[c].y))
        } else if (surveyPattern === "circle") {
            var cx = 0, cy = 0
            for (var i = 0; i < polygonXY.length; i++) { cx += polygonXY[i].x; cy += polygonXY[i].y }
            cx /= polygonXY.length; cy /= polygonXY.length
            var radius = 0
            for (var i = 0; i < polygonXY.length; i++) { var dx = polygonXY[i].x - cx, dy = polygonXY[i].y - cy; radius += Math.sqrt(dx*dx + dy*dy) }
            radius /= polygonXY.length
            for (var i = 0; i <= 36; i++) { var angle = (i / 36) * 2 * Math.PI; surveyWaypoints.push(xyToLatLon(cx + radius * Math.cos(angle), cy + radius * Math.sin(angle))) }
        }

        console.log("✅ Generated", surveyWaypoints.length, "waypoints")
        clearAllMarkers()
        for (var w = 0; w < surveyWaypoints.length; w++) addMarker(surveyWaypoints[w].lat, surveyWaypoints[w].lng, surveyAltitude, surveySpeed, "survey_waypoint")
        polygonCanvas.requestPaint()
    }

    // =========================================================================
    // LEGACY / COMPATIBILITY SHIM
    // =========================================================================
    function addMarkerJS(lat, lon, altitude, speed, commandType) { addMarker(lat, lon, altitude, speed, commandType) }
    function deleteMarkerJS(index)  { deleteMarker(index) }
    function centerOnDroneJS()      { centerOnDrone() }
    function zoomInJS()             { zoomIn() }
    function zoomOutJS()            { zoomOut() }

    function runJavaScript(code, callback) {
        console.warn("⚠️ LEGACY API:", code.substring(0, 50))
        try {
            var altMatch   = code.match(/markers\[(\d+)\]\.altitude\s*=\s*(\d+\.?\d*)/)
            var speedMatch = code.match(/markers\[(\d+)\]\.speed\s*=\s*(\d+\.?\d*)/)
            if (altMatch)   { updateMarkerAltitude(parseInt(altMatch[1]),   parseFloat(altMatch[2]));   if (callback) callback(true); return }
            if (speedMatch) { updateMarkerSpeed(parseInt(speedMatch[1]),     parseFloat(speedMatch[2])); if (callback) callback(true); return }
            if (code.indexOf("getAllMarkers") !== -1) { if (callback) callback(getMarkersJSON()); return }
            if (code === "markers.length")            { if (callback) callback(markers.length); return }
        } catch (e) { console.error("❌ Legacy JS error:", e.message); if (callback) callback(null) }
    }
}

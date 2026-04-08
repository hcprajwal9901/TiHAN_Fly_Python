import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.10
import QtQuick.Window 2.15
import QtQuick.Layouts 1.0
import "."

ApplicationWindow {
    id: mainWindow
    visible: true
    visibility: Window.Maximized

    width: Math.min(Screen.width * 0.95, 1920)
    height: Math.min(Screen.height * 0.95, 1080)

    minimumWidth: 1280
    minimumHeight: 720

    title: "TiHAN FLY - Ground Control Station (SECURE)"
    color: "#121212"

    // Global Font
    font.family: "Consolas"

    flags: Qt.Window

    // ============================================================
    // Screen Tools - QGC Style
    // ============================================================
    QtObject {
        id: screenTools

        readonly property real dpiScale: Math.max(1.0, Math.min(Screen.pixelDensity / 160, 2.0))

        readonly property real defaultFontPixelHeight: 14 * dpiScale
        readonly property real defaultFontPixelWidth: defaultFontPixelHeight * 0.55

        readonly property real smallFontPointSize:  defaultFontPixelHeight * 0.75
        readonly property real mediumFontPointSize: defaultFontPixelHeight * 0.85
        readonly property real largeFontPointSize:  defaultFontPixelHeight

        readonly property real toolbarHeight:   defaultFontPixelHeight * 3
        readonly property real defaultSpacing:  defaultFontPixelHeight * 0.5
        readonly property real smallSpacing:    defaultFontPixelHeight * 0.25
        readonly property real largeSpacing:    defaultFontPixelHeight

        readonly property real defaultMargins: defaultFontPixelHeight * 0.5
        readonly property real smallMargins:   defaultFontPixelHeight * 0.25

        readonly property real minButtonWidth:  defaultFontPixelWidth  * 10
        readonly property real minButtonHeight: defaultFontPixelHeight * 2

        readonly property real defaultRadius:     defaultFontPixelHeight * 0.5
        readonly property real defaultBorderWidth: 2
    }

    // ============================================================
    // Global Properties
    // ============================================================
    property var mapViewInstance:            mainMapView
    property var navigationControlsInstance: null

    // Security properties
    property string sessionToken:        ""
    property bool   isAuthenticated:     false
    property int    failedLoginAttempts: 0

    // Theme colors
    readonly property color primaryColor:   "#ffffff"
    readonly property color secondaryColor: "#f8f9fa"
    readonly property color accentColor:    "#0066cc"
    readonly property color successColor:   "#28a745"
    readonly property color warningColor:   "#ffc107"
    readonly property color errorColor:     "#dc3545"
    readonly property color textPrimary:    "#212529"
    readonly property color textSecondary:  "#6c757d"
    readonly property color borderColor:    "#dee2e6"

    // Sidebar properties
    property bool sidebarVisible: true
    readonly property real sidebarWidthOpen: Math.min(
        mainWindow.width * 0.38,
        screenTools.defaultFontPixelWidth * 46
    )
    readonly property real sidebarWidthClosed: screenTools.defaultFontPixelHeight * 2.5

    // ============================================================
    // TELEMETRY PROPERTIES - Bound to droneModel
    // ============================================================
    property real currentAltitude:      droneModel.isConnected && droneModel.telemetry.alt              !== undefined ? droneModel.telemetry.alt              : 0.0
    property real currentGroundSpeed:   droneModel.isConnected && droneModel.telemetry.groundspeed       !== undefined ? droneModel.telemetry.groundspeed       : 0.0
    property real currentYaw:           droneModel.isConnected && droneModel.telemetry.yaw               !== undefined ? droneModel.telemetry.yaw               : 0.0
    property real currentPitch:         droneModel.isConnected && droneModel.telemetry.pitch             !== undefined ? droneModel.telemetry.pitch             : 0.0
    property real currentRoll:          droneModel.isConnected && droneModel.telemetry.roll              !== undefined ? droneModel.telemetry.roll              : 0.0
    property real currentVerticalSpeed: droneModel.isConnected && droneModel.telemetry.climb             !== undefined ? droneModel.telemetry.climb             : 0.0
    property real currentDistToWP:      droneModel.isConnected && droneModel.telemetry.wp_dist           !== undefined ? droneModel.telemetry.wp_dist           : 0.0
    property real currentDistToMAV:     droneModel.isConnected && droneModel.telemetry.distance_to_home  !== undefined ? droneModel.telemetry.distance_to_home  : 0.0

    property var parametersWindowInstance:       null
    property var navigationControlsWindowInstance: null
    property var flightModeWindowInstance:       null

    // ============================================================
    // Font Loaders
    // ============================================================
    FontLoader { id: tamilFont;   source: "fonts/NotoSansTamil-Regular.ttf" }
    FontLoader { id: hindiFont;   source: "fonts/NotoSansDevanagari-Regular.ttf" }
    FontLoader { id: teluguFont;  source: "fonts/NotoSansTelugu-Regular.ttf" }

    // ============================================================
    // Language
    // ============================================================
    LanguageManager { id: languageManager }

    Translator {
        id: translator
        languageManager: languageManager
    }

    // ============================================================
    // Telemetry Connections
    // ============================================================
    Connections {
        target: droneModel
        enabled: droneModel !== null && droneModel !== undefined

        function onTelemetryChanged() {
            // console.log("📊 Telemetry - Alt:", currentAltitude.toFixed(2),
            //            "Speed:", currentGroundSpeed.toFixed(2),
            //            "Yaw:", currentYaw.toFixed(1))
        }

        function onIsConnectedChanged() {
            if (droneModel.isConnected) {
                console.log("✅ Drone connected - HUD should start updating")
            } else {
                console.log("❌ Drone disconnected")
            }
        }
    }

    Connections {
        target: languageManager
        enabled: true

        function onCurrentLanguageChanged() {
            Qt.callLater(function() {
                saveLanguagePreference(languageManager.currentLanguage)
                updateLanguageForAllComponents()
            })
        }
    }

    // ============================================================
    // Security Manager Connections
    // ============================================================
    Connections {
        target: typeof securityManager !== 'undefined' ? securityManager : null
        enabled: target !== null

        function onSecurityAlert(message, severity) {
            console.log("🔒 SECURITY ALERT [" + severity + "]: " + message)
            Qt.callLater(function() { showSecurityNotification(message, severity) })
        }

        function onAuthenticationFailed(reason) {
            console.log("❌ Authentication failed: " + reason)
            failedLoginAttempts++
            if (failedLoginAttempts >= 3)
                showSecurityNotification("Too many failed attempts. Access blocked.", "critical")
        }

        function onSessionExpired() {
            console.log("⏰ Session expired")
            isAuthenticated = false
            sessionToken    = ""
            showSecurityNotification("Session expired. Please reconnect.", "warning")
        }

        function onUnauthorizedAccess(action) {
            console.log("⚠️ Unauthorized access attempt: " + action)
            Qt.callLater(function() {
                showSecurityNotification("Unauthorized action blocked: " + action, "error")
            })
        }
    }

    // ============================================================
    // Window Loaders
    // ============================================================
    Loader {
        id: copyrightWindowLoader
        source: ""
        asynchronous: true

        function showCopyrightWindow() {
            if (item === null) source = "CopyrightWindow.qml"
            if (item !== null) { item.show(); item.raise(); item.requestActivate() }
        }
    }

    Loader {
        id: feedbackDialogLoader
        active: false
        asynchronous: true
        sourceComponent: Component {
            FeedbackDialog { onClosed: feedbackDialogLoader.active = false }
        }
    }

    // ============================================================
    // Global DataFlash Log Windows — loaded on demand to prevent
    // OpenGL context creation during startup (causes access violation)
    // ============================================================
    property var globalLogDownloaderWindow: null
    property var globalLogBrowserWindow:    null

    Loader {
        id: globalLogDownloaderWindowLoader
        active: false
        source: "LogDownloaderWindow.qml"
        onLoaded: {
            globalLogDownloaderWindow = item
            item.requestOpenLog.connect(function(path) {
                ensureLogBrowser()
                globalLogBrowserWindow.loadExternalLog(path)
                globalLogBrowserWindow.show()
                globalLogBrowserWindow.requestActivate()
            })
        }
    }

    Loader {
        id: globalLogBrowserWindowLoader
        active: false
        source: "LogBrowser.qml"
        onLoaded: {
            globalLogBrowserWindow = item
        }
    }

    function ensureLogDownloader() {
        if (!globalLogDownloaderWindowLoader.active)
            globalLogDownloaderWindowLoader.active = true
    }

    function ensureLogBrowser() {
        if (!globalLogBrowserWindowLoader.active)
            globalLogBrowserWindowLoader.active = true
    }

    // ============================================================
    // Security Notification Dialog
    // ============================================================
    Popup {
        id: securityNotificationDialog
        modal: true
        focus: true
        x: Math.round((mainWindow.width - width) * 0.5)
        y: screenTools.toolbarHeight + screenTools.defaultFontPixelHeight
        width: mainWindow.width * 0.35
        height: securityDialogColumn.height + (screenTools.defaultMargins * 4)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property string alertMessage:  ""
        property string alertSeverity: "info"

        background: Rectangle {
            color: "#ffffff"
            radius: screenTools.defaultRadius
            border.color: borderColor
            border.width: screenTools.defaultBorderWidth
            layer.enabled: true
            layer.effect: DropShadow {
                horizontalOffset: 0; verticalOffset: 4
                radius: 12; samples: 25; color: "#40000000"
            }
        }

        Column {
            id: securityDialogColumn
            anchors.centerIn: parent
            width: parent.width - (screenTools.defaultMargins * 4)
            spacing: screenTools.defaultSpacing

            Text {
                text: "Security Alert"
                font.pixelSize: screenTools.largeFontPointSize
                font.weight: Font.Bold
                color: textPrimary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                spacing: screenTools.defaultSpacing
                width: parent.width

                Text {
                    text: {
                        switch (securityNotificationDialog.alertSeverity) {
                            case "critical": return "🚨"
                            case "error":    return "❌"
                            case "warning":  return "⚠️"
                            case "success":  return "✅"
                            default:         return "ℹ️"
                        }
                    }
                    font.pixelSize: screenTools.largeFontPointSize * 1.5
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: securityNotificationDialog.alertMessage
                    font.pixelSize: screenTools.mediumFontPointSize
                    wrapMode: Text.WordWrap
                    width: parent.width - screenTools.largeFontPointSize * 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        switch (securityNotificationDialog.alertSeverity) {
                            case "critical": return "#dc3545"
                            case "error":    return "#dc3545"
                            case "warning":  return "#ffc107"
                            case "success":  return "#28a745"
                            default:         return "#0066cc"
                        }
                    }
                }
            }

            Rectangle {
                width: screenTools.minButtonWidth
                height: screenTools.minButtonHeight
                radius: screenTools.defaultRadius * 0.5
                color: securityOkMouseArea.pressed ? "#004499" : accentColor
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    anchors.centerIn: parent
                    text: "OK"
                    color: "white"
                    font.pixelSize: screenTools.mediumFontPointSize
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: securityOkMouseArea
                    anchors.fill: parent
                    onClicked: securityNotificationDialog.close()
                }

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }



    // ============================================================
    // Main UI
    // ============================================================
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f5f5f5" }
            GradientStop { position: 1.0; color: "#e9ecef" }
        }

        // Background grid overlay
        Canvas {
            anchors.fill: parent
            opacity: 0.08
            renderStrategy: Canvas.Threaded
            renderTarget: Canvas.FramebufferObject
            Component.onCompleted: requestPaint()
            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.strokeStyle = "#adb5bd"
                ctx.lineWidth   = 1
                var gridSize = screenTools.defaultFontPixelHeight * 2.5
                for (var x = 0; x < width;  x += gridSize) { ctx.beginPath(); ctx.moveTo(x, 0);     ctx.lineTo(x, height); ctx.stroke() }
                for (var y = 0; y < height; y += gridSize) { ctx.beginPath(); ctx.moveTo(0, y);     ctx.lineTo(width, y);  ctx.stroke() }
            }
        }

        // ── Top Connection Bar ────────────────────────────────────────────
        ConnectionBar {
            id: connectionBar
            anchors.top:   parent.top
            anchors.left:  parent.left
            anchors.right: parent.right
            height: screenTools.toolbarHeight
            languageManager: languageManager
        }

        // ── Left Status Panel ─────────────────────────────────────────────
        StatusViewLeft {
            id: statusViewLeft
            anchors.top:    connectionBar.bottom
            anchors.left:   parent.left
            anchors.bottom: parent.bottom
            width: (sidebarVisible ? sidebarWidthOpen : sidebarWidthClosed) + (screenTools.defaultMargins * 2)
        }

        Rectangle {
            id: mainMapContainer
            anchors.top:    connectionBar.bottom
            anchors.left:   statusViewLeft.right
            anchors.right:  parent.right
            anchors.bottom: bottomControlBar.top
            anchors.margins: screenTools.defaultMargins
            anchors.bottomMargin: screenTools.smallMargins
            color: "transparent"
            radius: 0
            clip: true

            MapViewQML {
                id: mainMapView
                anchors.fill: parent
                anchors.margins: 2

                isEditable: false   // Read-only on main screen

                // Live telemetry bindings
                currentLat:       droneModel.isConnected && droneModel.telemetry ? droneModel.telemetry.lat     || 0 : 0
                currentLon:       droneModel.isConnected && droneModel.telemetry ? droneModel.telemetry.lon     || 0 : 0
                currentAlt:       droneModel.isConnected && droneModel.telemetry ? droneModel.telemetry.rel_alt || 0 : 0
                isDroneConnected: droneModel.isConnected

                Component.onCompleted: console.log("🗺️ Main map view initialized")
            }

            
        }

        // ── Bottom Control Bar ────────────────────────────────────────────
        Rectangle {
            id: bottomControlBar
            anchors.bottom: parent.bottom
            anchors.left: statusViewLeft.right
            anchors.right: parent.right
            anchors.leftMargin: screenTools.defaultMargins
            anchors.rightMargin: screenTools.defaultMargins
            anchors.bottomMargin: screenTools.defaultMargins
            height: screenTools.toolbarHeight * 1.5
            color: "transparent"

            ControlButtons {
                anchors.centerIn: parent
                mainWindowRef: mainWindow
                Component.onCompleted: {
                    mainWindow.navigationControlsInstance = this
                }
            }
        }

        // ── DroneCommander Mission Upload Listener ────────────────────────
        Connections {
            target: typeof droneCommander !== 'undefined' ? droneCommander : null

            function onMissionUploaded(waypoints) {
                console.log("✅ Main GCS - Mission uploaded:", waypoints.length, "waypoints")
                if (typeof mainMapView !== 'undefined' && waypoints.length > 0) {
                    console.log("📍 Setting mission path on main map...")
                    mainMapView.setUploadedMissionPath(waypoints)
                    mainMapView.showUploadedPath = true
                    console.log("✅ Mission path displayed on main map")
                } else {
                    console.log("⚠️ mainMapView not found or no waypoints")
                }
                
                // Show success popup here
                if (typeof globalToastPopup !== 'undefined') {
                    globalToastPopup.show("Waypoints sent to drone successfully! (" + waypoints.length + " WPs)")
                }
            }

            function onCommandFeedback(message) {
                console.log("📡 Main GCS - DroneCommander feedback:", message)
                if (message.indexOf("Mission upload successful") !== -1 || message.indexOf("Mission uploaded successfully") !== -1) {
                    console.log("🎉 Mission upload confirmed on main GCS")
                    if (typeof globalToastPopup !== 'undefined') {
                        globalToastPopup.show("Waypoints sent to drone successfully!")
                    }
                }
            }
        }

        // ── Security Badge ────────────────────────────────────────────────
        Rectangle {
            id: securityBadge
            anchors.top:   parent.top
            anchors.right: parent.right
            anchors.topMargin:   connectionBar.height + screenTools.defaultMargins
            anchors.rightMargin: screenTools.defaultMargins
            width:  screenTools.defaultFontPixelWidth  * 14
            height: screenTools.defaultFontPixelHeight * 1.8
            color: successColor; radius: screenTools.defaultRadius * 0.7
            opacity: 0.9; z: 1001

            Row {
                anchors.centerIn: parent
                spacing: screenTools.smallSpacing
                Text { text: "🔒"; font.pixelSize: screenTools.mediumFontPointSize; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "SECURE MODE"; font.family: "Segoe UI"; font.pixelSize: screenTools.smallFontPointSize; font.weight: Font.Bold; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
            }

            DropShadow { anchors.fill: parent; horizontalOffset: 0; verticalOffset: 2; radius: 4; samples: 9; color: "#30000000"; source: parent; cached: true }

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 1.0;  duration: 2000 }
                NumberAnimation { to: 0.85; duration: 2000 }
            }
        }

        // ── Feedback Button ───────────────────────────────────────────────
        Rectangle {
            id: feedbackButton
            anchors.bottom: copyrightNotice.top
            anchors.right:  parent.right
            anchors.bottomMargin: screenTools.smallMargins
            anchors.rightMargin:  screenTools.defaultMargins
            width:  screenTools.defaultFontPixelWidth  * 12
            height: screenTools.defaultFontPixelHeight * 1.8
            color: accentColor; radius: screenTools.defaultRadius * 0.7
            opacity: 0.9; z: 1000

            DropShadow { anchors.fill: parent; horizontalOffset: 0; verticalOffset: 2; radius: 4; samples: 9; color: "#30000000"; source: parent; cached: true }

            Row {
                anchors.centerIn: parent
                spacing: screenTools.smallSpacing
                Text { text: "📧"; font.pixelSize: screenTools.mediumFontPointSize; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Feedback"; font.family: "Segoe UI"; font.pixelSize: screenTools.smallFontPointSize; font.weight: Font.DemiBold; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
            }

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked:  { feedbackDialogLoader.active = true }
                onEntered:  { parent.opacity = 1.0; parent.scale = 1.05 }
                onExited:   { parent.opacity = 0.9; parent.scale = 1.0  }
            }

            Behavior on opacity { NumberAnimation { duration: 200 } }
            Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        // ── Copyright Notice ──────────────────────────────────────────────
        Text {
            id: copyrightNotice
            anchors.bottom: parent.bottom
            anchors.right:  parent.right
            anchors.bottomMargin: screenTools.defaultMargins
            anchors.rightMargin:  screenTools.defaultMargins
            text: "© 2025 TiHAN IIT Hyderabad. All rights reserved."
            font.family: "Consolas"
            font.pixelSize: screenTools.smallFontPointSize
            color: textSecondary; opacity: 0.8; z: 1000

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { copyrightWindowLoader.showCopyrightWindow() }
                onEntered: { parent.opacity = 1.0; parent.color = accentColor  }
                onExited:  { parent.opacity = 0.9; parent.color = textSecondary }
            }

            Behavior on opacity { NumberAnimation { duration: 200 } }
            Behavior on color   { ColorAnimation  { duration: 200 } }
        }

        // ============================================================
        // Global Toast Notification System
        // ============================================================
        Rectangle {
            id: globalToastPopup
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: screenTools.toolbarHeight + screenTools.defaultMargins * 4
            width: toastRow.implicitWidth + screenTools.defaultMargins * 8
            height: toastRow.implicitHeight + screenTools.defaultMargins * 5
            z: 99999
            visible: false
            opacity: 0

            color: "#1a1a2e"
            radius: screenTools.defaultRadius * 1.5
            border.color: successColor
            border.width: 2

            layer.enabled: true
            layer.effect: DropShadow {
                horizontalOffset: 0; verticalOffset: 4
                radius: 12; samples: 25; color: "#40000000"
            }

            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: screenTools.defaultSpacing
                
                Text {
                    text: "✅"
                    font.pixelSize: screenTools.largeFontPointSize * 1.5
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Text {
                    id: toastText
                    color: "white"
                    font.pixelSize: screenTools.largeFontPointSize
                    font.weight: Font.Bold
                    font.family: "Segoe UI"
                    text: "Waypoints sent to drone successfully!"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            NumberAnimation {
                id: toastFadeIn
                target: globalToastPopup
                property: "opacity"
                to: 1.0
                duration: 250
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                id: toastFadeOut
                target: globalToastPopup
                property: "opacity"
                to: 0.0
                duration: 350
                easing.type: Easing.InQuad
                onStopped: globalToastPopup.visible = false
            }

            Timer {
                id: toastTimer
                interval: 4000
                repeat: false
                onTriggered: toastFadeOut.start()
            }

            function show(msg) {
                toastText.text = msg
                toastFadeOut.stop()
                globalToastPopup.opacity = 0
                globalToastPopup.visible = true
                toastFadeIn.start()
                toastTimer.restart()
            }
        }
    }

    // ============================================================
    // Security Functions
    // ============================================================
    function showSecurityNotification(message, severity) {
        securityNotificationDialog.alertMessage  = message
        securityNotificationDialog.alertSeverity = severity
        securityNotificationDialog.open()
    }

    function validateCoordinateInput(lat, lng) {
        if (typeof securityManager === 'undefined') { console.warn("⚠️ Security Manager not available"); return true }
        if (!securityManager.validate_coordinate(lat, "latitude") || !securityManager.validate_coordinate(lng, "longitude")) {
            showSecurityNotification("Invalid coordinates detected. Action blocked.", "error")
            if (typeof messageLogger !== 'undefined') messageLogger.logMessage("🚫 Invalid coordinates rejected: " + lat + ", " + lng, "error")
            return false
        }
        return true
    }

    function validateAltitudeInput(altitude) {
        if (typeof securityManager === 'undefined') { console.warn("⚠️ Security Manager not available"); return true }
        if (!securityManager.validate_altitude(altitude)) {
            showSecurityNotification("Invalid altitude: " + altitude + "m. Must be 0-500m.", "error")
            if (typeof messageLogger !== 'undefined') messageLogger.logMessage("🚫 Invalid altitude rejected: " + altitude + "m", "error")
            return false
        }
        return true
    }

    function validateSpeedInput(speed) {
        if (typeof securityManager === 'undefined') { console.warn("⚠️ Security Manager not available"); return true }
        if (!securityManager.validate_speed(speed)) {
            showSecurityNotification("Invalid speed: " + speed + "m/s. Must be 0-25m/s.", "error")
            if (typeof messageLogger !== 'undefined') messageLogger.logMessage("🚫 Invalid speed rejected: " + speed + "m/s", "error")
            return false
        }
        return true
    }

    function validateCommandExecution(command, params) {
        if (typeof commandValidator === 'undefined') { console.warn("⚠️ Command Validator not available"); return true }
        if (!commandValidator.validate_command(command, params)) {
            showSecurityNotification("Command rejected: " + command, "error")
            if (typeof messageLogger !== 'undefined') messageLogger.logMessage("🚫 Command rejected: " + command, "error")
            return false
        }
        return true
    }

    function sanitizeTextInput(input, maxLength) {
        if (typeof securityManager === 'undefined') { console.warn("⚠️ Security Manager not available"); return input }
        return securityManager.sanitize_string(input, maxLength || 255)
    }

    function logSecurityEvent(eventType, details) {
        Qt.callLater(function() {
            if (typeof securityManager !== 'undefined') securityManager.log_security_event(eventType, details)
            console.log("🔒 Security Event: " + eventType + " - " + details)
        })
    }

    function checkRateLimit(identifier, maxAttempts, windowSeconds) {
        if (typeof securityManager === 'undefined') { console.warn("⚠️ Security Manager not available"); return true }
        return securityManager.check_rate_limit(identifier, maxAttempts || 10, windowSeconds || 60)
    }

    // ============================================================
    // Regular Functions
    // ============================================================
    function updateFlightData(altitude, groundSpeed, yaw, distToWP, verticalSpeed, distToMAV) {
        console.log("⚠️ updateFlightData() called but data is now auto-updated via property bindings")
    }

    function saveLanguagePreference(languageCode) {
        console.log("Saving language preference:", languageCode)
    }

    function loadLanguagePreference() {
        return "en"
    }

    function updateLanguageForAllComponents() {
        console.log("Language updated to:", languageManager.currentLanguage)
    }

    // ============================================================
    // Startup
    // ============================================================
    Component.onCompleted: {
        console.log("📐 Window: " + width + "x" + height)
        console.log("📐 Screen: " + Screen.width + "x" + Screen.height)
        console.log("✅ QGC-style responsive layout active")
        console.log("📏 Base font size: " + screenTools.defaultFontPixelHeight)

        var savedLang = loadLanguagePreference()
        languageManager.changeLanguage(savedLang)

        if (typeof droneCommander !== 'undefined') console.log("✓ DroneCommander connected to QML")
        else console.log("✗ ERROR: DroneCommander NOT available!")

        if (typeof droneModel !== 'undefined') {
            console.log("✓ DroneModel connected to QML")
            console.log("  - Connected:", droneModel.isConnected)
            if (droneModel.telemetry) console.log("  - Telemetry object exists")
            else console.warn("⚠️ WARNING: droneModel.telemetry is null/undefined!")
        } else {
            console.error("✗ CRITICAL: DroneModel NOT available!")
        }

        if (typeof securityManager !== 'undefined') {
            console.log("🔒 Security Manager connected to QML")
            logSecurityEvent("SYSTEM_READY", "QML interface initialized")
        } else {
            console.warn("⚠️ WARNING: Security Manager NOT available!")
        }

        if (typeof commandValidator !== 'undefined') console.log("🔒 Command Validator connected to QML")
        else console.warn("⚠️ WARNING: Command Validator NOT available!")

        if (typeof messageLogger !== 'undefined') {
            messageLogger.logMessage("🚀 TiHAN Secure GCS loaded successfully", "success")
            messageLogger.logMessage("🔒 Security features active", "info")
        }
    }

    // ============================================================
    // Timers
    // ============================================================
    Timer {
        id: securityMonitorTimer
        interval: 60000; running: true; repeat: true
        onTriggered: Qt.callLater(function() {
            if (typeof securityManager !== 'undefined')
                logSecurityEvent("SECURITY_CHECK", "Periodic security monitoring")
        })
    }

    Timer {
        id: inactivityTimer
        interval: 1800000; running: false; repeat: false
        onTriggered: {
            if (typeof securityManager !== 'undefined') {
                console.log("⏰ Auto-lock triggered due to inactivity")
                showSecurityNotification("Session locked due to inactivity", "warning")
                logSecurityEvent("AUTO_LOCK", "Inactivity timeout")
            }
        }
    }

    Timer {
        id: activityThrottleTimer
        interval: 1000; running: false; repeat: false
        onTriggered: inactivityTimer.restart()
    }

    // Global activity tracker (resets inactivity timer on any mouse event)
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        z: -1
        onClicked:  { if (!activityThrottleTimer.running) activityThrottleTimer.start(); mouse.accepted = false }
        onPressed:  { if (!activityThrottleTimer.running) activityThrottleTimer.start(); mouse.accepted = false }
    }
}

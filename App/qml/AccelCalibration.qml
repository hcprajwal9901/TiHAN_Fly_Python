import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    width: 420
    height: 360
    visible: true
    title: languageManager ? languageManager.getText("Accelerometer Calibration") : "Accelerometer Calibration"
    flags: Qt.Dialog
    modality: Qt.ApplicationModal
    color: "#121212"

    property int currentStep: 0
    property int totalSteps: 6
    property bool running: false
    property var calibrationModel
    property var languageManager: null
    
    // ─────────────────────────────────────────────────────────────────────────
    // Track the current instruction in its base key form (for language updates)
    // ─────────────────────────────────────────────────────────────────────────
    property string currentInstructionKey: ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // ────────────── Title ──────────────
        Text {
            text: languageManager ? languageManager.getText("Accelerometer Calibration") : "Accelerometer Calibration"
            font.pixelSize: 20
            color: "white"
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            height: 1
            color: "#333"
            Layout.fillWidth: true
        }

        // ────────────── Instruction ──────────────
        Text {
            id: instructionText
            text: languageManager ? languageManager.getText("Press START to begin calibration.") : "Press START to begin calibration."
            wrapMode: Text.WordWrap
            font.pixelSize: 14
            color: "#dddddd"
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // ────────────── Progress ──────────────
        ColumnLayout {
            Layout.fillWidth: true

            ProgressBar {
                value: currentStep
                from: 0
                to: totalSteps
                Layout.fillWidth: true
            }

            Text {
                text: "Step " + currentStep + " / " + totalSteps
                color: "#aaaaaa"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // ────────────── Buttons ──────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                text: languageManager ? languageManager.getText("Start") : "Start"
                enabled: !running
                Layout.fillWidth: true
                onClicked: {
                    calibrationModel.start(1, 1)
                    running = true
                    currentStep = 0
                }
            }

            Button {
                text: languageManager ? languageManager.getText("Next") : "Next"
                enabled: running
                Layout.fillWidth: true
                onClicked: {
                    calibrationModel.user_next()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INSTRUCTION TRANSLATION FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Maps Python instruction strings to translation keys
     * This function takes the raw instruction from Python and extracts the key
     */
function translateInstruction(pythonText) {

    pythonText = pythonText.toLowerCase()

    if (pythonText.includes("level")) {
        currentInstructionKey = "Place vehicle level"
    }
    else if (pythonText.includes("left")) {
        currentInstructionKey = "Position 2: Rotate"
    }
    else if (pythonText.includes("right")) {
        currentInstructionKey = "Position 3: Rotate again"
    }
    else if (pythonText.includes("nose")) {
        currentInstructionKey = "Position 4: Rotate again"
    }
    else if (pythonText.includes("tail")) {
        currentInstructionKey = "Position 5: Rotate again"
    }
    else if (pythonText.includes("upside")) {
        currentInstructionKey = "Position 6: Rotate again"
    }
    else if (pythonText.includes("complete")) {
        currentInstructionKey = "Calibration complete"
    }
    else {
        currentInstructionKey = pythonText
    }

    updateInstructionDisplay()
}

    /**
     * Updates the instruction text based on current language
     * Called when:
     * 1. New instruction arrives from Python
     * 2. User changes language
     */
    function updateInstructionDisplay() {
        if (!currentInstructionKey || currentInstructionKey === "") {
            return
        }
        
        if (languageManager) {
            instructionText.text = languageManager.getText(currentInstructionKey)
        } else {
            instructionText.text = currentInstructionKey
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Listen for language changes and update instruction
    // ─────────────────────────────────────────────────────────────────────────
    Connections {
        target: languageManager
        ignoreUnknownSignals: true
        
        function onCurrentLanguageChanged() {
            console.log("🌐 Language changed - retranslating instruction")
            // Retranslate the current instruction when language changes
            updateInstructionDisplay()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Listen for calibration model signals
    // ─────────────────────────────────────────────────────────────────────────
    Connections {
        target: calibrationModel
        ignoreUnknownSignals: true
        
        function onInstructionUpdated(text) {
            console.log("📝 Instruction from Python:", text)
            // Translate and display the instruction
            translateInstruction(text)
        }
        
        function onProgressUpdated(step, total) {
            console.log("📊 Progress:", step, "/", total)
            currentStep = step
            totalSteps = total
        }
        
        function onFinished(success) {
            console.log("✅ Calibration finished - Success:", success)
            running = false
            
            if (success) {
                currentInstructionKey = "Calibration completed successfully"
            } else {
                currentInstructionKey = "Calibration failed"
            }
            
            updateInstructionDisplay()
        }
        
        function onError(msg) {
            console.log("❌ Calibration error:", msg)
            running = false
            instructionText.text = (languageManager ? languageManager.getText("Error") : "Error") + ": " + msg
        }
    }
}
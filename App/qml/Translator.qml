//Translator.qml
import QtQuick 2.0

QtObject {
    property var languageManager: null
    property string currentLanguage: languageManager ? languageManager.currentLanguage : "en"

    function translate(key) {
        return languageManager ? languageManager.getText(key) : key;
    }
}

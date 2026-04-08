// Complete Updated LanguageManager.qml with CALIBRATION INSTRUCTIONS
import QtQuick 2.15
import QtQuick.Controls 2.15

QtObject {
    id: languageManager
    
    // Current language property
    property string currentLanguage: "en"
    
    // Signal when language changes (for AccelCalibration.qml to listen)
   
    
    // Available languages
    property var availableLanguages: [
        { code: "en", name: "English", nativeName: "English" },
        { code: "ta", name: "Tamil", nativeName: "தமிழ்" },
        { code: "hi", name: "Hindi", nativeName: "हिन्दी" },
        { code: "te", name: "Telugu", nativeName: "తెలుగు" }
    ]
    
    // Translation strings object
    property var translations: ({
        // ═════════════════════════════════════════════════════════════════════
        // CALIBRATION INSTRUCTIONS - ACCELEROMETER
        // ═════════════════════════════════════════════════════════════════════
        "Place vehicle level": {
            "en": "Place vehicle level",
            "ta": "வாகனத்தை தட்டையாக வைக்கவும்",
            "hi": "वाहन को समतल रखें",
            "te": "వాహనాన్ని సమతలంగా ఉంచండి"
        },
        "Rotate vehicle": {
            "en": "Rotate vehicle",
            "ta": "வாகனத்தை சுழற்றவும்",
            "hi": "वाहन को घुमाएं",
            "te": "వాహనాన్ని తిప్పండి"
        },
        "Hold vehicle steady": {
            "en": "Hold vehicle steady",
            "ta": "வாகனத்தை நிலையாக வைக்கவும்",
            "hi": "वाहन को स्थिर रखें",
            "te": "వాహనాన్ని స్థిరంగా ఉంచండి"
        },
        "Calibration in progress": {
            "en": "Calibration in progress",
            "ta": "அளவீடு நடந்து கொண்டிருக்கிறது",
            "hi": "कैलिब्रेशन प्रगति में है",
            "te": "కాలిబ్రేషన్ ప్రవర్తనలో ఉంది"
        },
        "Waiting for next step": {
            "en": "Waiting for next step",
            "ta": "அடுத்த படிக்காக காத்திருக்கிறது",
            "hi": "अगले चरण की प्रतीक्षा कर रहे हैं",
            "te": "తదుపరి దశ కోసం వేచి ఉన్నారు"
        },
        "Calibration complete": {
            "en": "Calibration complete",
            "ta": "அளவீடு முடிந்துவிட்டது",
            "hi": "कैलिब्रेशन पूर्ण",
            "te": "కాలిబ్రేషన్ పూర్తయింది"
        },
        "Place the vehicle on a level surface": {
            "en": "Place the vehicle on a level surface",
            "ta": "வாகனத்தை தட்டையான மேற்பரப்பில் வைக்கவும்",
            "hi": "वाहन को समतल सतह पर रखें",
            "te": "వాహనాన్ని సమతల ఉపరితలంపై ఉంచండి"
        },
        "Rotate the vehicle slowly": {
            "en": "Rotate the vehicle slowly",
            "ta": "வாகனத்தை천천히 சுழற்றவும்",
            "hi": "वाहन को धीरे-धीरे घुमाएं",
            "te": "వాహనాన్ని నెమ్మదిగా తిప్పండి"
        },
        "Keep the vehicle steady": {
            "en": "Keep the vehicle steady",
            "ta": "வாகனத்தை நிலையாக வைத்திருக்கவும்",
            "hi": "वाहन को स्थिर रखें",
            "te": "వాహనాన్ని స్థిరంగా ఉంచండి"
        },
        "Position 1: Level": {
            "en": "Position 1: Level",
            "ta": "நிலை 1: தட்டை",
            "hi": "स्थिति 1: समतल",
            "te": "స్థితి 1: సమతల"
        },
        "Position 2: Rotate": {
            "en": "Position 2: Rotate",
            "ta": "நிலை 2: சுழற்று",
            "hi": "स्थिति 2: घुमाएं",
            "te": "స్థితి 2: తిప్పండి"
        },
        "Position 3: Rotate again": {
            "en": "Position 3: Rotate again",
            "ta": "நிலை 3: மீண்டும் சுழற்று",
            "hi": "स्थिति 3: फिर घुमाएं",
            "te": "స్థితి 3: మళ్లీ తిప్పండి"
        },
        "Position 4: Rotate again": {
            "en": "Position 4: Rotate again",
            "ta": "நிலை 4: மீண்டும் சுழற்று",
            "hi": "स्थिति 4: फिर घुमाएं",
            "te": "స్థితి 4: మళ్లీ తిప్పండి"
        },
        "Position 5: Rotate again": {
            "en": "Position 5: Rotate again",
            "ta": "நிலை 5: மீண்டும் சுழற்று",
            "hi": "स्थिति 5: फिर घुमाएं",
            "te": "స్థితి 5: మళ్లీ తిప్పండి"
        },
        "Position 6: Rotate again": {
            "en": "Position 6: Rotate again",
            "ta": "நிலை 6: மீண்டும் சுழற்று",
            "hi": "स्थिति 6: फिर घुमाएं",
            "te": "స్థితి 6: మళ్లీ తిప్పండి"
        },

        // ═════════════════════════════════════════════════════════════════════
        // CALIBRATION RESULTS
        // ═════════════════════════════════════════════════════════════════════
        "Calibration completed successfully": {
            "en": "Calibration completed successfully ✔",
            "ta": "அளவீடு வெற்றிகரமாக முடிந்தது ✔",
            "hi": "कैलिब्रेशन सफलतापूर्वक पूर्ण हुआ ✔",
            "te": "కాలిబ్రేషన్ విజయవంతంగా పూర్తయింది ✔"
        },
        "Calibration failed": {
            "en": "Calibration failed ✖",
            "ta": "அளவீடு தோல்வியடைந்தது ✖",
            "hi": "कैलिब्रेशन विफल ✖",
            "te": "కాలిబ్రేషన్ విఫలమైంది ✖"
        },

        // ═════════════════════════════════════════════════════════════════════
        // Connection Bar
        // ═════════════════════════════════════════════════════════════════════
        "CONNECT": {
            "en": "CONNECT",
            "ta": "இணைக்க",
            "hi": "कनेक्ट",
            "te": "కనెక్ట్"
        },
        "DISCONNECT": {
            "en": "DISCONNECT",
            "ta": "துண்டிக்க",
            "hi": "डिस्कनेक्ट",
            "te": "డిస్‌కనెక్ట్"
        },
        "CONNECTED": {
            "en": "CONNECTED",
            "ta": "இணைக்கப்பட்டது",
            "hi": "जुड़ा हुआ",
            "te": "కనెక్ట్ చేయబడింది"
        },
        "DISCONNECTED": {
            "en": "DISCONNECTED",
            "ta": "துண்டிக்கப்பட்டது",
            "hi": "डिस्कनेक्ट किया गया",
            "te": "డిస్‌కనెక్ట్ చేయబడింది"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Control Buttons
        // ═════════════════════════════════════════════════════════════════════
        "TAKEOFF": {
            "en": "TAKEOFF",
            "ta": "புறப்பாடு",
            "hi": "टेकऑफ",
            "te": "టేకాఫ్"
        },
        "LAND": {
            "en": "LAND",
            "ta": "தரையிறங்கு",
            "hi": "लैंड",
            "te": "ల్యాండ్"
        },
        "SETTINGS": {
            "en": "SETTINGS",
            "ta": "அமைப்புகள்",
            "hi": "सेटिंग्स",
            "te": "సెట్టింగ్స్"
        },
        "Ti-NARI": {
            "en": "Ti-NARI",
            "ta": "டி-நாரி",
            "hi": "टी-नारी",
            "te": "టి-నారి"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // ARM/DISARM States
        // ═════════════════════════════════════════════════════════════════════
        "ARMED": {
            "en": "ARMED",
            "ta": "ஆயுதம் கொண்ட",
            "hi": "सशस्त्र",
            "te": "ఆయుధధారి"
        },
        "Flight Mode": {
            "en": "Flight Mode",
            "ta": "பறக்கும் முறை",
            "hi": "फ्लाइट मोड",
            "te": "ఫ్లైట్ మోడ్"
        },
        "DISARMED": {
            "en": "DISARMED",
            "ta": "ஆயுதம் இல்லாத",
            "hi": "निरस्त्र",
            "te": "నిరాయుధ"
        },
        "ERROR": {
            "en": "ERROR",
            "ta": "பிழை",
            "hi": "त्रुटि",
            "te": "దోషం"
        },
        "Message": {
            "en": "Message",
            "ta": "செய்தி",
            "hi": "संदेश",
            "te": "సందేశం"
        },
        "Mode Changed": {
            "en": "Mode Changed",
            "ta": "பயன்முறை மாற்றப்பட்டது",
            "hi": "मोड बदला गया",
            "te": "మోడ్ మార్చబడింది"
        },
        "Mode changed to": {
            "en": "Mode changed to",
            "ta": "பயன்முறை மாற்றப்பட்டது",
            "hi": "मोड में बदल गया",
            "te": "మోడ్ కు మార్చబడింది"
        },
        "Drone Armed Successfully": {
            "en": "Drone Armed Successfully",
            "ta": "ட்ரோன் வெற்றிகரமாக ஆயுதம் செய்யப்பட்டது",
            "hi": "ड्रोन सफलतापूर्वक सशस्त्र",
            "te": "డ్రోన్ విజయవంతంగా ఆయుధధారిగా చేయబడింది"
        },
        "Drone Disarmed Successfully": {
            "en": "Drone Disarmed Successfully",
            "ta": "ட்ரோன் வெற்றிகரமாக ஆயுதம் நீக்கப்பட்டது",
            "hi": "ड्रोन सफलतापूर्वक निरस्त्र",
            "te": "డ్రోన్ విజయవంతంగా నిరాయుధీకరించబడింది"
        },
        "Select flight mode": {
            "en": "Select flight mode",
            "ta": "பறக்கும் பயன்முறையைத் தேர்ந்தெடுக்கவும்",
            "hi": "फ्लाइट मोड चुनें",
            "te": "ఫ్లైట్ మోడ్‌ను ఎంచుకోండి"
        },
        "Connect to drone first": {
            "en": "Connect to drone first",
            "ta": "முதலில் ட்ரோனுடன் இணைக்கவும்",
            "hi": "पहले ड्रोन से कनेक्ट करें",
            "te": "మొదట డ్రోన్‌కు కనెక్ట్ చేయండి"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Menu Items
        // ═════════════════════════════════════════════════════════════════════
        "Status": {
            "en": "Status",
            "ta": "நிலை",
            "hi": "स्थिति",
            "te": "స్థితి"
        },
        "Panel": {
            "en": "Panel",
            "ta": "பேனல்",
            "hi": "पैनल",
            "te": "ప్యానెల్"
        },
        "Fail Safe": {
            "en": "Fail Safe",
            "ta": "பாதுகாப்பு தோல్வி",
            "hi": "फेल सेफ",
            "te": "ఫెయిల్ సేఫ్"
        },
        "GeoFence": {
            "en": "GeoFence",
            "ta": "ஜியோஃபென்ஸ்",
            "hi": "जियोफेंस",
            "te": "జియోఫెన్స్"
        },
        "Battery Fail Safe": {
            "en": "Battery Fail Safe",
            "ta": "பேட்டரி பாதுகாப்பு",
            "hi": "बैटरी सुरक्षा",
            "te": "బ్యాటరీ భద్రత"
        },
        "RC FailSafe": {
            "en": "RC FailSafe",
            "ta": "RC பாதுகாப்பு",
            "hi": "RC सुरक्षा",
            "te": "RC భద్రత"
        },
        "Waypoints": {
            "en": "Waypoints",
            "ta": "வழிப்புள்ளிகள்",
            "hi": "वेपॉइंट्स",
            "te": "వేపాయింట్స్"
        },
        "Parameters": {
            "en": "Parameters",
            "ta": "அளவுருக்கள்",
            "hi": "पैरामीटर",
            "te": "పారామీటర్లు"
        },
        "Calibrations": {
            "en": "Calibrations",
            "ta": "அளவீட்டுகள்",
            "hi": "कैलिब्रेशन",
            "te": "కాలిబ్రేషన్స్"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Mission Upload Section
        // ═════════════════════════════════════════════════════════════════════
        "Mission Upload": {
            "en": "Mission Upload",
            "ta": "பணி பதிவேற்றம்",
            "hi": "मिशन अपलोड",
            "te": "మిషన్ అప్‌లోడ్"
        },
        "Add": {
            "en": "Add",
            "ta": "சேர்க்க",
            "hi": "जोड़ना",
            "te": "జోడించు"
        },
        "Send": {
            "en": "Send",
            "ta": "அனுப்ப",
            "hi": "भेजना",
            "te": "పంపు"
        },
        "Clear": {
            "en": "Clear",
            "ta": "அழி",
            "hi": "साफ़ करना",
            "te": "క్లియర్"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Weather Dashboard
        // ═════════════════════════════════════════════════════════════════════
        "Weather Info": {
            "en": "Weather Info",
            "ta": "வானிலை தகவல்",
            "hi": "मौसम की जानकारी",
            "te": "వాతావరణ సమాచారం"
        },
        "Unknown Location": {
            "en": "Unknown Location",
            "ta": "அறியப்படாத இடம்",
            "hi": "अज्ञात स्थान",
            "te": "తెలియని ప్రాంతం"
        },
        "Loading weather data...": {
            "en": "Loading weather data...",
            "ta": "வானிலை தரவுகளை ஏற்றுகிறது...",
            "hi": "मौसम डेटा लोड हो रहा है...",
            "te": "వాతావరణ డేటా లోడ్ అవుతోంది..."
        },
        "Loading...": {
            "en": "Loading...",
            "ta": "ஏற்றுகிறது...",
            "hi": "लोड हो रहा है...",
            "te": "లోడ్ అవుతోంది..."
        },
        "Wind": {
            "en": "Wind",
            "ta": "காற்று",
            "hi": "हवा",
            "te": "గాలి"
        },
        "Humidity": {
            "en": "Humidity",
            "ta": "ஈரப்பதம்",
            "hi": "आर्द्रता",
            "te": "తేమ"
        },
        "Pressure": {
            "en": "Pressure",
            "ta": "அழுத்தம்",
            "hi": "दबाव",
            "te": "ఒత్తిడి"
        },
        "Visibility": {
            "en": "Visibility",
            "ta": "தெரிவுநிலை",
            "hi": "दृश्यता",
            "te": "దృశ్యత"
        },
        "UV Index": {
            "en": "UV Index",
            "ta": "UV குறியீடு",
            "hi": "UV इंडेक्स",
            "te": "UV ఇండెక్స్"
        },
        "Cloud Cover": {
            "en": "Cloud Cover",
            "ta": "மேகத்திருத்து",
            "hi": "बादल",
            "te": "మేఘ కవచం"
        },
        "Close": {
            "en": "Close",
            "ta": "மூடு",
            "hi": "बंद करें",
            "te": "మూసివేయి"
        },
        "Weather Warning": {
            "en": "Weather Warning",
            "ta": "வானிலை எச்சரிக்கை",
            "hi": "मौसम चेतावनी",
            "te": "వాతావరణ హెచ్చరిక"
        },
        "High Temperature Warning": {
            "en": "High Temperature Warning",
            "ta": "அதிக வெப்பநिலை எச்சரிக்கை",
            "hi": "उच्च तापमान चेतावनी",
            "te": "అధిక ఉష్ణోగ్రత హెచ్చరిక"
        },
        "High Wind Warning": {
            "en": "High Wind Warning",
            "ta": "அதிக காற்று எச்சரிக்கை",
            "hi": "तेज़ हवा चेतावनी",
            "te": "అధిక గాలి హెచ్చరిక"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Waypoint Dashboard
        // ═════════════════════════════════════════════════════════════════════
        "Command Editor": {
            "en": "Command Editor",
            "ta": "கட్டளை திருத்தி",
            "hi": "कमांड एडिटर",
            "te": "కమాండ్ ఎడిటర్"
        },
        "Mission Start": {
            "en": "Mission Start",
            "ta": "பணி தொடக்கம்",
            "hi": "मिशन शुरू",
            "te": "మిషన్ ప్రారంభం"
        },
        "Edit Waypoint": {
            "en": "Edit Waypoint",
            "ta": "வழிப்புள்ளி திருத்து",
            "hi": "वेपॉइंट संपादित करें",
            "te": "వేపాయింట్ సవరించండి"
        },
        "Command": {
            "en": "Command",
            "ta": "கட்டளை",
            "hi": "कमांड",
            "te": "కమాండ్"
        },
        "Waypoint": {
            "en": "Waypoint",
            "ta": "வழிப்புள்ளி",
            "hi": "वेपॉइंट",
            "te": "వేపాయింట్"
        },
        "Takeoff": {
            "en": "Takeoff",
            "ta": "புறப்பாடு",
            "hi": "टेकऑफ",
            "te": "టేకాఫ్"
        },
        "Land": {
            "en": "Land",
            "ta": "தரையிறங்கு",
            "hi": "लैंड",
            "te": "ల్యాండ్"
        },
        "Return to Launch": {
            "en": "Return to Launch",
            "ta": "ஏவுதலுக்கு திரும்பு",
            "hi": "लॉन्च पर वापसी",
            "te": "లాంచ్‌కు తిరిగి రండి"
        },
        "Loiter": {
            "en": "Loiter",
            "ta": "நிறுத்தி வை",
            "hi": "धीमी गति",
            "te": "లోయిటర్"
        },
        "Circle": {
            "en": "Circle",
            "ta": "வட்டம்",
            "hi": "सर्कल",
            "te": "వృత్తం"
        },
        "Follow Me": {
            "en": "Follow Me",
            "ta": "என்னைப் பின்பற்று",
            "hi": "मेरा अनुसरण करें",
            "te": "నన్ను అనుసరించండి"
        },
        "Home": {
            "en": "Home",
            "ta": "வீடு",
            "hi": "घर",
            "te": "హోమ్"
        },
        "Altitude": {
            "en": "Altitude",
            "ta": "உயரம்",
            "hi": "ऊंचाई",
            "te": "ఎత్తు"
        },
        "Speed": {
            "en": "Speed",
            "ta": "வேகம்",
            "hi": "गति",
            "te": "వేగం"
        },
        "Camera": {
            "en": "Camera",
            "ta": "கேமிரா",
            "hi": "कैमरा",
            "te": "కెమెరా"
        },
        "None": {
            "en": "None",
            "ta": "ஏதுமில்லை",
            "hi": "कोई नहीं",
            "te": "ఏమీ లేదు"
        },
        "Photo": {
            "en": "Photo",
            "ta": "புகைப்படம்",
            "hi": "फोटो",
            "te": "ఫోటో"
        },
        "Video": {
            "en": "Video",
            "ta": "வீடியோ",
            "hi": "वीडियो",
            "te": "వీడియో"
        },
        "Survey": {
            "en": "Survey",
            "ta": "ஆய்வு",
            "hi": "सर्वेक्षण",
            "te": "సర్వే"
        },
        "Delete": {
            "en": "Delete",
            "ta": "நீக்கு",
            "hi": "डिलीट",
            "te": "తొలగించు"
        },
        "Apply": {
            "en": "Apply",
            "ta": "பயன்படுத்து",
            "hi": "लागू करें",
            "te": "వర్తింపజేయండి"
        },
        "Mission Command List": {
            "en": "Mission Command List",
            "ta": "பணி கட்டளை பட்டியல்",
            "hi": "मिशन कमांड सूची",
            "te": "మిషన్ కమాండ్ జాబితా"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Status Panel
        // ═════════════════════════════════════════════════════════════════════
        "Ground Speed": {
            "en": "Ground Speed",
            "ta": "தரை வேகம்",
            "hi": "ग्राउंड स्पीड",
            "te": "గ్రౌండ్ స్పీడ్"
        },
        "Yaw": {
            "en": "Yaw",
            "ta": "சுழற்சி",
            "hi": "यॉ",
            "te": "యా"
        },
        "Distance to WP": {
            "en": "Distance to WP",
            "ta": "WP க்கு தூரம்",
            "hi": "WP तक की दूरी",
            "te": "WP కు దూరం"
        },
        "Vertical Speed": {
            "en": "Vertical Speed",
            "ta": "செங்குத்து வேகம்",
            "hi": "वर्टिकल स्पीड",
            "te": "వర్టికల్ స్పీడ్"
        },
        "Distance to MAV": {
            "en": "Distance to MAV",
            "ta": "MAV க்கு தூரம்",
            "hi": "MAV तक की दूरी",
            "te": "MAV కు దూరం"
        },
        
        // ═════════════════════════════════════════════════════════════════════
        // Units
        // ═════════════════════════════════════════════════════════════════════
        "m": {
            "en": "m",
            "ta": "மீ",
            "hi": "मी",
            "te": "మీ"
        },
        "m/s": {
            "en": "m/s",
            "ta": "மீ/விநாடி",
            "hi": "मी/से",
            "te": "మీ/సె"
        },
        "deg": {
            "en": "deg",
            "ta": "டிகிரி",
            "hi": "डिग्री",
            "te": "డిగ్రీ"
        },

        // ═════════════════════════════════════════════════════════════════════
        // Additional Labels
        // ═════════════════════════════════════════════════════════════════════
        "RTL": {
            "en": "RTL",
            "ta": "திரும்ப",
            "hi": "वापस",
            "te": "ఆటో రిటర్న్"
        },
        "Battery": {
            "en": "Battery",
            "ta": "மின்கலம்",
            "hi": "बैटरी",
            "te": "బ్యాటరీ"
        },
        "Voltage": {
            "en": "Voltage",
            "ta": "மின்னழுத்தம்",
            "hi": "वोल्टेज",
            "te": "వోల్టేజ్"
        },
        "Flightmode": {
            "en": "Flight Mode",
            "ta": "பறக்கும் முறை",
            "hi": "फ़्लाइट मोड",
            "te": "ఫ్లైట్ మోడ్"
        },
        "Disarmed": {
            "en": "Disarmed",
            "ta": "செயலிழக்கப்பட்டது",
            "hi": "निष्क्रिय",
            "te": "నిరాయుధం"
        },

        // ═════════════════════════════════════════════════════════════════════
        // Flight Modes
        // ═════════════════════════════════════════════════════════════════════
        "STABILIZE": {
            "en": "STABILIZE",
            "ta": "நிலைப்படுத்து",
            "hi": "स्टेबलाइज़",
            "te": "స్టెబిలైజ్"
        },
        "ACRO": {
            "en": "ACRO",
            "ta": "ஆக்ரோ",
            "hi": "एक्रो",
            "te": "ఆక్రో"
        },
        "ALT_HOLD": {
            "en": "ALT HOLD",
            "ta": "உயரம் நிலை",
            "hi": "ऊंचाई पकड़",
            "te": "ఎత్తు నిలుపు"
        },
        "AUTO": {
            "en": "AUTO",
            "ta": "தானியங்கு",
            "hi": "ऑटो",
            "te": "ఆటో"
        },
        "GUIDED": {
            "en": "GUIDED",
            "ta": "வழிகாட்டல்",
            "hi": "गाइडेड",
            "te": "గైడెడ్"
        },
        "LOITER": {
            "en": "LOITER",
            "ta": "நிறுத்து",
            "hi": "लॉइटर",
            "te": "లోయిటర్"
        },
        "CIRCLE": {
            "en": "CIRCLE",
            "ta": "வட்டம்",
            "hi": "सर्कल",
            "te": "వృత్తం"
        },
        "POSITION": {
            "en": "POSITION",
            "ta": "நிலைப்படுத்து",
            "hi": "पोजीशन",
            "te": "పొజిషన్"
        },
        "OF_LOITER": {
            "en": "OF LOITER",
            "ta": "ஆப்டிக்கல் லாய்ட்டர்",
            "hi": "ऑप्टिकल लॉइटर",
            "te": "ఆప్టికల్ లాయిటర్"
        },
        "DRIFT": {
            "en": "DRIFT",
            "ta": "சறுக்கல்",
            "hi": "ड्रिफ्ट",
            "te": "డ్రిఫ్ట్"
        },
        "SPORT": {
            "en": "SPORT",
            "ta": "விளையாட்டு",
            "hi": "स्पोर्ट",
            "te": "స్పోర్ట్"
        },
        "FLIP": {
            "en": "FLIP",
            "ta": "புரட்டு",
            "hi": "फ्लिप",
            "te": "ఫ్లిప్"
        },
        "AUTOTUNE": {
            "en": "AUTOTUNE",
            "ta": "தானியங்கி ட்யூன்",
            "hi": "ऑटोट्यून",
            "te": "ఆటోట్యూన్"
        },
        "POSHOLD": {
            "en": "POSHOLD",
            "ta": "நிலை வைத்து",
            "hi": "पोसहोल्ड",
            "te": "పోస్‌హోల్డ్"
        },
        "BRAKE": {
            "en": "BRAKE",
            "ta": "நிறுத்து",
            "hi": "ब्रेक",
            "te": "బ్రేక్"
        },
        "THROW": {
            "en": "THROW",
            "ta": "எறி",
            "hi": "थ्रो",
            "te": "త్రో"
        },
        "AVOID_ADSB": {
            "en": "AVOID ADSB",
            "ta": "ADSB தவிர்",
            "hi": "एडीएसबी बचें",
            "te": "ADSB ఎవాయిడ్"
        },
        "GUIDED_NOGPS": {
            "en": "GUIDED NO GPS",
            "ta": "GPS இல்லாமல் வழிகாட்டல்",
            "hi": "गाइडेड बिना जीपीएस",
            "te": "GPS లేకుండా గైడెడ్"
        },
        "SMART_RTL": {
            "en": "SMART RTL",
            "ta": "ஸ்மார்ட் RTL",
            "hi": "स्मार्ट आरटीएल",
            "te": "స్మార్ట్ RTL"
        },
        "FLOWHOLD": {
            "en": "FLOWHOLD",
            "ta": "ஃப்லோ ஹோல்ட்",
            "hi": "फ्लोहोल्ड",
            "te": "ఫ్లోహోల్డ్"
        },
        "FOLLOW": {
            "en": "FOLLOW",
            "ta": "பின்பற்று",
            "hi": "फॉलो",
            "te": "ఫాలో"
        },
        "ZIGZAG": {
            "en": "ZIGZAG",
            "ta": "ஜிக்ஜாக்",
            "hi": "जिगजैग",
            "te": "జిగ్‌జాగ్"
        },
        "SYSTEMID": {
            "en": "SYSTEM ID",
            "ta": "அமைப்பு ID",
            "hi": "सिस्टम आईडी",
            "te": "సిస్టమ్ ID"
        },
        "AUTOROTATE": {
            "en": "AUTOROTATE",
            "ta": "தானியங்கி சுழற்சி",
            "hi": "ऑटोरोटेट",
            "te": "ఆటో రొటేట్"
        },
        "AUTO_RTL": {
            "en": "AUTO RTL",
            "ta": "தானியங்கு RTL",
            "hi": "ऑटो आरटीएल",
            "te": "ఆటో RTL"
        },

        // ═════════════════════════════════════════════════════════════════════
        // Takeoff Dialog
        // ═════════════════════════════════════════════════════════════════════
        "Takeoff Configuration": {
            "en": "Takeoff Configuration",
            "ta": "புறப்பாடு உள்ளமைவு",
            "hi": "टेकऑफ कॉन्फ़िगरेशन",
            "te": "టేకాఫ్ కాన్ఫిగరేషన్"
        },
        "Set the altitude for drone takeoff": {
            "en": "Set the altitude for drone takeoff",
            "ta": "ட்ரோன் புறப்பாட்டிற்கு உயரம் அமைக்கவும்",
            "hi": "ड्रोन टेकऑफ के लिए ऊंचाई सेट करें",
            "te": "డ్రోన్ టేకాఫ్ కోసం ఎత్తును సెట్ చేయండి"
        },
        "Altitude (meters)": {
            "en": "Altitude (meters)",
            "ta": "உயரம் (மீட்டர்)",
            "hi": "ऊंचाई (मीटर)",
            "te": "ఎత్తు (మీటర్లు)"
        },
        "Range: 1.0 - 500.0 meters": {
            "en": "Range: 1.0 - 500.0 meters",
            "ta": "வரம்பு: 1.0 - 500.0 மீட்டர்",
            "hi": "रेंज: 1.0 - 500.0 मीटर",
            "te": "పరిధి: 1.0 - 500.0 మీటర్లు"
        },
        "Cancel": {
            "en": "Cancel",
            "ta": "ரத்து செய்",
            "hi": "रद्द करें",
            "te": "రద్దు చేయండి"
        },
        "Start Takeoff": {
            "en": "Start Takeoff",
            "ta": "புறப்பாடு தொடங்கு",
            "hi": "टेकऑफ शुरू करें",
            "te": "టేకాఫ్ ప్రారంభించండి"
        },
        "Accelerometer Calibration": {
            "en": "Accelerometer Calibration",
            "ta": "முடுக்கமானி அளவீடு",
            "hi": "एक्सेलेरोमीटर कैलिब्रेशन",
            "te": "యాక్సిలరోమీటర్ కాలిబ్రేషన్"
        },
        "Press START to begin calibration.": {
            "en": "Press START to begin calibration.",
            "ta": "அளவீட்டைத் தொடங்க START அழுத்தவும்.",
            "hi": "कैलिब्रेशन शुरू करने के लिए START दबाएं।",
            "te": "కాలిబ్రేషన్ ప్రారంభించడానికి START నొక్కండి."
        },
        "Step": {
            "en": "Step",
            "ta": "படி",
            "hi": "चरण",
            "te": "దశ"
        },
        "Start": {
            "en": "Start",
            "ta": "தொடங்கு",
            "hi": "शुरू करें",
            "te": "ప్రారంభించండి"
        },
        "Next": {
            "en": "Next",
            "ta": "அடுத்து",
            "hi": "अगला",
            "te": "తదుపరి"
        },
"Compass Calibration": {
            "en": "Compass Calibration System",
            "ta": "திசைகாட்டி அளவீடு முறை",
            "hi": "कंपास कैलिब्रेशन प्रणाली",
            "te": "కంపాస్ కాలిబ్రేషన్ వ్యవస్థ"
        },
        "Advanced Configuration & Diagnostics": {
            "en": "Advanced Configuration & Diagnostics",
            "ta": "மேம்பட்ட உள்ளமைவு & நோய் நির్ధారணம்",
            "hi": "उन्नत कॉन्फ़िगरेशन और डायग्नोस्टिक्स",
            "te": "అందుబాటు కాన్ఫిగరేషన్ & ఆరోగ్య నిర్ధారణ"
        },
        "System Diagnostics": {
            "en": "System Diagnostics",
            "ta": "அமைப்பு நோய் நির్ధారணம்",
            "hi": "सिस्टम डायग्नोस्टिक्स",
            "te": "సిస్టమ్ డయాగ్నస్టిక్‌లు"
        },
        "Model Status": {
            "en": "Model Status",
            "ta": "மாதிரி நிலை",
            "hi": "मॉडल स्थिति",
            "te": "మోడల్ స్థితి"
        },
        "Calibration": {
            "en": "Calibration",
            "ta": "அளவீடு",
            "hi": "कैलिब्रेशन",
            "te": "కాలిబ్రేషన్"
        },
        "Mag 1": {
            "en": "Magnetometer 1",
            "ta": "காந்தமானி 1",
            "hi": "चुंबकत्वमापी 1",
            "te": "మ్యాగ్నెటోమీటర్ 1"
        },
        "Mag 2": {
            "en": "Magnetometer 2",
            "ta": "காந்தமானி 2",
            "hi": "चुंबकत्वमापी 2",
            "te": "మ్యాగ్నెటోమీటర్ 2"
        },
        "Mag 3": {
            "en": "Magnetometer 3",
            "ta": "காந்தமானி 3",
            "hi": "चुंबकत्वमापी 3",
            "te": "మ్యాగ్నెటోమీటర్ 3"
        },
        "Compass Priority Configuration": {
            "en": "Compass Priority Configuration",
            "ta": "திசைகாட்டி முன்னுரிமை உள்ளமைவு",
            "hi": "कंपास प्राथमिकता कॉन्फ़िगरेशन",
            "te": "కంపాస్ ప్రాధాన్యత కాన్ఫిగరేషన్"
        },
        "Configure compass priority order (highest priority at top). Each compass is listed with its device ID, bus configuration, and type.": {
            "en": "Configure compass priority order (highest priority at top). Each compass is listed with its device ID, bus configuration, and type.",
            "ta": "திசைகாட்டி முன்னுரிமை வரிசையை உள்ளமைக்கவும் (மிக உயர்ந்த முன்னுரிமை மேலே). ஒவ்வொரு திசைகாட்டியும் அதன் சாதன ID, பஸ் உள்ளமைவு மற்றும் வகையுடன் பட்டியலிடப்பட்டுள்ளது.",
            "hi": "कंपास प्राथमिकता क्रम कॉन्फ़िगर करें (शीर्ष पर उच्चतम प्राथमिकता)। प्रत्येक कंपास अपने डिवाइस ID, बस कॉन्फ़िगरेशन और प्रकार के साथ सूचीबद्ध है।",
            "te": "కంపాస్ ప్రాధాన్యత క్రమాన్ని కాన్ఫిగర్ చేయండి (టాప్‌లో అత్యధిక ప్రాధాన్యత). ప్రతి కంపాస్ దాని పరికర ID, బస్ కాన్ఫిగరేషన్ మరియు రకంతో జాబితా చేయబడింది."
        },
        "Priority": {
            "en": "Priority",
            "ta": "முன்னுரிமை",
            "hi": "प्राथमिकता",
            "te": "ప్రాధాన్యత"
        },
        "DevID": {
            "en": "Device ID",
            "ta": "சாதன ID",
            "hi": "डिवाइस ID",
            "te": "పరికర ID"
        },
        "Bus Type": {
            "en": "Bus Type",
            "ta": "பஸ் வகை",
            "hi": "बस प्रकार",
            "te": "బస్ రకం"
        },
        "Bus": {
            "en": "Bus",
            "ta": "பஸ்",
            "hi": "बस",
            "te": "బస్"
        },
        "Address": {
            "en": "Address",
            "ta": "முகவரி",
            "hi": "पता",
            "te": "చిరునామా"
        },
        "Dev Type": {
            "en": "Device Type",
            "ta": "சாதன வகை",
            "hi": "डिवाइस प्रकार",
            "te": "పరికర రకం"
        },
        "Missing": {
            "en": "Missing",
            "ta": "காணாமல் போனது",
            "hi": "लापता",
            "te": "లేనిది"
        },
        "External": {
            "en": "External",
            "ta": "வெளிப்புற",
            "hi": "बाहरी",
            "te": "బాహ్య"
        },
        "Actions": {
            "en": "Actions",
            "ta": "நடவடிக்கைகள்",
            "hi": "कार्यों",
            "te": "చర్యలు"
        },
        "Use Compass 1": {
            "en": "Use Compass 1",
            "ta": "திசைகாட்டி 1 ஐ பயன்படுத்தவும்",
            "hi": "कंपास 1 का उपयोग करें",
            "te": "కంపాస్ 1 ను ఉపయోగించండి"
        },
        "Use Compass 2": {
            "en": "Use Compass 2",
            "ta": "திசைகாட்டி 2 ஐ பயன்படுத்தவும்",
            "hi": "कंपास 2 का उपयोग करें",
            "te": "కంపాస్ 2 ను ఉపయోగించండి"
        },
        "Use Compass 3": {
            "en": "Use Compass 3",
            "ta": "திசைகாட்டி 3 ஐ பயன்படுத்தவும்",
            "hi": "कंपास 3 का उपयोग करें",
            "te": "కంపాస్ 3 ను ఉపయోగించండి"
        },
        "Remove Missing": {
            "en": "Remove Missing",
            "ta": "காணாமல் போனதை நீக்கு",
            "hi": "लापता निकालें",
            "te": "లేనిది తీసివేయండి"
        },
        "Calibration Process": {
            "en": "Calibration Process",
            "ta": "அளவீடு செயல்முறை",
            "hi": "कैलिब्रेशन प्रक्रिया",
            "te": "కాలిబ్రేషన్ ప్రక్రియ"
        },
        "Ready": {
            "en": "Ready",
            "ta": "தயாரான",
            "hi": "तैयार",
            "te": "సిద్ధమైనది"
        },
        "Start Calibration": {
            "en": "Start Calibration",
            "ta": "அளவீடு தொடங்கு",
            "hi": "कैलिब्रेशन शुरू करें",
            "te": "కాలిబ్రేషన్ ప్రారంభించండి"
        },
        "Accept Calibration": {
            "en": "Accept Calibration",
            "ta": "அளவீடு ஏற்கவும்",
            "hi": "कैलिब्रेशन स्वीकार करें",
            "te": "కాలిబ్రేషన్‌ను ఆమోదించండి"
        },
        "Cancel": {
            "en": "Cancel",
            "ta": "ரத்து செய்",
            "hi": "रद्द करें",
            "te": "రద్దు చేయండి"
        },
        "Calibration completed": {
            "en": "COMPLETED",
            "ta": "முடிந்தது",
            "hi": "पूर्ण",
            "te": "పూర్తయింది"
        },
        "Magnetometer Progress": {
            "en": "Magnetometer Progress",
            "ta": "காந்தமானி முன்னேற்றம்",
            "hi": "चुंबकत्वमापी प्रगति",
            "te": "మ్యాగ్నెటోమీటర్ పురోగతి"
        },
        "Magnetometer 1": {
            "en": "Magnetometer 1",
            "ta": "காந்தமானி 1",
            "hi": "चुंबकत्वमापी 1",
            "te": "మ్యాగ్నెటోమీటర్ 1"
        },
        "Magnetometer 2": {
            "en": "Magnetometer 2",
            "ta": "காந்தமானி 2",
            "hi": "चुंबकत्वमापी 2",
            "te": "మ్యాగ్నెటోమీటర్ 2"
        },
        "Magnetometer 3": {
            "en": "Magnetometer 3",
            "ta": "காந்தமானி 3",
            "hi": "चुंबकत्वमापी 3",
            "te": "మ్యాగ్నెటోమీటర్ 3"
        },
        "Fitness Level": {
            "en": "Fitness Level",
            "ta": "உপযுक்தता நிலை",
            "hi": "फिटनेस स्तर",
            "te": "ఫిట్‌నెస్ స్థితి"
        },
        "Auto-retry on failure": {
            "en": "Auto-retry on failure",
            "ta": "தோல்வியில் தானியங்கு மீண்டும் முயற்சி",
            "hi": "विफलता पर स्वचालित पुनः प्रयास",
            "te": "విఫలతపై స్వయం-పునः ప్రయత్నం"
        },
        "Calibration completed successfully! Click 'Reboot & Apply' to finalize changes.": {
            "en": "Calibration completed successfully! Click 'Reboot & Apply' to finalize changes.",
            "ta": "அளவீடு வெற்றிகரமாக முடிந்தது! परिवर्तनों को अंतिम रूप देने के लिए 'रিबूट और लागू करें' पर क्लिक करें।",
            "hi": "कैलिब्रेशन सफलतापूर्वक पूर्ण हुआ! परिवर्तनों को अंतिम रूप देने के लिए 'रिबूट और लागू करें' पर क्लिक करें।",
            "te": "కాలిబ్రేషన్ విజయవంతంగా పూర్తయింది! మార్పులను చూడటానికి 'రీబూట్ & అప్లై'ను క్లిక్ చేయండి."
        },
        "Ready to begin calibration process": {
            "en": "Ready to begin calibration process",
            "ta": "அளவீடு செயல்முறை தொடங்க தயாரான",
            "hi": "कैलिब्रेशन प्रक्रिया शुरू करने के लिए तैयार",
            "te": "కాలిబ్రేషన్ ప్రక్రియ ప్రారంభించడానికి సిద్ధమైనది"
        },
        "System Actions": {
            "en": "System Actions",
            "ta": "அமைப்பு நடவடிக்கைகள்",
            "hi": "सिस्टम कार्रवाई",
            "te": "సిస్టమ్ చర్యలు"
        },
        "Reboot Ardupilot": {
            "en": "Reboot Ardupilot",
            "ta": "Ardupilot ஐ மீண்டும் தொடங்கு",
            "hi": "Ardupilot को पुनः प्रारंभ करें",
            "te": "Ardupilot ను పునः ప్రారంభించండి"
        },
        "Large Vehicle MagCal": {
            "en": "Large Vehicle MagCal",
            "ta": "பெரிய வாহன MagCal",
            "hi": "बड़े वाहन MagCal",
            "te": "పెద్ద వాహనం MagCal"
        },
        "Reboot & Apply": {
            "en": "Reboot & Apply",
            "ta": "மீண்டும் தொடங்கு & பயன்படுத்து",
            "hi": "रीबूट और लागू करें",
            "te": "రీబూట్ & అప్లై"
        },
        "Reboot Required": {
            "en": "Reboot Required",
            "ta": "மீண்டும் தொடங்கல் தேவை",
            "hi": "पुनः प्रारंभ आवश्यक",
            "te": "పునः ప్రారంభం అవసరం"
        },
        "Calibration completed successfully": {
            "en": "Calibration completed successfully",
            "ta": "அளவீடு வெற்றிகரமாக முடிந்தது",
            "hi": "कैलिब्रेशन सफलतापूर्वक पूर्ण हुआ",
            "te": "కాలిబ్రేషన్ విజయవంతంగా పూర్తయింది"
        },
        "Reboot required to apply settings. Reboot now?": {
            "en": "Reboot required to apply settings. Reboot now?",
            "ta": "அமைப்புகளைப் பயன்படுத்த மீண்டும் தொடங்கல் தேவை. இப்போது மீண்டும் தொடங்கவா?",
            "hi": "सेटिंग्स लागू करने के लिए पुनः प्रारंभ आवश्यक है। अब रीबूट करें?",
            "te": "సెట్టింగ్‌లను వర్తింపజేయడానికి పునः ప్రారంభం అవసరం. ఇప్పుడు రీబూట్ చేయాలా?"
        },
        "Rebooting autopilot": {
            "en": "Rebooting autopilot",
            "ta": "autopilot ஐ மீண்டும் தொடங்குகிறது",
            "hi": "ऑटोपायलट को पुनः प्रारंभ कर रहे हैं",
            "te": "ఆటోపైలట్‌ను పునः ప్రారంభం చేస్తోంది"
        },
        "please wait": {
            "en": "please wait",
            "ta": "தயவுசெய்து காத்திருக்கவும்",
            "hi": "कृपया प्रतीक्षा करें",
            "te": "దయచేసి ఆగండి"
        },
        "The connection indicator will update automatically": {
            "en": "The connection indicator will update automatically",
            "ta": "সংযোগ సূচक স্বয়ংক্রিয়ভাবে আপডেট হবে",
            "hi": "कनेक्शन संकेतक स्वचालित रूप से अपडेट होगा",
            "te": "సংযోగ సూచిక స్వయంచాలకంగా నవీకరించబడుతుంది"
        },
        "CONNECTED": {
            "en": "Connected",
            "ta": "இணைக்கப்பட்டது",
            "hi": "जुड़ा हुआ",
            "te": "కనెక్ట్ చేయబడింది"
        },
        "DISCONNECTED": {
            "en": "Disconnected",
            "ta": "துண்டிக்கப்பட்டது",
            "hi": "डिस्कनेक्ट किया गया",
            "te": "డిస్‌కనెక్ట్ చేయబడింది"
        }
    })
    
    // ─────────────────────────────────────────────────────────────────────────
    // Function to get translated text
    // ─────────────────────────────────────────────────────────────────────────
    function getText(key) {
        if (translations[key] && translations[key][currentLanguage]) {
            return translations[key][currentLanguage];
        }
        // Fallback to English if translation not found
        return translations[key] ? translations[key]["en"] : key;
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // Function to change language
    // ─────────────────────────────────────────────────────────────────────────
function changeLanguage(languageCode) {
    if (availableLanguages.some(lang => lang.code === languageCode)) {
        currentLanguage = languageCode
        console.log("🌐 Language changed to:", languageCode)
    }
}
    
    // ─────────────────────────────────────────────────────────────────────────
    // Function to get language name
    // ─────────────────────────────────────────────────────────────────────────
    function getLanguageName(code) {
        var lang = availableLanguages.find(lang => lang.code === code);
        return lang ? lang.nativeName : code;
    }
}

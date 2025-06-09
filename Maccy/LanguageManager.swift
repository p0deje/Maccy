import Defaults
import Foundation

// App Languages
enum AppLanguage: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable
{
    case system = "system"
    case english = "en"
    case vietnamese = "vi"
    // Có thể thêm nhiều ngôn ngữ khác
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case russian = "ru"

    var id: Self { self }

    var description: String {
        switch self {
        case .system:
            return NSLocalizedString("LanguageSystem", tableName: "GeneralSettings", comment: "")
        case .english:
            return NSLocalizedString("LanguageEnglish", tableName: "GeneralSettings", comment: "")
        case .vietnamese:
            return NSLocalizedString(
                "LanguageVietnamese", tableName: "GeneralSettings", comment: "")
        case .spanish:
            return NSLocalizedString("LanguageSpanish", tableName: "GeneralSettings", comment: "")
        case .french:
            return NSLocalizedString("LanguageFrench", tableName: "GeneralSettings", comment: "")
        case .german:
            return NSLocalizedString("LanguageGerman", tableName: "GeneralSettings", comment: "")
        case .chinese:
            return NSLocalizedString("LanguageChinese", tableName: "GeneralSettings", comment: "")
        case .japanese:
            return NSLocalizedString("LanguageJapanese", tableName: "GeneralSettings", comment: "")
        case .korean:
            return NSLocalizedString("LanguageKorean", tableName: "GeneralSettings", comment: "")
        case .russian:
            return NSLocalizedString("LanguageRussian", tableName: "GeneralSettings", comment: "")
        }
    }

    var nativeName: String {
        switch self {
        case .system:
            return NSLocalizedString("LanguageSystem", tableName: "GeneralSettings", comment: "")
        case .english:
            return "English"
        case .vietnamese:
            return "Tiếng Việt"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
        case .chinese:
            return "中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .russian:
            return "Русский"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        default:
            return self.rawValue
        }
    }
}

// Language Manager
@Observable
class LanguageManager {
    static let shared = LanguageManager()

    var currentLanguage: AppLanguage {
        didSet {
            if currentLanguage != oldValue {
                applyLanguage()
            }
        }
    }

    private init() {
        self.currentLanguage = Defaults[.appLanguage]
    }

    func applyLanguage() {
        Defaults[.appLanguage] = currentLanguage

        if let localeIdentifier = currentLanguage.localeIdentifier {
            // Set the user language preference
            UserDefaults.standard.set([localeIdentifier], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        } else {
            // Use system language
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }

        // Post notification to update UI
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    func toggleLanguage() {
        let availableLanguages: [AppLanguage] = [.system, .english, .vietnamese]
        let currentIndex = availableLanguages.firstIndex(of: currentLanguage) ?? 0
        let nextIndex = (currentIndex + 1) % availableLanguages.count
        currentLanguage = availableLanguages[nextIndex]
    }

    // Get supported languages (mainly English and Vietnamese as requested)
    static var supportedLanguages: [AppLanguage] {
        return [.system, .english, .vietnamese]
    }
}

// Notification for language changes
extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

// Defaults key for app language
extension Defaults.Keys {
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
}

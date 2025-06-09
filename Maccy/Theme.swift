import Defaults
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case system
    case light
    case dark

    var id: Self { self }

    var description: String {
        switch self {
        case .system:
            return NSLocalizedString("ThemeSystem", tableName: "AppearanceSettings", comment: "")
        case .light:
            return NSLocalizedString("ThemeLight", tableName: "AppearanceSettings", comment: "")
        case .dark:
            return NSLocalizedString("ThemeDark", tableName: "AppearanceSettings", comment: "")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

// Theme Colors
struct ThemeColors {
    // Background colors
    static var backgroundColor: Color {
        Color(.controlBackgroundColor)
    }

    static var cardBackgroundColor: Color {
        Color(.controlColor)
    }

    // Text colors
    static var primaryTextColor: Color {
        Color(.labelColor)
    }

    static var secondaryTextColor: Color {
        Color(.secondaryLabelColor)
    }

    // Accent colors
    static var accentColor: Color {
        Color(.controlAccentColor)
    }

    // Border colors
    static var borderColor: Color {
        Color(.separatorColor)
    }

    // Selected item colors
    static var selectedBackgroundColor: Color {
        Color(.selectedControlColor)
    }

    static var selectedTextColor: Color {
        Color(.selectedControlTextColor)
    }
}

// Theme Manager
@Observable
class ThemeManager {
    static let shared = ThemeManager()

    var currentTheme: AppTheme {
        didSet {
            applyTheme()
        }
    }

    private init() {
        self.currentTheme = Defaults[.appTheme]
    }

    func applyTheme() {
        Defaults[.appTheme] = currentTheme

        DispatchQueue.main.async {
            if let appearance = self.currentTheme.colorScheme?.nsAppearance {
                NSApp.appearance = appearance
            } else {
                NSApp.appearance = nil  // Use system default
            }
        }
    }
}

// Extension to convert ColorScheme to NSAppearance
extension ColorScheme {
    var nsAppearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        @unknown default:
            return nil
        }
    }
}

// Defaults extension for AppTheme
extension Defaults.Keys {
    static let appTheme = Key<AppTheme>("appTheme", default: .system)
}

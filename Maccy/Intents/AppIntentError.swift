import Foundation

/// Errors raised by App Intents that interact with clipboard history.
enum AppIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
  /// No matching clipboard item exists for the requested index or selection.
  case notFound

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notFound: return "Clipboard item not found"
    }
  }
}

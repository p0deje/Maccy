import Foundation

enum AppIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
  case notFound

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notFound: return "Clipboard item not found"
    }
  }
}

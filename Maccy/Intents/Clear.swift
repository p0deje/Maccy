import AppIntents
import Defaults

/// App Intent that clears all non-pinned items from clipboard history.
struct Clear: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "ClearIntent"

  static let title: LocalizedStringResource = "Clear Clipboard History"
  static let description = IntentDescription("Clears all Maccy clipboard history except for pinned items.")

  static var parameterSummary: some ParameterSummary {
    Summary("Clear Clipboard History")
  }

  /// Clears history after optionally confirming with the user.
  func perform() async throws -> some IntentResult {
    if !Defaults[.suppressClearAlert] {
      try await requestConfirmation()
    }

    await AppState.shared.history.clear()
    return .result()
  }
}

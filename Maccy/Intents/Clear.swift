import AppIntents
import Defaults

struct Clear: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "ClearIntent"

  static var title: LocalizedStringResource = "Clear Clipboard History"
  static var description = IntentDescription("Clears all Maccy clipboard history except for pinned items.")

  static var parameterSummary: some ParameterSummary {
    Summary("Clear Clipboard History")
  }

  func perform() async throws -> some IntentResult {
    if !Defaults[.suppressClearAlert] {
      try await requestConfirmation()
    }

    await AppState.shared.history.clear()
    return .result()
  }
}

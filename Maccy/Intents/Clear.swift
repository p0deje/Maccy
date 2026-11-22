import AppIntents
import Defaults

struct Clear: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "ClearIntent"

  static let title: LocalizedStringResource = "Clear Clipboard History"
  static let description = IntentDescription(
    "Clears all Maccy clipboard history except for pinned and protected items."
  )

  static var parameterSummary: some ParameterSummary {
    Summary("Clear Clipboard History")
  }

  func perform() async throws -> some IntentResult {
    if !Defaults[.suppressClearAlert] {
      try await requestConfirmation()
    }

    guard await AppState.shared.history.clear() else {
      throw HistoryStorageError()
    }
    return .result()
  }
}

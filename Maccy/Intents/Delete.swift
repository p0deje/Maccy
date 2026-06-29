import AppIntents

/// App Intent that deletes a single item by its 1-based position in history.
struct Delete: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "DeleteIntent"

  static let title: LocalizedStringResource = "Delete Item from Clipboard History"
  static let description = IntentDescription("Deletes an item from Maccy clipboard history.")

  /// 1-based position of the item to delete.
  @Parameter(title: "Number", default: 1)
  var number: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Delete \(\.$number) Item from Clipboard History")
  }

  /// Converts the 1-based `number` parameter to a 0-based collection index.
  private let positionOffset = 1

  @MainActor func perform() async throws -> some IntentResult {
    let items = AppState.shared.history.items
    let index = number - positionOffset
    guard index >= 0, items.count > index else {
      throw AppIntentError.notFound
    }

    AppState.shared.history.delete(items[index])

    return .result()
  }
}

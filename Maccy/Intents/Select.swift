import AppIntents

/// App Intent that selects an item by its 1-based position in history.
struct Select: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "SelectIntent"

  static let title: LocalizedStringResource = "Select Item in Clipboard History"
  static let description = IntentDescription("""
  Selects an item in Maccy clipboard history.
  Depending on Maccy settings, it might trigger pasting of the selected item.
  """)

  static var parameterSummary: some ParameterSummary {
    Summary("Select \(\.$number) Item in Clipboard History")
  }

  /// 1-based position of the item to select.
  @Parameter(title: "Number", default: 1, requestValueDialog: "What is the number of the item?")
  var number: Int

  /// Converts the 1-based `number` parameter to a 0-based collection index.
  private let positionOffset = 1

  /// Selects the item at `number` and returns its title.
  @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let items = AppState.shared.history.items
    let index = number - positionOffset
    guard index >= 0, items.count > index else {
      throw AppIntentError.notFound
    }

    let value = items[index].title
    AppState.shared.history.select(items[index])

    return .result(value: value)
  }
}

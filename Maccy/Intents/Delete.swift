import AppIntents

struct Delete: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "DeleteIntent"

  static let title: LocalizedStringResource = "Delete Item from Clipboard History"
  static let description = IntentDescription("Deletes an item from Maccy clipboard history.")

  @Parameter(title: "Number", default: 1)
  var number: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Delete \(\.$number) Item from Clipboard History")
  }

  private let positionOffset = 1

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      let items = AppState.shared.history.items
      let index = number - positionOffset
      guard items.count >= index else {
        throw AppIntentError.notFound
      }

      AppState.shared.history.delete(items[index])
    }

    return .result()
  }
}

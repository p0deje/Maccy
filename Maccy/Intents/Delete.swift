import AppIntents

struct Delete: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "DeleteIntent"

  static var title: LocalizedStringResource = "Delete Item from Clipboard History"
  static var description = IntentDescription("Deletes an item from Maccy clipboard history.")

  @Parameter(title: "Number", default: 1)
  var number: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Delete \(\.$number) Item from Clipboard History")
  }

  private let positionOffset = 1

  @Dependency(key: "maccy")
  private var maccy: Maccy

  func perform() async throws -> some IntentResult {
    guard let value = maccy.delete(position: number - positionOffset) else {
      throw AppIntentError.notFound
    }

    return .result()
  }
}

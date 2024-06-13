import AppIntents

struct Select: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "SelectIntent"

  static var title: LocalizedStringResource = "Select Item in Clipboard History"
  static var description = IntentDescription("Selects an item in Maccy clipboard history. Depending on Maccy settings, it might trigger pasting of the selected item.")

  static var parameterSummary: some ParameterSummary {
    Summary("Select \(\.$number) Item in Clipboard History")
  }

  @Parameter(title: "Number", default: 1, requestValueDialog: "What is the number of the item?")
  var number: Int

  private let positionOffset = 1

  @Dependency(key: "maccy")
  private var maccy: Maccy

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    guard let value = maccy.select(position: number - positionOffset) else {
      throw AppIntentError.notFound
    }

    return .result(value: value)
  }
}

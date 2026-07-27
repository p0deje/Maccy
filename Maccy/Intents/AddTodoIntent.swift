import AppIntents

struct AddTodoIntent: AppIntent {
  static var title: LocalizedStringResource = "Add Todo"
  static var description = IntentDescription("Adds a todo in Maccy.")

  static var openAppWhenRun: Bool = true

  @Parameter(title: "Title")
  var title: String

  static var parameterSummary: some ParameterSummary {
    Summary("Add todo \(\.$title)")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    _ = Todos.shared.add(title: title)
    return .result()
  }
}

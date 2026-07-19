import AppIntents

struct CompleteTodoIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete Todo"
  static var description = IntentDescription(
    "Marks an incomplete todo complete by title, or opens the Todos window if none match."
  )

  static var openAppWhenRun: Bool = true

  @Parameter(title: "Title")
  var title: String

  static var parameterSummary: some ParameterSummary {
    Summary("Complete todo \(\.$title)")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let todos = Todos.shared
    let incomplete = todos.items.filter { !$0.isCompleted }

    let match = incomplete.first {
      $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
    } ?? incomplete.first {
      $0.title.localizedCaseInsensitiveContains(trimmed)
    }

    if let match {
      todos.toggleComplete(match, source: .menu)
      return .result()
    }

    // No match — open Todos so the user can complete manually.
    AppState.shared.appDelegate?.openTodosWindow()
    return .result()
  }
}

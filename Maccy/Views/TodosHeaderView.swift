import SwiftUI

struct TodosHeaderView: View {
  @Environment(AppState.self) private var appState
  @FocusState.Binding var searchFocused: Bool

  var body: some View {
    HStack {
      TextField(
        NSLocalizedString("SearchTodos", tableName: "Todos", comment: ""),
        text: Binding(
          get: { appState.todos.searchQuery },
          set: { appState.todos.searchQuery = $0 }
        )
      )
      .textFieldStyle(.plain)
      .focused($searchFocused)
    }
    .padding(.horizontal, Popup.horizontalPadding)
    .padding(.vertical, 6)
  }
}

import SwiftUI

struct TodosToolbarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)

      HStack(spacing: 12) {
        Button {
          _ = appState.todos.add()
        } label: {
          Label(NSLocalizedString("NewTodo", tableName: "Todos", comment: ""), systemImage: "plus")
        }
        .buttonStyle(.plain)

        Spacer()

        Button {
          if let selected = appState.todos.selectedItem {
            appState.todos.toggleComplete(selected, source: .menu)
          }
        } label: {
          Text(NSLocalizedString("ToggleDone", tableName: "Todos", comment: ""))
        }
        .buttonStyle(.plain)
        .disabled(appState.todos.selectedItem == nil)

        Button(role: .destructive) {
          if let selected = appState.todos.selectedItem {
            appState.todos.delete(selected)
          }
        } label: {
          Text(NSLocalizedString("Delete", tableName: "Todos", comment: ""))
        }
        .buttonStyle(.plain)
        .disabled(appState.todos.selectedItem == nil)

        Button {
          appState.openPreferences()
        } label: {
          Text(NSLocalizedString("preferences", tableName: "Localizable", comment: ""))
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 12)
      .font(.callout)
    }
    .readHeight(appState, into: \.popup.extraTopHeight)
  }
}

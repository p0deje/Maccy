import SwiftUI

struct TodosSlideoutContentView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let selected = appState.todos.selectedItem {
        TodoSlideoutToolbarView(item: selected)
          .padding(.horizontal, 12)

        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            TodoSlideoutHeaderView(item: selected)
              .id(selected.id)

            TodoDetailView(item: selected)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
        }
      } else {
        TodoEmptyStateView(
          systemImage: "sidebar.left",
          message: NSLocalizedString("SelectTodoForDetails", tableName: "Todos", comment: "")
        )
        .frame(maxHeight: .infinity)
      }
    }
    .padding(.top, Popup.verticalPadding)
  }
}

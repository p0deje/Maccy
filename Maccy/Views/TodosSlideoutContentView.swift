import SwiftUI

struct TodosSlideoutContentView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let selected = appState.todos.selectedItem {
        ScrollView {
          TodoDetailView(item: selected)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(selected.id)
        }
      } else {
        Text(NSLocalizedString("SelectTodoForDetails", tableName: "Todos", comment: ""))
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }
}

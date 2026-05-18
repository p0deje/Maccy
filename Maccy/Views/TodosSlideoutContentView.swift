import SwiftUI

struct TodosSlideoutContentView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack {
      if let selected = appState.todos.selectedItem {
        ScrollView {
          TodoDetailView(item: selected)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(selected.id)
        }
      } else {
        EmptyView()
      }
    }
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }
}

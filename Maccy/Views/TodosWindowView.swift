import SwiftUI

struct TodosWindowView: View {
  @State private var appState = AppState.shared
  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      KeyHandlingView(
        searchQuery: $appState.todos.searchQuery,
        searchFocused: $searchFocused
      ) {
        SlideoutView(controller: appState.preview) {
          VStack(alignment: .leading, spacing: 0) {
            PopupSearchHeaderView(
              searchFocused: $searchFocused,
              searchQuery: $appState.todos.searchQuery,
              placeholder: LocalizedStringKey(
                String(localized: "SearchTodos", table: "Todos")
              ),
              controller: appState.preview
            )
            TodosToolbarView()
            TodosListView(searchFocused: $searchFocused)
              .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
          }
          .padding(.horizontal, Popup.horizontalPadding)
          .onMouseMove {
            appState.todos.isKeyboardNavigating = false
          }
        } slideout: {
          TodosSlideoutContentView()
        }
      }
      .padding(.top, Popup.verticalPadding)
    }
    .environment(appState)
    .task {
      try? appState.todos.load()
    }
    .onAppear {
      appState.activeTab = .todos
      appState.prepareTodosTab()
      searchFocused = true
    }
  }
}

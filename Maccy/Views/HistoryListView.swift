import SwiftUI

struct HistoryListView: View {
  @Environment(AppState.self) private var appState

  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  var body: some View {
    LazyVStack(spacing: 0) {
      ForEach(appState.history.items) { item in
        HistoryItemView(item: item)
      }
    }
    // Use overlay to calculate the total height inside a scroll view.
    .overlay(
      GeometryReader { geo in
        EmptyView()
          .onChange(of: appState.needsResize) {
            if appState.needsResize {
              appState.popup.resize(height: geo.size.height)
            }
          }
      }
    )
  }
}

import SwiftUI

/// Renders the pinned-items section of the history list.
struct PinsView: View {
  @Environment(AppState.self) private var appState

  var items: [HistoryItemDecorator]

  var body: some View {
    MultipleSelectionListView(items: items) { previous, item, next, index in
      HistoryItemView(item: item, previous: previous, next: next, index: index)
    }
  }
}

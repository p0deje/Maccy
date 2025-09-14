import SwiftUI

struct PinsView: View {
  @Environment(AppState.self) private var appState

  var items: [HistoryItemDecorator]

  var body: some View {
    LazyVStack(spacing: 0) {
      ForEach(items) { item in
        HistoryItemView(item: item)
      }
    }
    .readHeight(appState, into: \.popup.pinnedItemsHeight)
  }
}

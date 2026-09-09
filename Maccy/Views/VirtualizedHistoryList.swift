import Defaults
import SwiftUI

/// History-specific wrapper around `VirtualizedList`: builds row metrics from
/// history state, maps visible rows to page requests, and bridges keyboard
/// navigation (scroll target) and popup resizing.
struct VirtualizedHistoryList: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.imageMaxHeight) private var imageMaxHeight

  private var metrics: VirtualListMetrics {
    VirtualListMetrics(
      rowHeight: Popup.itemHeight,
      tallRowHeight: CGFloat(imageMaxHeight) + 10,
      totalCount: appState.history.unpinnedTotalCount,
      tallRowIndices: appState.history.tallRowIndices
    )
  }

  private var loadedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems
  }

  private var loadedRange: Range<Int> {
    appState.history.loadedRange
  }

  private var scrollTargetRow: Int? {
    guard let target = appState.navigator.scrollTarget,
          let position = loadedItems.firstIndex(where: { $0.id == target }) else {
      return nil
    }
    return loadedRange.lowerBound + position
  }

  var body: some View {
    VirtualizedList(
      metrics: metrics,
      scrollTargetRow: scrollTargetRow,
      onVisibleRowsChanged: { rows in
        appState.history.ensureLoaded(rows: rows)
      },
      onScrollTargetHandled: {
        appState.navigator.scrollTarget = nil
      }
    ) { index in
      rowView(at: index)
    }
    .task(id: appState.popup.needsResize) {
      try? await Task.sleep(for: .milliseconds(10))
      guard !Task.isCancelled, appState.popup.needsResize else { return }

      appState.popup.resize(height: metrics.totalHeight)
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        searchFocused = true
        appState.navigator.isKeyboardNavigating = true
        appState.navigator.select(item: appState.history.unpinnedItems.first ?? appState.history.pinnedItems.first)
        appState.preview.enableAutoOpen()
        appState.preview.resetAutoOpenSuppression()
        appState.preview.startAutoOpen()
      } else {
        modifierFlags.flags = []
        appState.navigator.isKeyboardNavigating = true
        appState.preview.cancelAutoOpen()
      }
    }
  }

  @ViewBuilder
  private func rowView(at index: Int) -> some View {
    let range = loadedRange
    if range.contains(index), index - range.lowerBound < loadedItems.count {
      let item = loadedItems[index - range.lowerBound]
      HistoryItemView(item: item, previous: nil, next: nil, index: index)
    } else {
      // Not loaded yet; VirtualizedList reserves the correct height.
      Color.clear
    }
  }
}

import Defaults
import SwiftUI

/// A virtualized list view for history items using custom layout.
/// Eliminates scrolling jumps by using precise positioning and view recycling.
struct VirtualizedHistoryList: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.previewDelay) private var previewDelay

  /// Height for text-only items
  private var textItemHeight: CGFloat { Popup.itemHeight }

  /// Height for image items (includes padding)
  private var imageItemHeight: CGFloat { CGFloat(Defaults[.imageMaxHeight]) + 10 }

  /// Average item height for scroll calculations
  /// Since most items are text, weight heavily toward text height
  private var averageItemHeight: CGFloat {
    textItemHeight
  }

  /// Maximum number of items that can be visible at once
  /// Used for view recycling to limit memory usage
  private var maxVisibleItems: Int {
    // Estimate based on a reasonable window height (e.g., 800px)
    // Add generous buffer for smooth scrolling
    Int((800 / averageItemHeight) * 3)
  }

  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }

  private var totalItemCount: Int {
    appState.history.totalCount
  }

  private var loadedRange: Range<Int> {
    let start = appState.history.windowStartIndex
    let end = start + unpinnedItems.count
    return start..<end
  }

  var body: some View {
    VirtualizedListContainer(
      totalCount: totalItemCount,
      itemHeight: averageItemHeight,
      loadedRange: loadedRange,
      loadedItems: unpinnedItems,
      maxVisibleItems: maxVisibleItems,
      onLoadPrevious: {
        Task {
          await appState.history.loadPreviousItems()
        }
      },
      onLoadNext: {
        Task {
          await appState.history.loadMoreItems()
        }
      }
    )
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
}

import Defaults
import SwiftUI

/// A virtualized list view for history items that properly handles pagination
/// and maintains correct scroll position across page transitions.
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

  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }

  private var totalItemCount: Int {
    appState.history.totalCount
  }

  var body: some View {
    GeometryReader { outerGeo in
      ScrollViewReader { proxy in
        ScrollView {
          VirtualizedListContent(
            items: unpinnedItems,
            totalCount: totalItemCount,
            windowStartIndex: appState.history.windowStartIndex,
            hasMoreBefore: appState.history.hasMoreItemsBefore,
            hasMoreAfter: appState.history.hasMoreItems,
            isLoading: appState.history.isLoadingMore,
            averageItemHeight: averageItemHeight,
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
          .task(id: appState.navigator.scrollTarget) {
            guard appState.navigator.scrollTarget != nil else { return }

            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }

            if let selection = appState.navigator.scrollTarget {
              proxy.scrollTo(selection)
              appState.navigator.scrollTarget = nil
            }
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
          .background {
            GeometryReader { geo in
              Color.clear
                .task(id: appState.popup.needsResize) {
                  try? await Task.sleep(for: .milliseconds(10))
                  guard !Task.isCancelled else { return }

                  if appState.popup.needsResize {
                    appState.popup.resize(height: geo.size.height)
                  }
                }
            }
          }
        }
        .contentMargins(.leading, 10, for: .scrollIndicators)
      }
    }
  }
}

/// The content of the virtualized list with proper spacers for scroll position
private struct VirtualizedListContent: View {
  let items: [HistoryItemDecorator]
  let totalCount: Int
  let windowStartIndex: Int
  let hasMoreBefore: Bool
  let hasMoreAfter: Bool
  let isLoading: Bool
  let averageItemHeight: CGFloat
  let onLoadPrevious: () -> Void
  let onLoadNext: () -> Void

  @State private var hasTriggeredLoadPrevious = false
  @State private var hasTriggeredLoadNext = false

  var body: some View {
    LazyVStack(spacing: 0) {
      // Invisible spacer representing items before the current window
      // This makes the scrollbar reflect the true list size
      if hasMoreBefore {
        Color.clear
          .frame(height: estimatedHeightBefore)
          .id("spacer-before")
      }

      // Sentinel view to detect when user scrolls to the top of loaded content
      if hasMoreBefore {
        Color.clear
          .frame(height: 1)
          .onAppear {
            if !hasTriggeredLoadPrevious {
              hasTriggeredLoadPrevious = true
              onLoadPrevious()
            }
          }
          .onDisappear {
            hasTriggeredLoadPrevious = false
          }
      }

      // Actual visible items
      ForEach(items) { item in
        HistoryItemView(item: item)
      }

      // Sentinel view to detect when user scrolls to the bottom of loaded content
      if hasMoreAfter {
        Color.clear
          .frame(height: 1)
          .onAppear {
            if !hasTriggeredLoadNext {
              hasTriggeredLoadNext = true
              onLoadNext()
            }
          }
          .onDisappear {
            hasTriggeredLoadNext = false
          }
      }

      // Loading indicator
      if isLoading {
        HStack {
          Spacer()
          ProgressView()
            .controlSize(.small)
            .padding(.vertical, 10)
          Spacer()
        }
      }

      // Invisible spacer representing items after the current window
      if hasMoreAfter {
        Color.clear
          .frame(height: estimatedHeightAfter)
          .id("spacer-after")
      }
    }
  }

  /// Estimated height of all items before the current window
  private var estimatedHeightBefore: CGFloat {
    CGFloat(windowStartIndex) * averageItemHeight
  }

  /// Estimated height of all items after the current window
  private var estimatedHeightAfter: CGFloat {
    let itemsAfter = max(0, totalCount - windowStartIndex - items.count)
    return CGFloat(itemsAfter) * averageItemHeight
  }
}

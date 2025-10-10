import Defaults
import SwiftUI

struct HistoryListView: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  @Default(.pinTo) private var pinTo
  @Default(.previewDelay) private var previewDelay

  private var pinnedItems: [HistoryItemDecorator] {
    let pinSortBy = Defaults[.pinSortBy]
    let ascending = Defaults[.pinSortAscending]
    return appState.history.pinnedItems.filter(\.isVisible).sorted {
      switch pinSortBy {
      case .firstCopiedAt:
        return ascending ? ($0.item.firstCopiedAt < $1.item.firstCopiedAt) : ($0.item.firstCopiedAt > $1.item.firstCopiedAt)
      case .lastCopiedAt:
        return ascending ? ($0.item.lastCopiedAt < $1.item.lastCopiedAt) : ($0.item.lastCopiedAt > $1.item.lastCopiedAt)
      case .numberOfCopies:
        return ascending ? ($0.item.numberOfCopies < $1.item.numberOfCopies) : ($0.item.numberOfCopies > $1.item.numberOfCopies)
      case .pinKey:
        // Ascending: A-Z, Descending: Z-A
        return ascending ? (($0.item.pin ?? "") < ($1.item.pin ?? "")) : (($0.item.pin ?? "") > ($1.item.pin ?? ""))
      }
    }
  }
  private var unpinnedItems: [HistoryItemDecorator] {
    let sortBy = Defaults[.sortBy]
    let ascending = Defaults[.sortAscending]
    return appState.history.unpinnedItems.filter(\.isVisible).sorted {
      switch sortBy {
      case .firstCopiedAt:
        return ascending ? ($0.item.firstCopiedAt < $1.item.firstCopiedAt) : ($0.item.firstCopiedAt > $1.item.firstCopiedAt)
      case .lastCopiedAt:
        return ascending ? ($0.item.lastCopiedAt < $1.item.lastCopiedAt) : ($0.item.lastCopiedAt > $1.item.lastCopiedAt)
      case .numberOfCopies:
        return ascending ? ($0.item.numberOfCopies < $1.item.numberOfCopies) : ($0.item.numberOfCopies > $1.item.numberOfCopies)
      case .pinKey:
        return ascending ? (($0.item.pin ?? "") < ($1.item.pin ?? "")) : (($0.item.pin ?? "") > ($1.item.pin ?? ""))
      }
    }
  }
  private var showPinsSeparator: Bool {
    !pinnedItems.isEmpty && !unpinnedItems.isEmpty && appState.history.searchQuery.isEmpty
  }

  var body: some View {
    if pinTo == .top {
      LazyVStack(spacing: 0) {
        ForEach(pinnedItems) { item in
          HistoryItemView(item: item)
        }

        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = geo.size.height
            }
        }
      }
    }

    ScrollView {
      ScrollViewReader { proxy in
        LazyVStack(spacing: 0) {
          ForEach(unpinnedItems) { item in
            HistoryItemView(item: item)
          }
        }
        .task(id: appState.scrollTarget) {
          guard appState.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.scrollTarget {
            proxy.scrollTo(selection)
            appState.scrollTarget = nil
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .active {
            searchFocused = true
            HistoryItemDecorator.previewThrottler.minimumDelay = Double(previewDelay) / 1000
            HistoryItemDecorator.previewThrottler.cancel()
            appState.isKeyboardNavigating = true
            appState.selection = appState.history.unpinnedItems.first?.id ?? appState.history.pinnedItems.first?.id
          } else {
            modifierFlags.flags = []
            appState.isKeyboardNavigating = true
          }
        }
        // Calculate the total height inside a scroll view.
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

    if pinTo == .bottom {
      LazyVStack(spacing: 0) {
        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }

        ForEach(pinnedItems) { item in
          HistoryItemView(item: item)
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = geo.size.height
            }
        }
      }
    }
  }
}

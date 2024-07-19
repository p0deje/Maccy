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

  var body: some View {
    if !appState.history.pinnedItems.isEmpty, pinTo == .top {
      LazyVStack(spacing: 0) {
        ForEach(appState.history.pinnedItems) { item in
          HistoryItemView(item: item)
        }
      }
    }

    ScrollView {
      ScrollViewReader { proxy in
        LazyVStack(spacing: 0) {
          ForEach(appState.history.unpinnedItems) { item in
            HistoryItemView(item: item)
          }
        }
        .onChange(of: appState.selection) {
          if let selection = appState.selection {
            proxy.scrollTo(selection)
          }
        }
        .onChange(of: scenePhase) {
          if scenePhase == .active {
            searchFocused = true
            appState.selection = appState.history.unpinnedItems.first?.id
          } else {
            HistoryItemDecorator.previewThrottler.minimumDelay = Double(previewDelay) / 1000
            modifierFlags.flags = []
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
      .contentMargins(.leading, 10, for: .scrollIndicators)
    }
    

    if !appState.history.pinnedItems.isEmpty, pinTo == .bottom {
      LazyVStack(spacing: 0) {
        ForEach(appState.history.pinnedItems) { item in
          HistoryItemView(item: item)
        }
      }
    }
  }
}

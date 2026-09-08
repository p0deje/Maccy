import Defaults
import SwiftUI

struct HeaderView: View {
  @Default(.extendedHistory) private var extendedHistory
  @State private var appState = AppState.shared

  let controller: SlideoutController
  @FocusState.Binding var searchFocused: Bool

  var previewPlacement: SlideoutPlacement {
    return controller.placement
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .center, spacing: 0) {
        ListHeaderView(
          searchFocused: $searchFocused,
          searchQuery: $appState.history.searchQuery
        )
        .padding(.horizontal, Popup.horizontalPadding)

        ToolbarButton {
          controller.togglePreview()
        } label: {
          Image(
            systemName: previewPlacement == .right
              ? "sidebar.left" : "sidebar.right"
          )
        }
        .shortcutKeyHelp(
          name: .togglePreview,
          key: controller.state.isOpen ? "ClosePreview" : "OpenPreview",
          tableName: "PreviewItemView",
          replacementKey: "previewKey"
        )
        .padding(.trailing, Popup.horizontalPadding)
      }
      .opacity(appState.searchVisible ? 1 : 0)
      .accessibilityHidden(!appState.searchVisible)
      .frame(maxHeight: appState.searchVisible ? nil : 0)
      .layoutPriority(1)

      if extendedHistory {
        HStack(spacing: 8) {
          Button("deep_search") { appState.history.startDeepSearch() }
            .disabled(appState.history.deepSearchLoading)
            .accessibilityIdentifier("deepSearch")
          if appState.history.deepSearchActive {
            Button("recent_history") { appState.history.endDeepSearch() }
            if appState.history.deepSearchLoading {
              ProgressView().controlSize(.mini)
            } else {
              Text("\(appState.history.items.count)").foregroundStyle(.secondary)
              if appState.history.deepSearchHasMore {
                Button("next_page") { appState.history.startDeepSearch(nextPage: true) }
              }
            }
          } else {
            Text("recent_history_scope").foregroundStyle(.secondary)
          }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.horizontal, Popup.horizontalPadding)
        if appState.history.deepSearchActive {
          Text(appState.history.deepSearchError ?? NSLocalizedString("deep_search_scope", comment: ""))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Popup.horizontalPadding)
        }
      }
    }
    .padding(.top, Popup.verticalPadding)
    .padding(.horizontal, 10)
    .animation(.default.speed(3), value: appState.navigator.leadSelection)
    .background(.clear)
    .frame(maxHeight: !appState.searchVisible && !extendedHistory ? 0 : nil, alignment: .top)
    .readHeight(appState, into: \.popup.headerHeight)
  }
}

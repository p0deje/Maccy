import Defaults
import KeyboardShortcuts
import SwiftUI

struct PopupSearchHeaderView: View {
  @Environment(AppState.self) private var appState
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String
  let placeholder: LocalizedStringKey
  let controller: SlideoutController

  @Default(.showTitle) private var showTitle

  private var previewPlacement: SlideoutPlacement {
    controller.placement
  }

  private var headerAnimationToken: UUID? {
    appState.activeTab == .clipboard ? appState.navigator.leadSelection : appState.todos.selectedId
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        HStack {
          if showTitle {
            Text("Maccy")
              .foregroundStyle(.secondary)
              .padding(.leading, 5)
          }

          SearchFieldView(placeholder: placeholder, query: $searchQuery)
            .focused($searchFocused)
            .frame(maxWidth: .infinity)
            .offset(y: appState.searchVisible ? 0 : -Popup.itemHeight)
        }
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
          key: "PreviewKey",
          tableName: "PreviewItemView",
          replacementKey: "previewKey"
        )
        .padding(.trailing, Popup.horizontalPadding)
      }
      .opacity(appState.searchVisible ? 1 : 0)
      .layoutPriority(1)
    }
    .padding(.top, Popup.verticalPadding)
    .padding(.horizontal, 10)
    .animation(.default.speed(3), value: headerAnimationToken)
    .background(.clear)
    .frame(maxHeight: !appState.searchVisible ? 0 : nil, alignment: .top)
    .readHeight(appState, into: \.popup.headerHeight)
  }
}

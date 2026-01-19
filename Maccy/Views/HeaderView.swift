import Defaults
import SwiftUI

struct HeaderView: View {
  @State private var appState = AppState.shared

  let controller: SlideoutController
  @FocusState.Binding var searchFocused: Bool

  var previewPlacement: SlideoutPlacement {
    return controller.placement
  }

  @ViewBuilder
  private func toolbar(alignment: Alignment) -> some View {
    HStack(spacing: 0) {
      if alignment == .topLeading {
        Spacer()
      }
      ToolbarView()
        .padding(.horizontal, Popup.horizontalPadding)
      if alignment == .topTrailing {
        Spacer()
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if previewPlacement == .left {
        toolbar(alignment: .topTrailing)
      }

      HStack(alignment: .center, spacing: 0) {
        ListHeaderView(
          searchFocused: $searchFocused,
          searchQuery: $appState.history.searchQuery
        )
        .padding(.horizontal, Popup.horizontalPadding)
        .frame(
          maxWidth: previewPlacement == .right
            ? controller.contentWidth : nil
        )
        .opacity(appState.searchVisible ? 1 : 0)

        HStack {
          ToolbarButton {
            controller.togglePreview()
          } label: {
            Image(
              systemName: previewPlacement == .right
                ? "sidebar.right" : "sidebar.left"
            )
          }
        }
        .padding(.trailing, Popup.horizontalPadding)
        .padding(
          .leading,
          appState.preview.state.isOpen ? Popup.horizontalPadding : 0
        )
        .opacity(
          !appState.preview.state.isOpen && !appState.searchVisible ? 0 : 1
        )
      }
      .frame(
        idealWidth: previewPlacement == .left
          ? controller.contentWidth : nil,
        maxWidth: previewPlacement == .left
          ? controller.contentWidth : nil
      )
      .layoutPriority(1)

      if previewPlacement == .right {
        toolbar(alignment: .topLeading)
      }
    }
    .padding(.top, Popup.verticalPadding)
    .readHeight(appState, into: \.popup.realHeaderHeight)
    .animation(.default.speed(3), value: appState.navigator.leadSelection)
    .background(.clear)
    .frame(maxHeight: !appState.searchVisible ? 0 : nil, alignment: .top)
    .readHeight(appState, into: \.popup.headerHeight)
  }
}

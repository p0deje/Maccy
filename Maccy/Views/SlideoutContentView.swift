import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack {
      ToolbarView()

      if appState.preview.state != .open {
        EmptyView()
      } else if let item = appState.navigator.leadHistoryItem {
        PreviewItemView(item: item)
          .id(item.id)
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }

}

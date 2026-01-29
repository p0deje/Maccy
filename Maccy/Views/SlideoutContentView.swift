import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack {
      if let item = appState.navigator.leadHistoryItem {
        PreviewItemView(item: item)
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .padding()
  }

}

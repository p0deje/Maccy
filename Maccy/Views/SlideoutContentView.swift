import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack {
      ToolbarView()

      if let item = appState.navigator.leadHistoryItem {
        // `.id(item.id)` forces a fresh PreviewItemView (and its AsyncView +
        // @State + one-shot `.task`) per lead item, so the preview re-renders
        // as the selection moves. Without it, PreviewItemView keeps structural
        // identity across selection changes and AsyncView's `.task` never
        // re-runs — the preview shows the first item's image stuck on nav.
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

import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack {
      ToolbarView()

      if let item = appState.preview.previewedItem {
        // `.id(item.id)` forces a fresh PreviewItemView (and its AsyncView +
        // @State + one-shot `.task`) whenever `previewedItem` changes, so the
        // preview re-renders as the retargeted item changes. `previewedItem` is
        // set on retarget-fire (scheduleRetarget) or manual open — NOT on every
        // lead change — so the pane doesn't chase every selection. Without
        // `.id`, PreviewItemView keeps structural identity and AsyncView's
        // `.task` never re-runs — the preview shows the first item stuck.
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

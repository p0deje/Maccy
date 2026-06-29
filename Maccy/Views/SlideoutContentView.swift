import SwiftUI

/// Right-hand content of the slideout pane: a toolbar plus either the preview
/// of the currently previewed item, a paste-stack preview, or nothing.
struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    VStack {
      ToolbarView()

      if let item = appState.preview.previewedItem {
        // `.id(item.id)` forces a fresh `PreviewItemView` (and its `AsyncView`,
        // `@State`, and one-shot `.task`) whenever the previewed item changes,
        // so the preview re-renders for the new item. The previewed item is set
        // only on explicit preview/open, not on every selection, so the pane
        // does not chase each selection. Without `.id`, `PreviewItemView` keeps
        // structural identity, its `.task` never re-runs, and the preview would
        // stay stuck on the first item.
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

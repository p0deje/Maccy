import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  var body: some View {
    if let item = appState.previewItem {
      PreviewItemView(item: item)
        .onAppear {
          item.ensurePreviewImage()
        }
    }
  }

}

import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  @Bindable var item: HistoryItemDecorator

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if item.item.image != nil {
        if let image = item.previewImage {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 5))
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200)
        }
      } else {
        Text(item.text)
          .font(.body)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
    .controlSize(.small)
    .padding()
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .task(id: item.id) {
      await MainActor.run {
        item.ensurePreviewImage()
      }
    }
  }
}

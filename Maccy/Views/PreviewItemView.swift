import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  var item: HistoryItemDecorator

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: "info.circle")
        .imageScale(.large)
        .padding(.bottom, 3)
        .padding(.top, -6)
        .padding(.leading, -3)

      if let image = item.previewImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(.rect(cornerRadius: 5))
      } else {
        ScrollView {
          Text(item.text)
            .font(.body)
        }
      }

      Divider()
        .padding(.vertical)

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "PreviewItemView")
          AppImageView(
            appImage: item.applicationImage,
            size: NSSize(width: 11, height: 11)
          )
          Text(application)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "PreviewItemView")
        Text(item.item.firstCopiedAt, style: .date)
        Text(item.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "PreviewItemView")
        Text(item.item.lastCopiedAt, style: .date)
        Text(item.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "PreviewItemView")
        Text(String(item.item.numberOfCopies))
      }
      .padding(.bottom)

      if let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
        Text(
          NSLocalizedString("PinKey", tableName: "PreviewItemView", comment: "")
            .replacingOccurrences(of: "{pinKey}", with: pinKey.description)
        )
        .textScale(.secondary)
      }

      if let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
        Text(
          NSLocalizedString(
            "DeleteKey",
            tableName: "PreviewItemView",
            comment: ""
          )
          .replacingOccurrences(of: "{deleteKey}", with: deleteKey.description)
        )
        .textScale(.secondary)
      }

      if let previewKey = KeyboardShortcuts.Shortcut(name: .togglePreview) {
        Text(
          NSLocalizedString(
            "PreviewKey",
            tableName: "PreviewItemView",
            comment: ""
          )
          .replacingOccurrences(
            of: "{previewKey}",
            with: previewKey.description
          )
        )
        .textScale(.secondary)
      }
    }
    .controlSize(.small)
    .padding()
  }
}

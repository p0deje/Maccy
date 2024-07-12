import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  var item: HistoryItemDecorator

  var body: some View {
    VStack(alignment: .leading) {
      if let image = item.image {
        Image(nsImage: image)
      } else {
        Text(item.text)
          .controlSize(.regular)
      }

      Divider()

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "Preview")
          Text(application)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "Preview")
        Text(item.item.firstCopiedAt, style: .date)
        Text(item.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "Preview")
        Text(item.item.lastCopiedAt, style: .date)
        Text(item.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "Preview")
        Text(String(item.item.numberOfCopies))
      }
      
      Divider()

      if let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
        Text(
          NSLocalizedString("PinKey", tableName: "Preview", comment: "")
            .replacingOccurrences(of: "{pinKey}", with: pinKey.description)
        )
      }

      if let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
        Text(
          NSLocalizedString("DeleteKey", tableName: "Preview", comment: "")
            .replacingOccurrences(of: "{deleteKey}", with: deleteKey.description)
        )
      }
    }
    .controlSize(.small)
    .padding()
  }
}


//#Preview {
//    PreviewItemView()
//}

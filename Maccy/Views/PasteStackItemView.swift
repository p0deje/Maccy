import Defaults
import SwiftUI

private struct PasteStackId: Hashable {
  var pasteStackId: UUID
  var itemId: UUID
}

struct PasteStackItemView: View {
  var stack: PasteStack
  var item: HistoryItemDecorator
  var index: Int?
  var isSelected: Bool

  var body: some View {
    ListItemView(
      id: PasteStackId(pasteStackId: stack.id, itemId: item.id),
      selectionId: stack.id,
      appIcon: item.applicationImage,
      image: index != nil ? item.thumbnailImage : nil,
      accessoryImage: item.thumbnailImage != nil ? nil : item.accessoryImage,
      reservesImageSpace: index != nil && item.hasImage,
      attributedTitle: item.attributedTitle,
      shortcuts: [],
      isSelected: isSelected,
      selectionIndex: index,
      selectionAppearance: .none
    ) {
      Text(verbatim: item.title)
    }
  }
}

import Defaults
import SwiftUI

private struct PasteStackId: Hashable {
  var pasteStackId: UUID
  var itemId: UUID

  static func == (lhs: PasteStackId, rhs: PasteStackId) -> Bool {
    return lhs.pasteStackId == rhs.pasteStackId && lhs.itemId == rhs.itemId
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(pasteStackId)
    hasher.combine(itemId)
  }
}

struct PasteStackItemView: View {
  var stack: PasteStack
  var item: HistoryItemDecorator
  var index: Int?
  var isSelected: Bool

  @Default(.showHexColorSwatch) private var showHexColorSwatch

  private var colorSwatchImage: NSImage? {
    guard showHexColorSwatch else { return nil }
    return ColorImage.from(item.title)
  }

  var body: some View {
    ListItemView(
      id: PasteStackId(pasteStackId: stack.id, itemId: item.id),
      selectionId: stack.id,
      appIcon: item.applicationImage,
      image: index != nil ? item.thumbnailImage : nil,
      accessoryImage: item.thumbnailImage != nil ? nil : colorSwatchImage,
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

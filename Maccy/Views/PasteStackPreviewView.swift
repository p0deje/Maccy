import SwiftUI

private struct PasteStackPreviewItemView: View {
  var stack: PasteStack
  var item: HistoryItemDecorator

  var body: some View {
    PasteStackItemView(
      stack: stack,
      item: item,
      index: nil,
      isSelected: false
    )
  }
}

struct PasteStackPreviewView: View {
  private static let padding = 2.0

  var pasteStack: PasteStack
  @State var pasteStackListHeight: CGFloat = 0

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        EnumeratedForEach(data: pasteStack.items) { (element, index) in
          PasteStackPreviewItemView(
            stack: pasteStack,
            item: element
          )
          if index != pasteStack.items.count - 1 {
            Divider()
              .padding(.vertical, Self.padding)
          }
        }
      }
      .padding(.vertical, Self.padding)
      .readHeight($pasteStackListHeight)
    }
    .frame(maxHeight: pasteStackListHeight)
    .background(.fill.tertiary)
    .clipShape(SelectionAppearance.none.rect(cornerRadius: Popup.cornerRadius))
    Spacer()
  }
}

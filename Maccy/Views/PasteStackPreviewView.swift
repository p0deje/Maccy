import SwiftUI

/// Unselected, no-index rendering of a single stack item used inside the preview.
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

/// Scrollable, dividers-between-rows preview of every item in a paste stack.
struct PasteStackPreviewView: View {
  /// Vertical padding applied around dividers and the list edge.
  private static let padding = 2.0

  var pasteStack: PasteStack
  @State var pasteStackListHeight: CGFloat = 0

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(pasteStack.items.enumerated()), id: \.element.id) { (index, element) in
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

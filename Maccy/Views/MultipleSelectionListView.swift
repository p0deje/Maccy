import SwiftUI

private struct MultipleSelectionListRow<Element: Identifiable>: Identifiable {
  let previous: Element?
  let element: Element
  let next: Element?
  let index: Int

  var id: Element.ID { element.id }
}

struct MultipleSelectionListView<Element: Identifiable, Content: View>: View {
  var items: [Element]
  var content: (Element?, Element, Element?, Int) -> Content

  private var rows: [MultipleSelectionListRow<Element>] {
    items.indices.map { index in
      MultipleSelectionListRow(
        previous: index > 0 ? items[index - 1] : nil,
        element: items[index],
        next: index < items.count - 1 ? items[index + 1] : nil,
        index: index
      )
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(rows) { row in
        content(row.previous, row.element, row.next, row.index)
      }
    }
  }
}

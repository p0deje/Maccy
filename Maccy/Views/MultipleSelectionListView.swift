import SwiftUI

struct IndexedElement<Element: Identifiable & Equatable>: Identifiable, Equatable {
  let index: Int
  let element: Element

  var id: Element.ID {
    element.id
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.element == rhs.element
  }
}

struct MultipleSelectionListView<Element, RowContent, ModifiedForEach>: View
where Element: Identifiable & Equatable, RowContent: View, ModifiedForEach: View {
  var items: [Element]
  var content: (Element?, Element, Element?, Int) -> RowContent
  var forEachModifier: (ForEach<[IndexedElement<Element>], Element.ID, RowContent>) -> ModifiedForEach

  init(
    items: [Element],
    @ViewBuilder content: @escaping (Element?, Element, Element?, Int) -> RowContent
  ) where ModifiedForEach == ForEach<[IndexedElement<Element>], Element.ID, RowContent> {
    self.items = items
    self.content = content
    self.forEachModifier = { $0 }
  }

  init(
    items: [Element],
    @ViewBuilder content: @escaping (Element?, Element, Element?, Int) -> RowContent,
    @ViewBuilder forEachModifier: @escaping (
      ForEach<[IndexedElement<Element>], Element.ID, RowContent>
    ) -> ModifiedForEach
  ) {
    self.items = items
    self.content = content
    self.forEachModifier = forEachModifier
  }

  var body: some View {
    let indexedItems = items.enumerated().map {
      IndexedElement(index: $0.offset, element: $0.element)
    }

    LazyVStack(spacing: 0) {
      forEachModifier(
        ForEach(indexedItems, id: \.id) { indexed in
          let index = indexed.index
          let element = indexed.element
          let previous = index > 0 ? items[index - 1] : nil
          let next = index < items.count - 1 ? items[index + 1] : nil

          content(previous, element, next, index)
        }
      )
    }
  }
}

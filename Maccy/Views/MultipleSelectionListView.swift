import SwiftUI

struct MultipleSelectionListView<Element, RowContent, ModifiedForEach>: View
where Element: Identifiable, RowContent: View, ModifiedForEach: View {
  var items: [Element]
  var content: (Element?, Element, Element?, Int) -> RowContent
  var forEachModifier: (EnumeratedForEach<[Element], Element.ID, RowContent>) -> ModifiedForEach

  init(
    items: [Element],
    @ViewBuilder content: @escaping (Element?, Element, Element?, Int) -> RowContent
  ) where ModifiedForEach == EnumeratedForEach<[Element], Element.ID, RowContent> {
    self.items = items
    self.content = content
    self.forEachModifier = { $0 }
  }

  init(
    items: [Element],
    @ViewBuilder content: @escaping (Element?, Element, Element?, Int) -> RowContent,
    @ViewBuilder forEachModifier: @escaping (
      EnumeratedForEach<[Element], Element.ID, RowContent>
    ) -> ModifiedForEach
  ) {
    self.items = items
    self.content = content
    self.forEachModifier = forEachModifier
  }

  var body: some View {
    LazyVStack(spacing: 0) {
      forEachModifier(
        EnumeratedForEach(data: items) { element, index in
          let previous = index > 0 ? items[index - 1] : nil
          let next = index < items.count - 1 ? items[index + 1] : nil
          return content(previous, element, next, index)
        }
      )
    }
  }
}

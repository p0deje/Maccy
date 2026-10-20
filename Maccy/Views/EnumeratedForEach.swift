import SwiftUI

public struct EnumeratedForEach<Data, ID, Content>: DynamicViewContent
where Data: RandomAccessCollection, Data.Element: Identifiable<ID>, ID: Hashable, Content: View {

  public var data: Data
  @ViewBuilder public var content: (Data.Element, Int) -> Content

  public var body: some View {
    buildBody()
  }

  @ViewBuilder
  private func buildBody() -> some View {
    if #available(macOS 26.0, *) {
      ForEach(data.enumerated(), id: \.element.id) { item in
        self.content(item.element, item.offset)
      }
    } else {
      ForEach(Array(data.enumerated()), id: \.element.id) { item in
        self.content(item.element, item.offset)
      }
    }
  }
}

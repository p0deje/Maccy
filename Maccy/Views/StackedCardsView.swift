import SwiftUI

private func deterministicDouble(from uuid: UUID) -> Double {
  let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }

  var value: UInt64 = 0
  for b in bytes.prefix(8) {
    value = (value << 8) | UInt64(b)
  }

  return Double(value) / Double(UInt64.max)
}

private func deterministicDouble(from uuid: UUID, in range: Range<Double>)
  -> Double
{
  precondition(range.lowerBound < range.upperBound)

  let u = deterministicDouble(from: uuid)
  return range.lowerBound + u * (range.upperBound - range.lowerBound)
}

struct StackedCardsView<Item: Identifiable, Content: View>: View
where Item.ID == UUID {
  let items: [Item]
  let maxCount: Int
  let content: (Item) -> Content

  private var lastID: UUID? {
    return items.last?.id
  }

  @ViewBuilder
  private func cardItem<CardContent: View>(
    _ size: CGSize,
    _ id: UUID,
    content: () -> CardContent = { Color.clear }
  ) -> some View {
    content()
      .frame(width: size.width * 0.9, height: size.height * 0.9)
      .background(.background.secondary)
      .cornerRadius(2 * Popup.cornerRadius)
      .overlay {
        RoundedRectangle(cornerRadius: 2 * Popup.cornerRadius)
          .stroke(Color(cgColor: NSColor.separatorColor.cgColor))
      }
      .rotationEffect(.degrees(deterministicDouble(from: id, in: -5.0..<5.0)))
      .shadow(
        color: Color(.sRGBLinear, white: 0, opacity: 0.1),
        radius: 4
      )
  }

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: Alignment(horizontal: .center, vertical: .top)) {
        ForEach(items.suffix(maxCount), id: \.id) { element in
          cardItem(geo.size, element.id) {
            content(element)
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

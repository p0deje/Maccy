import SwiftUI

struct CollapsedStackItem<Content: View>: View {
  let maxItems: Int
  let index: Int
  let open: Bool

  @State var height: CGFloat = -1
  var content: () -> Content

  private var offset: Double {
    if open || index == 0 {
      return 0
    }
    if index + 1 > maxItems {
      return -height
    }
    return -height * 0.75
  }

  private var scale: Double {
    if open {
      return 1
    }
    return pow(0.98, Double(index))
  }

  private var opacity: Double {
    if open {
      return 1
    }
    if index + 1 > maxItems {
      return 0
    }
    return pow(0.95, Double(index))
  }

  var body: some View {
    content()
      .background(
        GeometryReader { geo in
          Color.clear
            .task(id: geo.size.height) {
              DispatchQueue.main.async {
                height = geo.size.height
              }
            }
        }
      )
      .offset(y: offset)
      .padding(.bottom, offset)
      .opacity(opacity)
      .scaleEffect(scale, anchor: .center)
      .zIndex(Double(-index))
  }
}

struct PasteStackView: View {
  var stack: PasteStack
  var open: Bool = false

  @Environment(AppState.self) private var appState

  private func indexTagFor(_ index: Int) -> Int? {
    if open {
      return index
    }
    if index == 0 {
      return stack.items.count - 1
    }
    return nil
  }

  var body: some View {
    let maxItems = min(3, stack.items.count)
    LazyVStack(spacing: 0) {
      ForEach(Array(stack.items[..<maxItems].enumerated()), id: \.element.id) { (index, element) in
        CollapsedStackItem(maxItems: maxItems, index: index, open: open) {
          PasteStackItemView(
            stack: self.stack,
            item: element,
            index: indexTagFor(index),
            isSelected: appState.navigator.pasteStackSelected
          )
          .opacity(index > 0 ? 0 : 1)
          .background(appState.navigator.pasteStackSelected ? Color.accentColor.opacity(0.8) : .clear)
          .background(.thinMaterial)
          .clipShape(SelectionAppearance.none.rect(cornerRadius: Popup.cornerRadius))
          .shadow(
            color: Color(.sRGBLinear, white: 0, opacity: open ? 0 : 0.1),
            radius: 2,
            y: 2
          )
        }
      }
    }
    .hoverSelectionId(stack.id)
  }
}

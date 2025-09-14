import SwiftUI

struct HeightReaderModifier<State>: ViewModifier {
  let state: State
  let keyPath: ReferenceWritableKeyPath<State, CGFloat>

  func body(content: Content) -> some View {
    content.background(
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            state[keyPath: keyPath] = geo.size.height
          }
      }
    )
  }
}

extension View {
  func readHeight<State>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    modifier(HeightReaderModifier(state: state, keyPath: keyPath))
  }
}

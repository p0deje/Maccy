import SwiftUI

@MainActor
struct SizeReaderModifier<Value: Equatable & Sendable>: ViewModifier {
  @Binding var value: Value
  let mapper: (CGSize) -> Value

  func body(content: Content) -> some View {
    content.onGeometryChange(for: Value.self) { proxy in
      // onGeometryChange's transform is @Sendable but runs on main during layout;
      // assumeIsolated is a synchronous no-op assertion. Capture mapper (main-
      // isolated) safely by re-entering the @MainActor domain.
      MainActor.assumeIsolated { mapper(proxy.size) }
    } action: { newValue in
      MainActor.assumeIsolated { value = newValue }
    }
  }
}

@MainActor
fileprivate extension Binding {
  init<State>(
    _ object: State,
    keyPath: ReferenceWritableKeyPath<State, Value>
  ) {
    self.init(
      get: { object[keyPath: keyPath] },
      set: { object[keyPath: keyPath] = $0 }
    )
  }
}

@MainActor
extension View {
  func readHeight<State>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    readHeight(Binding(state, keyPath: keyPath))
  }

  func readWidth<State>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    readWidth(Binding(state, keyPath: keyPath))
  }

  func readWidth(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.width))
  }

  func readHeight(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.height))
  }
}

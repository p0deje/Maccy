import SwiftUI

/// Reads a view's geometry and feeds a mapped dimension back into a binding.
///
/// `onGeometryChange`'s transform is `@Sendable` but runs on the main thread during
/// layout. The `GeometryProxy` is not `Sendable`, so the `.size` is extracted before
/// crossing into the `@MainActor` block; `MainActor.assumeIsolated` is a synchronous
/// no-op assertion confirming we are on main during layout.
@MainActor
struct SizeReaderModifier<Value: Equatable & Sendable>: ViewModifier {
  @Binding var value: Value
  let mapper: (CGSize) -> Value

  func body(content: Content) -> some View {
    content.onGeometryChange(for: Value.self) { proxy in
      let size = proxy.size
      return MainActor.assumeIsolated { mapper(size) }
    } action: { newValue in
      MainActor.assumeIsolated { value = newValue }
    }
  }
}

@MainActor
fileprivate extension Binding {
  /// Creates a binding backed by a key path into an observable state object.
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
  /// Reads this view's height into a key path on the given state object.
  func readHeight<State>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    readHeight(Binding(state, keyPath: keyPath))
  }

  /// Reads this view's width into a key path on the given state object.
  func readWidth<State>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    readWidth(Binding(state, keyPath: keyPath))
  }

  /// Reads this view's width into the given binding.
  func readWidth(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.width))
  }

  /// Reads this view's height into the given binding.
  func readHeight(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.height))
  }
}

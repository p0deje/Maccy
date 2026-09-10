import SwiftUI

// Used only for @State bindings (e.g. PasteStackPreviewView).
private struct SizeReaderModifier<Value: Equatable>: ViewModifier {
  @Binding var value: Value
  let mapper: (CGSize) -> Value

  func body(content: Content) -> some View {
    content.onGeometryChange(for: Value.self) { proxy in
      mapper(proxy.size)
    } action: { newValue in
      value = newValue
    }
  }
}

// Writes to a keyPath on an @Observable object WITHOUT going through @Binding.
//
// Using a @Binding to an @Observable property here would register the
// destination property (e.g. popup.headerHeight) as a render dependency of
// this modifier. Any write from onGeometryChange would then re-invalidate the
// modifier itself, creating a potential layout feedback loop on macOS 26.
// Writing directly via keyPath avoids that dependency registration entirely.
private struct ObservableSizeReaderModifier<State: AnyObject>: ViewModifier {
  let object: State
  let keyPath: ReferenceWritableKeyPath<State, CGFloat>
  let mapper: (CGSize) -> CGFloat

  func body(content: Content) -> some View {
    content.onGeometryChange(for: CGFloat.self) { proxy in
      mapper(proxy.size)
    } action: { [weak object] newValue in
      object?[keyPath: keyPath] = newValue
    }
  }
}

extension View {
  func readHeight<State: AnyObject>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    modifier(ObservableSizeReaderModifier(object: state, keyPath: keyPath, mapper: \.height))
  }

  func readWidth<State: AnyObject>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    modifier(ObservableSizeReaderModifier(object: state, keyPath: keyPath, mapper: \.width))
  }

  func readWidth(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.width))
  }

  func readHeight(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.height))
  }
}


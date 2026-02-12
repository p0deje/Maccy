import SwiftUI

enum AsyncViewState<T> {
  case loading
  case failed
  case loaded(T)
}

struct AsyncView<Value, Content: View, Placeholder: View>: View {
  let operation: () async throws -> Value
  @ViewBuilder var content: (Value) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var viewState = AsyncViewState<Value>.loading

  init(
    operation: @escaping () async throws -> Value,
    @ViewBuilder content: @escaping (Value) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.operation = operation
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      switch viewState {
      case .loading, .failed:
        placeholder()
      case .loaded(let value):
        content(value)
      }
    }.task {
      do {
        viewState = .loading
        let result = try await operation()
        viewState = .loaded(result)
      } catch {
        viewState = .failed
      }
    }
  }
}

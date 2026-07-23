import SwiftUI

enum AsyncViewState<T> {
  case loading
  case failed
  case loaded(T)
}

struct AsyncView<Value, Content: View, Placeholder: View>: View {
  let id: AnyHashable?
  let operation: () async throws -> Value
  @ViewBuilder var content: (Value) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var viewState = AsyncViewState<Value>.loading

  init(
    id: AnyHashable? = nil,
    operation: @escaping () async throws -> Value,
    @ViewBuilder content: @escaping (Value) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.id = id
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
    }.task(id: id) {
      do {
        viewState = .loading
        let result = try await operation()
        try Task.checkCancellation()
        viewState = .loaded(result)
      } catch is CancellationError {
      } catch {
        viewState = .failed
      }
    }
  }
}

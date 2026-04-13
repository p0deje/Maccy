import SwiftUI

enum AsyncViewState<T> {
  case loading
  case failed
  case loaded(T)
}

struct AsyncView<Value, Content: View, Placeholder: View>: View {
  let taskId: AnyHashable
  let operation: () async throws -> Value
  @ViewBuilder var content: (Value) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var viewState = AsyncViewState<Value>.loading

  init(
    id: some Hashable,
    operation: @escaping () async throws -> Value,
    @ViewBuilder content: @escaping (Value) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.taskId = AnyHashable(id)
    self.operation = operation
    self.content = content
    self.placeholder = placeholder
  }

  init(
    operation: @escaping () async throws -> Value,
    @ViewBuilder content: @escaping (Value) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.taskId = AnyHashable(0)
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
    }.task(id: taskId) {
      do {
        let result = try await operation()
        viewState = .loaded(result)
      } catch {
        if case .loading = viewState {
          viewState = .failed
        }
      }
    }
  }
}

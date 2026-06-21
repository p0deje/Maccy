import SwiftUI

enum AsyncViewState<T> {
  case loading
  case failed
  case loaded(T)
}

/// An async-loading container view. The `operation` runs in a `.task`; its
/// result drives `content` (loaded) or `placeholder` (loading/failed).
///
/// Pass an `id` when the operation should re-run as the underlying identity
/// changes — e.g. a preview that must refresh as the selected item changes.
/// When `id` is non-nil the task is keyed on it (`.task(id:)`): SwiftUI cancels
/// the previous task and restarts it on a change, and the closure resets
/// `viewState = .loading` first so no stale value lingers. Without `id` the
/// task runs once on appear (the original behavior).
///
/// Why `id` exists: `PreviewItemView` previously rendered the lead item's
/// preview through an `AsyncView` whose `.task` had no id. `PreviewItemView`
/// keeps its structural identity across selection changes (positional
/// `if let`), so the task never re-ran — the preview showed the first item's
/// image stuck while navigating. Keying the task on `item.id` makes the preview
/// refresh per selection.
struct AsyncView<Value, Content: View, Placeholder: View>: View {
  let operation: () async throws -> Value
  let taskId: AnyHashable?
  @ViewBuilder var content: (Value) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var viewState = AsyncViewState<Value>.loading

  init(
    operation: @escaping () async throws -> Value,
    @ViewBuilder content: @escaping (Value) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.operation = operation
    self.taskId = nil
    self.content = content
    self.placeholder = placeholder
  }

  /// When `id` changes, the operation re-runs (and `viewState` resets to
  /// `.loading` first), so the displayed value tracks the new identity.
  init<ID: Hashable>(
    id: ID,
    operation: @escaping () async throws -> Value,
    @ViewBuilder content: @escaping (Value) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.operation = operation
    self.taskId = AnyHashable(id)
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
      viewState = .loading
      do {
        let result = try await operation()
        viewState = .loaded(result)
      } catch {
        viewState = .failed
      }
    }
  }
}

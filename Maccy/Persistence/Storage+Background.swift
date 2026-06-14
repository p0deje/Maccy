import SwiftData

extension Storage {
  /// Returns a fresh context for use inside one background actor/task.
  ///
  /// Do not share the returned context across isolation domains.
  @MainActor
  func newBackgroundContext() -> ModelContext {
    let context = ModelContext(container)
    context.undoManager = nil
    return context
  }
}

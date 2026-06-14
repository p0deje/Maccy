import SwiftData

extension Storage {
  /// Returns a fresh context for use inside one background actor/task.
  ///
  /// Do not share the returned context across isolation domains.
  ///
  /// `automaticallyMergesChangesFromParent` is set so that when the ingest actor
  /// (BS-2.2b) commits on this background context, the changes are merged into
  /// the main context (`Storage.shared.context`) — which is what lets `History`
  /// (a main-context reader) observe actor-written items. The reverse direction
  /// (main -> background) is handled by SwiftData's default container behavior.
  @MainActor
  func newBackgroundContext() -> ModelContext {
    let context = ModelContext(container)
    context.undoManager = nil
    context.automaticallyMergesChangesFromParent = true
    return context
  }
}

import SwiftData

extension Storage {
  /// Returns a fresh context for use inside one background actor/task.
  ///
  /// Do not share the returned context across isolation domains.
  ///
  /// SwiftData `ModelContext`s created from the same `ModelContainer` share the
  /// underlying persistent store, so when the ingest actor (BS-2.2b) commits on
  /// this background context, a subsequent `fetch` on the main context
  /// (`Storage.shared.context`) observes those committed changes — which is what
  /// lets `History.consume`/`reconcileWithStore` (BS-2.3) reflect actor-written
  /// items. (`ModelContext` has no `automaticallyMergesChangesFromParent` —
  /// unlike Core Data's `NSManagedObjectContext` — because SwiftData propagates
  /// committed changes through the shared store, not per-context merge events.)
  @MainActor
  func newBackgroundContext() -> ModelContext {
    let context = ModelContext(container)
    context.undoManager = nil
    return context
  }
}

import SwiftData

extension Storage {
  /// Returns a fresh `ModelContext` for use inside one background actor/task.
  ///
  /// Do not share the returned context across isolation domains.
  ///
  /// SwiftData `ModelContext`s created from the same `ModelContainer` share the
  /// underlying persistent store, so when the off-main ingest actor commits on
  /// this background context, a subsequent `fetch` on the main context
  /// (`Storage.shared.context`) observes those committed changes — which is what
  /// lets the main-actor reconcile reflect actor-written items. `ModelContext`
  /// has no `automaticallyMergesChangesFromParent` (unlike Core Data's
  /// `NSManagedObjectContext`); SwiftData propagates committed changes through
  /// the shared store rather than via per-context merge events.
  @MainActor
  func newBackgroundContext() -> ModelContext {
    let context = ModelContext(container)
    context.undoManager = nil
    return context
  }
}

/// Bounded background-fetch primitive that reads history items on an injected
/// (background) context and projects them to Sendable `ItemSnapshotDTO`s,
/// split into a **visible window** (to decorate on the main actor for the first
/// frame) and a **tail** (low-priority prefetch that follows). `fetchLimit`
/// bounds the total rows fetched, replacing an unbounded `FetchDescriptor` with
/// a bounded read so a cold open no longer faults the whole table onto main.
///
/// Sort follows the chosen algorithm (`lastCopiedAt` by default), matching
/// `Sorter.bySortingAlgorithm` direction-for-direction.
///
/// Pin partitioning is deliberately NOT applied here — it depends on
/// `Defaults[.pinTo]` and must preserve algorithm order within each partition,
/// which does not map to a single `FetchDescriptor` sort. The caller applies it
/// on the projected snapshots, preserving the existing two-pass sort result.
///
/// Synchronous `throws` rather than `async`: the fetch runs on whatever thread
/// owns the injected context. Production calls this from a background `Task`
/// holding a `Storage.newBackgroundContext()`, so the work stays off-main
/// without the primitive itself being async.
///
/// Status: not yet wired into the live read path — `History.load()` fetches
/// directly rather than through `fetchWindow`. Colocated in this file (rather
/// than its own `VisibleWindowLoader.swift`) to avoid hand-editing the
/// non-synced pbxproj; promoting to a dedicated file is housekeeping for a
/// later batched pbxproj edit.
enum VisibleWindowLoader {
  /// Fetches up to `fetchLimit` items from `context`, sorted by `sortBy`, and
  /// splits them into a visible window of `visibleHint` items and a tail.
  ///
  /// - Returns: A `(visible, tail)` pair of `ItemSnapshotDTO`s.
  /// - Throws: Rethrows any SwiftData fetch error.
  static func fetchWindow(
    in context: ModelContext,
    sortBy: Sorter.By,
    fetchLimit: Int,
    visibleHint: Int
  ) throws -> (visible: [ItemSnapshotDTO], tail: [ItemSnapshotDTO]) {
    let sortDescriptor: SortDescriptor<HistoryItem>
    switch sortBy {
    case .firstCopiedAt:
      sortDescriptor = SortDescriptor(\.firstCopiedAt, order: .reverse)
    case .numberOfCopies:
      sortDescriptor = SortDescriptor(\.numberOfCopies, order: .reverse)
    default:
      sortDescriptor = SortDescriptor(\.lastCopiedAt, order: .reverse)
    }

    var descriptor = FetchDescriptor<HistoryItem>(sortBy: [sortDescriptor])
    descriptor.fetchLimit = max(0, fetchLimit)

    let results = try context.fetch(descriptor)
    let snapshots = results.map(snapshot(of:))

    let visibleCount = max(0, min(visibleHint, snapshots.count))
    let visible = Array(snapshots.prefix(visibleCount))
    let tail = Array(snapshots.dropFirst(visibleCount))
    return (visible, tail)
  }
}

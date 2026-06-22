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

/// BS-4.3 primitive: fetches history items on the injected (background) context
/// and projects them to Sendable `ItemSnapshotDTO`s, split into a **visible
/// window** (to decorate on the main actor for the first frame) and a **tail**
/// (low-priority prefetch that follows). `fetchLimit` bounds the total rows
/// fetched — replacing `History.load()`'s unbounded `FetchDescriptor` with a
/// bounded read so cold-open no longer faults the whole table onto main.
///
/// Sort follows the chosen algorithm (`lastCopiedAt` by default), matching
/// `Sorter.bySortingAlgorithm` direction-for-direction.
///
/// **Pin partitioning is deliberately NOT applied here** — it depends on
/// `Defaults[.pinTo]` and must preserve algorithm order within each partition,
/// which doesn't map to a single `FetchDescriptor` sort. The caller (`History.load`,
/// next sub-step) applies it on the projected snapshots, preserving the current
/// `Sorter.sort` two-pass result.
///
/// Synchronous `throws` (not the step-4 sketch's `async`): the fetch runs on
/// whatever thread owns the injected context — production calls this from a
/// background `Task` holding a `Storage.newBackgroundContext()`, so the work
/// stays off-main without the primitive itself being async. Colocated in this
/// file (not its own `VisibleWindowLoader.swift`) to avoid hand-editing the
/// non-synced pbxproj under a no-local-toolchain workflow; promoting to a
/// dedicated file is housekeeping for a later batched pbxproj edit.
enum VisibleWindowLoader {
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

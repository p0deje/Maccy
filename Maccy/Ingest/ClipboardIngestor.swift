import AppKit
import Defaults
import Foundation
import Logging
import SwiftData

/// Off-main clipboard ingest contract.
protocol ClipboardIngestor: Sendable {
  func ingest(_ request: IngestRequest) async -> IngestResult
}

/// `ClipboardIngestor` adapter that performs the ingest on the main actor via the
/// legacy `History.shared.add` path.
final class MainActorIngestorAdapter: ClipboardIngestor {
  func ingest(_ request: IngestRequest) async -> IngestResult {
    await MainActor.run {
      let item = Self.historyItem(from: request)
      History.shared.add(item)
      return IngestResult(event: nil, metrics: .zero)
    }
  }

  @MainActor
  static func historyItem(from request: IngestRequest) -> HistoryItem {
    let item = HistoryItem(
      contents: request.contents.map {
        HistoryItemContent(type: $0.type, value: $0.value)
      }
    )
    item.application = request.application
    item.firstCopiedAt = request.now
    item.lastCopiedAt = request.now
    item.title = item.generateTitle()
    return item
  }
}

/// Off-main clipboard ingest actor: the production replacement for the main-thread
/// `History.add` path.
///
/// The pipeline runs entirely off the main thread: filter the request contents,
/// dedup against existing items, write a single SwiftData transaction, then emit a
/// `Sendable` `StoreEvent` back to the main observer. `MainActorIngestorAdapter`
/// is the byte-for-byte legacy equivalent kept as the runtime path until the
/// off-main actor is wired in.
///
/// ## Concurrency model
/// - `modelContext` is the actor's isolated `ModelContext` (provided by the
///   `@ModelActor` macro, run through a `DefaultSerialModelExecutor` so each
///   access is mutually exclusive). `ModelContext` is not `Sendable`, but it lives
///   entirely inside this actor's isolation: every fetch, mutation,
///   `transaction`, `processPendingChanges`, and `save` happens on the actor.
///   The `@Model HistoryItem` / `HistoryItemContent` instances therefore never
///   cross isolation — only `ItemSnapshotDTO` / `StoreEvent` (both `Sendable`)
///   leave the actor.
/// - `now` is an injected clock. `ingest(_:)` calls it once at the top to fix a
///   single `timestamp`, then reuses `timestamp` for `firstCopiedAt` /
///   `lastCopiedAt` so one ingest is internally consistent. `Date()` is never
///   called from inside the actor.
/// - `image` is the `ImageProcessing` strategy (used later for thumbnails and
///   previews); this actor calls `HistoryItem.generateTitle()` for text titles.
///   Image items get an empty title (the OCR feature was removed).
///
/// ## Single-transaction invariant
/// The whole point versus the legacy `History.add` flow (which issued
/// `insertIntoStorage` → `mergeDuplicateIfNeeded` → `limitHistorySize` as
/// separate saves) is one `modelContext.transaction { ... }` followed by one
/// `modelContext.save()` per ingest. The trim, the duplicate delete, and the
/// new-item insert all land in the same transaction. Errors are logged via
/// `logger.error` (never silently `try?`-swallowed) and surface as a no-event
/// `IngestResult`.
///
/// ## Known parity gap versus `History.add`
/// `History.findSimilarItem` additionally consults the main-thread `sessionLog`
/// via `isModified(item)` to detect "this copy is a modification of a recent
/// copy." The actor has no `sessionLog` (it is main-thread-only state), so the
/// actor performs the `supersedes` dedup only. The rare modification-merge case
/// is a deliberate limitation; it could be closed later by forwarding sessionLog
/// info into the actor's request.
@ModelActor
actor BackgroundClipboardIngestor: ClipboardIngestor {
  // `var` with defaults so the `@ModelActor` macro's generated
  // `init(modelContainer:)` satisfies "all stored properties initialized"; the
  // real values are set in the custom init below.
  private var image: ImageProcessing = PassthroughImageProcessor()
  private var now: @Sendable () -> Date = { Date() }
  private var onEvent: @Sendable (StoreEvent) async -> Void = { _ in }
  private let logger = Logger(label: "org.p0deje.Maccy")

  /// In-memory dedup index over every committed item's content entries,
  /// replacing the per-copy full-table fetch plus O(n) `supersedes` scan with an
  /// O(hits) candidate lookup.
  ///
  /// `persistentIDByItemID` bridges the index's `ItemID` (UUID) keys to the
  /// `PersistentIdentifier` that `model(for:)` needs to fetch each candidate for
  /// the authoritative `supersedes` confirm — `ItemID` is a UUID hash of the
  /// persistent id, cheap to build and unit-test, but not itself fetchable. The
  /// index is built lazily on the first ingest, then maintained incrementally per
  /// commit (register the inserted item, unregister the duplicate plus the
  /// size-trim evictions).
  private var signatureIndex = SignatureIndex()
  private var persistentIDByItemID: [ItemID: PersistentIdentifier] = [:]
  private var dedupIndexInitialized = false

  init(
    modelContainer: ModelContainer,
    image: ImageProcessing,
    now: @escaping @Sendable () -> Date,
    onEvent: @escaping @Sendable (StoreEvent) async -> Void
  ) {
    self.modelContainer = modelContainer
    self.image = image
    self.now = now
    self.onEvent = onEvent
    modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
  }

  /// Ingests one clipboard copy off the main thread.
  ///
  /// Steps (matching the legacy `History.add` flow, collapsed into a single
  /// transaction):
  /// 1. Build an `IngestConfig` snapshot from `Defaults` and the built-in type
  ///    sets on the main actor (mirroring `Clipboard.contents(from:)` /
  ///    `filteredTypes` / `shouldIgnore`).
  /// 2. Filter the request contents with the pure `filterContents` helper,
  ///    timing it for `parseMs` via the injected clock. An empty result is a
  ///    no-op ingest (no event, no write).
  /// 3. Build the new `HistoryItem` on the actor's isolated `modelContext`.
  /// 4. Dedup against existing items via the per-entry `SignatureIndex`
  ///    (O(hits) candidate lookup plus authoritative `supersedes` confirm),
  ///    replacing the legacy full-table `findSimilarItem` scan.
  /// 5. Merge fields from the duplicate if found (mirroring
  ///    `History.mergeDuplicateIfNeeded`).
  /// 6. Single-transaction commit: trim unpinned items beyond the main-actor
  ///    `Defaults[.size]` snapshot (oldest first), delete the duplicate, insert
  ///    the new item, then one save.
  /// 7. Emit `.added` (no duplicate) or `.merged` (duplicate found) with the
  ///    item's `ItemSnapshotDTO`.
  /// 8. Report `IngestMetrics`.
  ///
  /// - Returns: The `StoreEvent` (if any) plus metrics. On a persistence error
  ///   the event is `nil`, the error is logged, and the metrics reflect the
  ///   pre-commit state (dedup decision plus parse timing).
  func ingest(_ request: IngestRequest) async -> IngestResult {
    let filterStart = now()
    // Defaults, filterContents (rich-text detection), and title generation all
    // stay on the main actor. The Defaults package is shared with UI state, and
    // the rich-text paths parse via NSAttributedString/AppKit.
    let (filtered, title, historyLimit) = await MainActor.run {
      let config = Self.ingestConfig()
      let filtered = filterContents(
        request.contents, application: request.application, config: config
      )
      return (filtered, Self.title(for: filtered), max(1, Defaults[.size]))
    }
    let parseMs = now().timeIntervalSince(filterStart) * 1000

    guard !filtered.isEmpty else {
      return IngestResult(
        event: nil,
        metrics: IngestMetrics(dedupHits: 0, bytesHashed: 0, parseMs: parseMs)
      )
    }

    let timestamp = now()
    let item = makeHistoryItem(
      filtered, application: request.application, timestamp: timestamp, title: title
    )
    ensureDedupIndexInitialized()
    let dup = findDuplicate(of: item)
    if let dup {
      mergeFields(from: dup, into: item, timestamp: timestamp)
    }

    let dedupHits = dup != nil ? 1 : 0
    let bytesHashed = Self.bytesHashed(for: item)

    let deletedItemIDs: [ItemID]
    do {
      deletedItemIDs = try commit(item, deleting: dup, limit: historyLimit)
    } catch {
      logger.error("Failed to commit ingest: \(String(describing: error))")
      return IngestResult(
        event: nil,
        metrics: IngestMetrics(dedupHits: dedupHits, bytesHashed: bytesHashed, parseMs: parseMs)
      )
    }

    // Keep the dedup index in sync with the committed transaction.
    maintainDedupIndex(inserted: item, deleted: deletedItemIDs)

    let event: StoreEvent = dup == nil
      ? .added(snapshot(of: item))
      : .merged(snapshot(of: item))
    await onEvent(event)

    return IngestResult(
      event: event,
      metrics: IngestMetrics(dedupHits: dedupHits, bytesHashed: bytesHashed, parseMs: parseMs)
    )
  }

  // MARK: - Ingest steps

  /// Builds the new `HistoryItem` from the filtered contents (mirroring
  /// `MainActorIngestorAdapter.historyItem(from:)`).
  ///
  /// The title is pre-computed on the main actor (see `title(for:)`) because
  /// `NSAttributedString` parsing cannot run off-main; image items get an empty
  /// title (OCR was removed).
  private func makeHistoryItem(
    _ contents: [ContentDTO],
    application: String?,
    timestamp: Date,
    title: String
  ) -> HistoryItem {
    let item = HistoryItem(
      contents: contents.map { HistoryItemContent(type: $0.type, value: $0.value) }
    )
    item.application = application
    item.firstCopiedAt = timestamp
    item.lastCopiedAt = timestamp
    item.title = title
    return item
  }

  /// Computes the item title from the filtered contents.
  ///
  /// Must run on the main actor: `HistoryItemEngine.generateTitle` parses
  /// RTF/HTML via `NSAttributedString`, which is main-thread-affine
  /// (AppKit/WebKit) and traps off-main. The actor hops to main for this (and
  /// for `filterContents`); the dedup fetch and the single-transaction write stay
  /// off-main.
  @MainActor
  private static func title(for contents: [ContentDTO]) -> String {
    let transient = contents.map { HistoryItemContent(type: $0.type, value: $0.value) }
    return HistoryItemEngine.generateTitle(
      contents: transient,
      fallbackTitle: "",
      maxLength: HistoryItem.titlePreviewLimit,
      richTextParsingLimit: 512 * 1024,
      showSpecialSymbols: Defaults[.showSpecialSymbols]
    )
  }

  /// Finds an existing item that supersedes the new one via the per-entry index,
  /// replacing the legacy per-copy full-table fetch plus O(n) `supersedes` scan.
  ///
  /// The index returns candidate ids whose signature shares at least one content
  /// entry with the new item; each is fetched by `PersistentIdentifier` and
  /// confirmed with the authoritative `supersedes` (which rules out same-size and
  /// fingerprint collisions), so dedup correctness is identical to the legacy
  /// O(n) scan. Genuinely-new content shares no entry and yields no candidates —
  /// the O(1) fast path. `model(for:)` returning an un-faulted shell for an id it
  /// no longer knows (a stale index entry) is harmless: such a shell has no
  /// contents, so `supersedes` returns false and it is skipped.
  private func findDuplicate(of item: HistoryItem) -> HistoryItem? {
    let signature = item.duplicateSignature
    let entries = item.contents.map { content in
      ContentSignatureEntry(
        type: content.type,
        fingerprint: content.value.flatMap(ClipboardDataProcessor.fingerprintIfLarge),
        size: content.value?.count ?? 0
      )
    }
    for candidateID in signatureIndex.candidates(forEntries: entries) {
      guard let candidatePID = persistentIDByItemID[candidateID],
            let candidate = modelContext.model(for: candidatePID) as? HistoryItem,
            candidate != item,
            candidate.supersedes(signature) else {
        continue
      }
      return candidate
    }
    return nil
  }

  /// Lazily builds the dedup index from the committed store on the first ingest:
  /// one O(n) pass, then skipped on subsequent ingests. Runs on the actor's
  /// isolated context.
  private func ensureDedupIndexInitialized() {
    guard !dedupIndexInitialized else { return }
    let items = (try? modelContext.fetch(FetchDescriptor<HistoryItem>())) ?? []
    for existing in items {
      registerInDedupIndex(existing)
    }
    dedupIndexInitialized = true
  }

  /// Registers one item's signature plus its id-to-`PersistentIdentifier` bridge entry.
  private func registerInDedupIndex(_ item: HistoryItem) {
    let snap = snapshot(of: item)
    signatureIndex.register(snap.signature, id: snap.id)
    if let pid = snap.persistentID {
      persistentIDByItemID[snap.id] = pid
    }
  }

  /// Removes one item's signature plus bridge entry (used for the duplicate and
  /// the size-trim-evicted items that `commit` deletes).
  private func unregisterFromDedupIndex(itemID: ItemID) {
    signatureIndex.remove(id: itemID)
    persistentIDByItemID.removeValue(forKey: itemID)
  }

  /// Keeps the dedup index in sync with one committed transaction: drops the
  /// duplicate plus size-trim evictions, then registers the inserted item after
  /// the save so its `persistentModelID` / `ItemID` are finalized.
  private func maintainDedupIndex(inserted item: HistoryItem, deleted: [ItemID]) {
    for deletedID in deleted {
      unregisterFromDedupIndex(itemID: deletedID)
    }
    registerInDedupIndex(item)
  }

  /// Copies the duplicate's fields into the new item (mirroring
  /// `History.mergeDuplicateIfNeeded`).
  ///
  /// Contents are replaced with the existing item's; the sessionLog-modification
  /// guard is absent here (see the class doc).
  private func mergeFields(from dup: HistoryItem, into item: HistoryItem, timestamp: Date) {
    item.contents = dup.contents.map { HistoryItemContent(type: $0.type, value: $0.value) }
    item.firstCopiedAt = dup.firstCopiedAt
    item.numberOfCopies += dup.numberOfCopies
    item.pin = dup.pin
    item.title = dup.title
    if !item.fromMaccy {
      item.application = dup.application
    }
    item.lastCopiedAt = timestamp
  }

  /// Single-transaction commit: delete the duplicate, trim unpinned items beyond
  /// the main-actor `Defaults[.size]` snapshot (oldest first), insert the new
  /// item, then one `processPendingChanges` plus `save`.
  ///
  /// Returns the `ItemID`s of the deleted items (the duplicate plus each
  /// size-trim eviction) so the caller can keep the dedup index in sync —
  /// captured from each item before it is deleted, since a post-save snapshot of
  /// a deleted `@Model` would fault a torn row.
  private func commit(_ item: HistoryItem, deleting dup: HistoryItem?, limit: Int) throws -> [ItemID] {
    var deletedItemIDs: [ItemID] = []
    try modelContext.transaction {
      // Sort unpinned by lastCopiedAt descending so `dropFirst(limit - 1)` is the
      // oldest tail — exactly what `History.limitHistorySize` deletes. The dup is
      // removed from the count before trimming (mirroring `History.add`, where
      // the merge removes the dup before `limitHistorySize` runs — net zero for
      // a merge).
      let descriptor = FetchDescriptor<HistoryItem>(
        predicate: #Predicate { $0.pin == nil },
        sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
      )
      var unpinned = (try? modelContext.fetch(descriptor)) ?? []
      if let dup {
        unpinned.removeAll { $0 == dup }
        deletedItemIDs.append(snapshot(of: dup).id)
        modelContext.delete(dup)
      }
      if unpinned.count > limit - 1 {
        for excess in unpinned.dropFirst(limit - 1) {
          deletedItemIDs.append(snapshot(of: excess).id)
          modelContext.delete(excess)
        }
      }
      modelContext.insert(item)
    }
    modelContext.processPendingChanges()
    try modelContext.save()
    return deletedItemIDs
  }

  /// Builds the `IngestConfig` snapshot the pure filter needs, mirroring the
  /// `Defaults` and private-constant reads `Clipboard` performs live in
  /// `contents(from:)` / `filteredTypes` / `shouldIgnore`.
  ///
  /// `Clipboard.supportedTypes` and `Clipboard.ignoredTypes` are private, so the
  /// rawValues are hardcoded here — the one accepted duplication, matching
  /// `IngestConfig`'s doc comment and `IngestFilterTests.allSupportedTypes`.
  private static func ingestConfig() -> IngestConfig {
    // Clipboard.supportedTypes rawValues:
    // .fileURL, .heic, .html, .jpeg, .png, .rtf, .string, .tiff.
    let supportedTypes: Set<String> = [
      "public.file-url",
      "public.heic",
      "public.html",
      "public.jpeg",
      "public.png",
      "public.rtf",
      "public.utf8-plain-text",
      "public.tiff"
    ]

    // Clipboard.ignoredTypes rawValues:
    // .autoGenerated, .concealed, .transient -> org.nspasteboard.* markers.
    let builtInIgnored: Set<String> = [
      "org.nspasteboard.AutoGeneratedType",
      "org.nspasteboard.ConcealedType",
      "org.nspasteboard.TransientType"
    ]

    let enabledTypes = Set(Defaults[.enabledPasteboardTypes].map(\.rawValue))
    let ignoredTypes = builtInIgnored.union(Defaults[.ignoredPasteboardTypes])

    return IngestConfig(
      supportedTypes: supportedTypes,
      enabledTypes: enabledTypes,
      ignoredTypes: ignoredTypes,
      maxValueSize: HistoryItemContent.maxValueSize,
      richTextParsingLimit: 512 * 1024,
      regularExpressionInputLimit: 2_000,
      ignoreRegexp: Defaults[.ignoreRegexp],
      ignoredApps: Defaults[.ignoredApps],
      ignoreAllAppsExceptListed: Defaults[.ignoreAllAppsExceptListed],
      titlePreviewLimit: HistoryItem.titlePreviewLimit
    )
  }

  /// Approximates the byte volume that would be fingerprinted during this ingest:
  /// the sum of `value.count` over contents whose size clears
  /// `ClipboardDataProcessor.fingerprintIfLarge`'s 16 KiB threshold.
  ///
  /// Used only for `IngestMetrics.bytesHashed` reporting; it does not influence
  /// dedup correctness (the actual fingerprints are computed lazily inside
  /// `HistoryItemEngine`).
  private static func bytesHashed(for item: HistoryItem) -> Int {
    item.contents.reduce(0) { total, content in
      guard let data = content.value,
            data.count >= 16 * 1024 else {
        return total
      }
      return total + data.count
    }
  }
}

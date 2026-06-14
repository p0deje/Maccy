import AppKit
import Defaults
import Foundation
import Logging
import SwiftData

protocol ClipboardIngestor: Sendable {
  func ingest(_ request: IngestRequest) async -> IngestResult
}

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

/// Off-main clipboard ingest actor — the BS-2 replacement for the
/// `History.add` half of the old main-thread path.
///
/// `MainActorIngestorAdapter` mirrors the existing `Clipboard` → `History.add`
/// flow byte-for-byte and stays the runtime path until BS-2.4/2.5 flip the
/// switch. This actor is the production target: filter → dedup → write a single
/// SwiftData transaction → emit a `Sendable` `StoreEvent` back to the main
/// observer, all OFF the main thread.
///
/// ## Concurrency model
/// - `modelContext` is the actor's isolated `ModelContext` (provided by the
///   `@ModelActor` macro, run through a `DefaultSerialModelExecutor` so each
///   access is mutually exclusive). `ModelContext` is NOT `Sendable`,
///   but it lives entirely inside this actor's isolation: every fetch, mutation,
///   `transaction`, `processPendingChanges`, and `save` happens on the actor.
///   The `@Model HistoryItem` / `HistoryItemContent` instances therefore NEVER
///   cross isolation — only `ItemSnapshotDTO` / `StoreEvent` (both `Sendable`)
///   leave the actor.
/// - `now` is an injected clock. `ingest(_:)` calls it ONCE at the top to fix a
///   single `timestamp`, then reuses `timestamp` for `firstCopiedAt` /
///   `lastCopiedAt` so one ingest is internally consistent. `Date()` is never
///   called from inside the actor.
/// - `image` is the `ImageProcessing` from BS-1 (used later for thumbnails /
///   previews in BS-3); this actor calls `HistoryItem.generateTitle()` for text
///   titles. Image items get an empty title (the OCR feature was removed).
///
/// ## Single-transaction invariant
/// The whole point versus the old `History.add` flow (which issued
/// `insertIntoStorage` → `mergeDuplicateIfNeeded` → `limitHistorySize` as
/// separate saves) is ONE `modelContext.transaction { ... }` followed by ONE
/// `modelContext.save()` per ingest. The trim, the duplicate delete, and the new-item
/// insert all land in the same transaction. Errors are LOGGED via `logger.error`
/// (never silently `try?`-swallowed) and surface as a no-event `IngestResult`.
///
/// ## Known parity gap versus `History.add`
/// `History.findSimilarItem` (History.swift:562-577) additionally consults the
/// main-thread `sessionLog` via `isModified(item)` (History.swift:572,
/// 604-610) to detect "this copy is a modification of a recent copy." The actor
/// has no `sessionLog` (it is main-thread-only state), so the actor performs the
/// `supersedes` dedup ONLY. The rare modification-merge case is a deliberate
/// BS-2 limitation; it could be closed later by forwarding sessionLog info into
/// the actor's request.
@ModelActor
actor BackgroundClipboardIngestor: ClipboardIngestor {
  // `var` with defaults so the @ModelActor macro's generated `init(modelContainer:)`
  // satisfies "all stored properties initialized"; the real values are set in the
  // custom init below.
  private var image: ImageProcessing = PassthroughImageProcessor()
  private var now: @Sendable () -> Date = { Date() }
  private var onEvent: @Sendable (StoreEvent) async -> Void = { _ in }
  private let logger = Logger(label: "org.p0deje.Maccy")

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
  /// Steps (matching the old `History.add` flow, collapsed into a single
  /// transaction):
  /// 1. Build an `IngestConfig` snapshot from `Defaults` and the built-in type
  ///    sets (mirrors `Clipboard.contents(from:)` / `filteredTypes` /
  ///    `shouldIgnore`).
  /// 2. Filter the request contents with the pure `filterContents` helper,
  ///    timing it for `parseMs` via the injected clock. An empty result is a
  ///    no-op ingest (no event, no write).
  /// 3. Build the new `HistoryItem` on the actor's isolated `modelContext` (mirrors `historyItem(from:)`).
  /// 4. Dedup against existing items via `duplicateSignature` / `supersedes`
  ///    (mirrors `History.findSimilarItem`, minus the sessionLog branch).
  /// 5. Merge fields from the duplicate if found (mirrors
  ///    `History.mergeDuplicateIfNeeded`).
  /// 6. Single-transaction commit: trim unpinned items beyond `Defaults[.size]`
  ///    (oldest first), delete the duplicate, insert the new item, then ONE save.
  /// 7. Emit `.added` (no dup) or `.merged` (dup found) with the item's
  ///    `ItemSnapshotDTO`.
  /// 8. Report `IngestMetrics`.
  ///
  /// - Returns: The `StoreEvent` (if any) plus metrics. On a persistence error
  ///   the event is `nil`, the error is logged, and the metrics reflect the
  ///   pre-commit state (dedup decision + parse timing).
  func ingest(_ request: IngestRequest) async -> IngestResult {
    let config = Self.ingestConfig()

    let filterStart = now()
    // filterContents (rich-text detection) and title generation parse RTF/HTML
    // via NSAttributedString, which is main-thread-affine (AppKit/WebKit) and
    // traps if run off-main. Run both on the main actor; the heavy dedup-fetch
    // and single-transaction write below stay off-main.
    let (filtered, title) = await MainActor.run {
      let filtered = filterContents(
        request.contents, application: request.application, config: config
      )
      return (filtered, Self.title(for: filtered))
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
    let dup = findDuplicate(of: item)
    if let dup {
      mergeFields(from: dup, into: item, timestamp: timestamp)
    }

    let dedupHits = dup != nil ? 1 : 0
    let bytesHashed = Self.bytesHashed(for: item)

    do {
      try commit(item, deleting: dup)
    } catch {
      logger.error("Failed to commit ingest: \(String(describing: error))")
      return IngestResult(
        event: nil,
        metrics: IngestMetrics(dedupHits: dedupHits, bytesHashed: bytesHashed, parseMs: parseMs)
      )
    }

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

  /// Builds the new `HistoryItem` from the filtered contents (mirrors
  /// `MainActorIngestorAdapter.historyItem(from:)`). The title is pre-computed on
  /// the main actor (see `title(for:)`) because `NSAttributedString` parsing
  /// can't run off-main; image items get an empty title (OCR removed).
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

  /// Computes the item title from the filtered contents. MUST run on the main
  /// actor: `HistoryItemEngine.generateTitle` parses RTF/HTML via
  /// `NSAttributedString`, which is main-thread-affine (AppKit/WebKit) and traps
  /// off-main. The actor hops to main for this (and for `filterContents`); the
  /// dedup fetch and the single-transaction write stay off-main.
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

  /// Finds an existing item that supersedes the new one (mirrors
  /// `History.findSimilarItem`, History.swift:562-577, MINUS the `isModified` /
  /// `sessionLog` branch — see the actor's class doc).
  private func findDuplicate(of item: HistoryItem) -> HistoryItem? {
    let existing = (try? modelContext.fetch(FetchDescriptor<HistoryItem>())) ?? []
    let signature = item.duplicateSignature
    return existing.first { $0 != item && $0.supersedes(signature) }
  }

  /// Copies the duplicate's fields into the new item (mirrors
  /// `History.mergeDuplicateIfNeeded`, History.swift:257-283). Contents are
  /// replaced with the existing item's (the sessionLog-modification guard is
  /// absent here — see the class doc).
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
  /// `Defaults[.size]` (oldest first), insert the new item, then ONE
  /// `processPendingChanges` + `save`. Mirrors the ritual in
  /// `SwiftDataHistoryPersistence.deleteUnpinned` (History.swift:43-57) and the
  /// trim in `History.limitHistorySize(to:)` (History.swift:208-215, 244).
  private func commit(_ item: HistoryItem, deleting dup: HistoryItem?) throws {
    let limit = max(1, Defaults[.size])
    try modelContext.transaction {
      // Sort unpinned by lastCopiedAt descending so `dropFirst(limit - 1)` is the
      // oldest tail — exactly what History.limitHistorySize deletes. The dup is
      // removed from the count BEFORE trimming (mirrors History.add, where the
      // merge removes the dup before limitHistorySize runs — net zero for merge).
      let descriptor = FetchDescriptor<HistoryItem>(
        predicate: #Predicate { $0.pin == nil },
        sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
      )
      var unpinned = (try? modelContext.fetch(descriptor)) ?? []
      if let dup {
        unpinned.removeAll { $0 == dup }
        modelContext.delete(dup)
      }
      if unpinned.count > limit - 1 {
        for excess in unpinned.dropFirst(limit - 1) {
          modelContext.delete(excess)
        }
      }
      modelContext.insert(item)
    }
    modelContext.processPendingChanges()
    try modelContext.save()
  }

  /// Builds the `IngestConfig` snapshot the pure filter needs. Mirrors the
  /// `Defaults` / private-constant reads `Clipboard` does live in
  /// `contents(from:)` / `filteredTypes` / `shouldIgnore`.
  ///
  /// `Clipboard.supportedTypes` and `Clipboard.ignoredTypes` are private, so the
  /// rawValues are hardcoded here with citations — the one accepted duplication,
  /// matching `IngestConfig`'s doc comment and `IngestFilterTests.allSupportedTypes`.
  private static func ingestConfig() -> IngestConfig {
    // Clipboard.supportedTypes rawValues (Clipboard.swift:24-33):
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

    // Clipboard.ignoredTypes rawValues (Clipboard.swift:34-38):
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

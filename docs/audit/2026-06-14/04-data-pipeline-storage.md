# Data Pipeline & Storage Audit — Maccy

**Date:** 2026-06-14
**Scope:** SwiftData persistence layer, `ModelContext`/`ModelContainer` architecture, fetch/load pipeline, insert/dedup flow, delete/size-limit, save/transaction behavior, throttling/coalescing, data redundancy, pre-warming/responsiveness, schema/model.
**Method:** Direct read of source at repo root `/lzcapp/document/Projects/Maccy`. Every file:line cited was read; snippets are quoted verbatim.
**Verified baseline:** Persistence is SwiftData. `@Model class HistoryItem` (`Maccy/Models/HistoryItem.swift:7`) with `@Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item) var contents` (`:73`); `@Model class HistoryItemContent` (`Maccy/Models/HistoryItemContent.swift:5`). `Maccy/Storage.swift` is `@MainActor` (`:5`) and exposes **only** `container.mainContext` (`:10`) — there is **no** `newContext()`, **no** `newBackgroundContext()`, **no** autosave, **no** actor wrapper anywhere. Confirmed by repo-wide grep: every `context.insert/processPendingChanges/save/delete/transaction/fetch` call site (`History.swift:108, 133-135, 168, 206-207, 230-241, 263-265, 282-284, 458`; `HistoryItem.swift:45`) targets `Storage.shared.context` exclusively.

This audit deliberately focuses on the **data pipeline and storage correctness/performance/safety**. Where a finding overlaps with the concurrency/UI-blocking audit (`01-concurrency-ui-blocking.md`) or image pipeline (`02-image-pipeline.md`), it is restated here from the storage/data-flow angle.

---

## Summary Table

| ID | Severity | Location | One-line problem |
|---|---|---|---|
| `no-background-modelcontext` | Critical | `Storage.swift:5-35` | Single `mainContext`-only architecture: every fetch/insert/delete/save/processPendingChanges runs on the main thread; no background context, no autosave, no actor isolation of SwiftData. |
| `load-fetch-all-no-predicate-limit-sort` | Critical | `History.swift:106-119` | `load()` issues a bare `FetchDescriptor<HistoryItem>()` — no predicate, no `fetchLimit`, no `sortBy`, no `propertiesToFetch`/faulting — then fully realizes + sorts + decorates every row synchronously on main. |
| `findsimilar-full-table-refetch-each-copy` | Critical | `History.swift:455-470` | `findSimilarItem()` re-fetches the **entire** `HistoryItem` table on every single copy, then does an O(n) `supersedes()` scan; no signature index, no cached signature column. |
| `add-multi-processpending-save-per-copy` | Critical | `History.swift:130-201` | A single copy triggers up to 3 independent `processPendingChanges()`+`save()` round-trips (insert + delete-dup + limit-overflow deletes), all blocking the main thread. |
| `limit-multi-delete-save-storm` | High | `History.swift:122-128, 275-295` | `limitHistorySize()` calls `delete()` once per overflow item; each `delete()` issues its own `processPendingChanges() + save()` — N SQLite writes on main. |
| `add-resorts-whole-array` | High | `History.swift:191-194` | `add()` builds `sorter.sort(all.map(\.item) + [item])` (allocates a new `[HistoryItem]`, runs O(n log n)) just to find one insertion index — should be O(log n) binary search. |
| `delete-pattern-vs-clear-transaction-inconsistent` | High | `History.swift:217-295` | `clear()`/`clearAll()` batch via `context.transaction { delete(model:where:) }`, but per-item `delete()` does **not** use a transaction — inconsistency that hurts both correctness reasoning and throughput. |
| `insert-dedup-ignores-pending-transaction` | High | `History.swift:130-201` | Insert + duplicate-delete + size-limit-trim happen as **separate** save cycles, not a single transaction; an interrupted sequence (crash/quit) can leave a duplicate row or skip the trim. |
| `try-save-swallowed-silently` | High | `History.swift:135, 241, 265, 284`; `HistoryItem.swift:45`; `Clipboard.swift:208` | Every persistence failure is swallowed by `try?` with no logging, no user surface, no retry — a save failure (disk full, locked store) is indistinguishable from success and corrupts in-memory vs on-disk truth. |
| `recover-container-deletes-store-data-loss` | High | `Storage.swift:37-72` | `recoverContainer` unconditionally deletes the SQLite/WAL/SHM store on first container-init failure (`removeStoreFiles`) — silent, irreversible data loss with no backup, no user opt-in. |
| `dedup-merges-by-copying-value-array` | Medium | `History.swift:149-167` | On duplicate merge, contents are duplicated via `existingHistoryItem.contents.map { HistoryItemContent(type:value:) }` — full byte copy of every content blob, then the old item is deleted; doubles transient memory for large items. |
| `dedup-merge-orphans-inverse-not-rewired` | Medium | `History.swift:149-168`, `HistoryItemContent.swift:17-18` | New `HistoryItemContent` rows are constructed without setting `.item`; the inverse is only implicitly wired by SwiftData after insert. Combined with the synchronous delete of the old item, there is a window where `HistoryItemContent.item` is `nil`. |
| `duplicatesignature-recomputed-per-existing-item` | Medium | `HistoryItem.swift:86-95`, `HistoryItemEngine.swift:46-51, 110-119` | `existingItem.supersedes(signature)` re-derives a `ContentSignature` per existing item per copy (allocates `[ContentSignature]` and a `ContentIndex` for every existing row); fingerprint is recomputed for blobs ≥ 16 KiB per comparison. |
| `contentdata-linear-scan-on-many-getters` | Medium | `HistoryItem.swift:159-258` | `contentData(_:)` / `allContentData(_:)` are O(contents.count) linear scans invoked by `imageData`, `text`, `htmlData`, `rtfData`, `modified`, `fromMaccy`, `universalClipboard*`, `fileURLs` — repeatedly realized during decorate/render. |
| `sessionlog-holds-strong-historyitem-refs` | Medium | `History.swift:60-61, 179, 227, 260, 289` | `sessionLog: [Int: HistoryItem]` retains `@Model` instances by `changeCount`; entries are only pruned opportunistically; pins are never pruned (`sessionLog.removeValues { $0.pin == nil }` excludes pinned), so the log grows with copy churn. |
| `no-coalesce-of-ingest-writes` | Medium | `Clipboard.swift:156-215`, `History.swift:130-201` | Clipboard writes are not coalesced: a copy storm (e.g. select-all in an editor that fires multiple `changeCount` ticks) runs the full ingest + DB save synchronously for each tick. |
| `only-search-is-throttled` | Medium | `History.swift:22-36, 57` | The single `Throttler(minimumDelay: 0.2)` only governs `searchQuery`; there is **no** throttle/coalesce on ingest, save, or `refreshVisibleItems`. |
| `modelconfiguration-options-unused` | Medium | `Storage.swift:21-35` | `ModelConfiguration(url:)` is created with defaults — `allowsSave`, `allowsUndo`, `cloudKitDatabase`, `groupContainer`, and SwiftData autosave/`shouldBatchOperations`-style behaviors are not configured. |
| `no-indexes-on-predicate-columns` | Medium | `HistoryItem.swift:42-48`, `Storage.xcdatamodel/contents:3-11` | The schema declares no indexes; `availablePins` queries `pin != nil` and `clear()` deletes `pin == nil` via predicates, but without an index these are full scans. |
| `schema-maxvaluestring-203-truncates-title` | Medium | `Storage.xcdatamodel/contents:9` | `title` is declared `maxValueString="203"` in the .xcdatamodel — the model file imposes a 203-char ceiling that is unrelated to `HistoryItem.titlePreviewLimit = 1_000` and may silently truncate long titles at the persistence layer. |
| `xcdatamodel-classname-mismatch-historyitemL` | Low | `Storage.xcdatamodel/contents:3,12` | `representedClassName="HistoryItemL"` / `"HistoryItemContentL"` — legacy suffix that does not match the Swift `@Model` class names; relies on SwiftData’s `usedWithSwiftData="YES"` mapping, but is a latent confusion/error surface. |
| `empty-legacy-xcdatamodeld-history` | Low | `History.xcdatamodeld/History.xcdatamodel/contents` | The `History.xcdatamodeld` package contains an empty `<elements/>` model — dead legacy schema still shipped/built; should be removed. |
| `fetchcount-withLogging-on-every-mutation` | Low | `History.swift:204-214, 220, 255, 281` | `withLogging` runs **two** `fetchCount` queries (HistoryItem + HistoryItemContent) before and after every `clear`/`clearAll`/`delete` — 4 round-trips of pure diagnostics on the main thread, in production. |
| `processpendingchanges-called-manually-and-redundantly` | Low | `History.swift:134, 240, 264, 283` | `processPendingChanges()` is invoked manually in 4 places right before `save()`. `save()` already processes pending changes internally; the explicit call is redundant work and signals confusion about SwiftData semantics. |
| `no-prefetch-on-popup-open` | Medium | `Popup.swift:75-87`, `FloatingPanel.swift:74-87`, `ContentView.swift:55-57` | The popup’s only data load is `ContentView.task { try? await appState.history.load() }`; there is no pre-warm when the hotkey is **pressed** (only after the panel becomes key), no prefetch of the visible window’s thumbnails/preview, no idle prepare. |
| `load-no-relationship-faulting` | Medium | `History.swift:106-119`, `HistoryItem.swift:73-74` | `load()` realizes each `HistoryItem` row and (via decorator init) touches `contents` (`imageData`, `application`, `title`) — faults are fired eagerly per row with no `relationshipKeyPathsForPrefetching` and no batched fetch. |
| `decorator-init-side-effects-during-load` | Medium | `HistoryItemDecorator.swift:77-87`, `ApplicationImageCache.swift:10-23` | `load()` maps every row through `HistoryItemDecorator($0)`; the initializer synchronously copies `imageData` (retains blob), calls `ApplicationImageCache.shared.getImage` (which on miss builds an `ApplicationImage` + may hit `NSWorkspace`), and starts two `withObservationTracking` loops — all on the main thread, per row. |
| `history-not-sendable-context-escape` | Medium | `Storage.swift:5-10`, `HistoryItemDecorator.swift:8` | `ModelContext` is not `Sendable`; `History` is `@Observable` (not isolated) but its methods are `@MainActor`; the `@unchecked Sendable` on `HistoryItemDecorator` combined with mutable `var` and main-actor-only methods is a Swift-6 hazard. |
| `sorter-pinned-double-sort` | Low | `Sorter.swift:26-30` | `sort()` runs `.sorted(bySortingAlgorithm)` then `.sorted(byPinned)` — two full stable sorts; for nearly-sorted inputs (single insert) this is needlessly O(n log n) twice. |
| `unpinning-and-pin-randomavailablepin-extra-fetch` | Low | `HistoryItemDecorator.swift:219-225`, `HistoryItem.swift:40-48` | `togglePin()` calls `HistoryItem.randomAvailablePin`, which fetches all pinned rows from disk just to pick a random free letter — a DB round-trip per pin action. |
| `macos15-insert-twice-branch` | Low | `History.swift:141-146`, `Clipboard.swift:204-209` | Insert path forks on `if #available(macOS 15.0, *)`; on macOS 14 the item is inserted in `Clipboard.checkForChangesInPasteboard` and then `add()` skips re-insert — fragile, easy to regress into a double-insert. |
| `availablepins-fetch-uses-try-swallow` | Low | `HistoryItem.swift:42-48` | `availablePins` does `try? Storage.shared.context.fetch(...)` then `?? []`; a fetch error is silently treated as “all pins free,” which could assign a duplicate pin. |

**Correct code (do not "fix"):**
- `@Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)` (`HistoryItem.swift:73`) correctly cascades deletes so contents are not orphaned on `delete(_:)`.
- `HistoryItemContent.maxValueSize` (`HistoryItemContent.swift:7-12`) caps each blob before persistence — guards against pathological clipboard payloads.
- `findSimilarItem` correctly excludes self via `existingItem != item` (`History.swift:460`).
- `ClipboardDataProcessor.dataLikelyEqual` short-circuits on length and fingerprints blobs ≥ 16 KiB (`ClipboardDataProcessor.swift:39-60`) — the fingerprint *strategy* is sound; the problem is *where/when* it’s recomputed (see `duplicatesignature-recomputed-per-existing-item`).
- `clear()`/`clearAll()` use `context.transaction { ... }` to group predicate deletes (`History.swift:230-242`, `262-265`) — directionally correct (see `delete-pattern-vs-clear-transaction-inconsistent` for the inconsistency).
- The C++ `fnv1a64` fingerprint (`Processor/ClipboardByteProcessor.cpp:78-85`) and `validUTF8PrefixLength` (`:19-76`) are correct, allocation-free, and the right tool — the issue is the Swift call-site frequency, not the implementation.
- `ContentIndex` builds a `[String: [Data]]` map once per `Signature.isContained(in:)` (`HistoryItemEngine.swift:122-142`) — sensible single-pass indexing per item.

---

## Grouped Findings

### 1. Storage / ModelContext Architecture

#### `no-background-modelcontext` — Critical
- **Location:** `Maccy/Storage.swift:5-35`.
- **Problem:** `Storage` is `@MainActor` and exposes only `var context: ModelContext { container.mainContext }`. Every persistence operation in the app — fetches (`History.load`, `findSimilarItem`, `availablePins`), inserts (`insertIntoStorage`), deletes (`delete`, `clear`, `clearAll`, `limitHistorySize`), `processPendingChanges`, `save`, `transaction`, and `fetchCount` diagnostics — funnels through this single main-actor context. There is no `container.newContext()` / `newBackgroundContext()`, no actor-wrapped store, no autosave configuration, and `ModelContext` is not `Sendable`.
- **Evidence:**
  ```swift
  // Storage.swift:5-10
  @MainActor
  class Storage {
    static let shared = Storage()
    var container: ModelContainer
    var context: ModelContext { container.mainContext }
  ```
  Repo-wide grep confirms **every** context access targets `Storage.shared.context` (History.swift ×9 sites, HistoryItem.swift:45). No `newContext`/`autosave`/`ModelConfiguration(cloudKitDatabase:|allowsSave:|...)` anywhere.
- **Impact:** All DB I/O is main-thread by construction. SQLite fetches, B-tree scans, WAL checkpoint writes, and `processPendingChanges` reconciliation compete with UI rendering and pasteboard polling on the same run loop. This is the architectural root cause that makes `load()`, `findSimilarItem`, `limitHistorySize`, and every save visibly block the UI. It also blocks the Swift-6 migration: `ModelContext` is non-`Sendable`, so passing it across isolation boundaries is impossible without an actor wrapper that does not exist.
- **Recommendation:** Introduce a dedicated persistence actor:
  - Keep `mainContext` for UI-bound reads if desired, **or** route all writes through a background context obtained via `container.newContext()` (SwiftData) wrapped in a `PersistenceActor` (`actor PersistenceStore { let container: ModelContainer }`). Each write task creates a context, mutates, saves, then propagates the change to the main context via `MainActor.assumeIsolated` merge or a notification.
  - Configure `ModelConfiguration(autosaveEnabled: true, ...)` (or its current API equivalent) so trivial writes do not require an explicit `save()`.
  - Surface a typed `DBError` instead of `try?` (see `try-save-swallowed-silently`).
  - Under Swift 6 strict concurrency, the actor becomes the single `Sendable` boundary; `HistoryItem`/`HistoryItemContent` (`@Model`) remain non-`Sendable` and are only touched inside the actor (or on main after a fetch).
- **Swift-6 / safety:** Critical enabler — without this, no other concurrency finding can be cleanly fixed.

---

### 2. Fetch / Load

#### `load-fetch-all-no-predicate-limit-sort` — Critical
- **Location:** `Maccy/Observables/History.swift:106-119`.
- **Problem:** `load()` constructs a bare `FetchDescriptor<HistoryItem>()` and `try context.fetch(descriptor)`. There is **no** `predicate`, **no** `fetchLimit`, **no** `sortBy`, **no** `propertiesToFetch`, and **no** `relationshipKeyPathsForPrefetching`. Every row in `Storage.sqlite` is realized, then the entire array is re-sorted in Swift via `sorter.sort(results)`, then **every** row is decorated via `HistoryItemDecorator($0)`. For a 500/999-row history (the UI stepper ceiling, `StorageSettingsPane.swift:69`) this is hundreds of full row realizations + decorator inits on the main thread.
- **Evidence:**
  ```swift
  // History.swift:106-119
  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try Storage.shared.context.fetch(descriptor)
    all = sorter.sort(results).map { HistoryItemDecorator($0) }
    items = all
    limitHistorySize(to: historySizeLimit)
    updateShortcuts()
    Task { AppState.shared.popup.needsResize = true }
  }
  ```
- **Impact:** Popup-open latency is dominated by this fetch+sort+decorate. On cold launch with a large store the entire history is loaded before any UI is interactive. Decorator init is itself expensive (`decorator-init-side-effects-during-load`).
- **Recommendation:**
  - Push the sort into the descriptor: `descriptor.sortBy = [SortDescriptor(\.lastCopiedAt, order: .reverse)]` (driven by `Defaults[.sortBy]`); pinned-first is the only thing the in-memory sort adds and can be applied only to the visible slice.
  - Set a `fetchLimit` generously above the visible window (e.g. `historySizeLimit`) and lazy-load the tail on scroll.
  - Use `propertiesToFetch` to avoid hydrating `contents` for off-screen rows, and `relationshipKeyPathsForPrefetching` to batch-fire content faults only for the visible window.
  - Move the fetch to a background context (see `no-background-modelcontext`) and decorate only the visible slice on main.
- **Swift-6 / safety:** A background fetch returns non-`Sendable` `@Model` instances; pass `PersistentIdentifier`s (Sendable) across the boundary and realize on main, or keep reads on main but at least cap and sort in the descriptor.

#### `load-no-relationship-faulting` — Medium
- **Location:** `History.swift:106-119`; `HistoryItem.swift:73-74, 159-258`.
- **Problem:** After `fetch`, `HistoryItemDecorator($0)` reads `item.title`, `item.imageData` (which calls `contentData([.tiff,.png,.jpeg,.heic])` → touches `contents`), and `ApplicationImageCache.shared.getImage(item:)` (reads `item.application`, `item.universalClipboard`). The first access to `contents` per row fires a relationship fault → one SQLite round-trip per row, serially, on main. No `relationshipKeyPathsForPrefetching` is set, so faults are not batched.
- **Evidence:** `HistoryItemDecorator.init` (`:77-87`) touches `item.title`, `item.imageData`, `applicationImage = ApplicationImageCache.shared.getImage(item: item)`. `imageData` (`HistoryItem.swift:175-183`) calls `contentData(...)` which iterates `contents` (`:244-252`).
- **Impact:** For N rows the load path issues up to N relationship fault round-trips plus N decorator inits, all serialized on main.
- **Recommendation:** Configure `descriptor.relationshipKeyPathsForPrefetching = [\.contents]` so contents for the fetched window are loaded in a single SQL `IN (…)` join; or fetch `HistoryItemContent` separately with a predicate on the realized IDs.

#### `decorator-init-side-effects-during-load` — Medium
- **Location:** `Maccy/Observables/HistoryItemDecorator.swift:77-87`; `ApplicationImageCache.swift:10-23`.
- **Problem:** The decorator initializer does heavy synchronous work per row: (1) copies `item.imageData` into `private let imageData: Data?` — **retains the entire image blob** for every history row in memory even if it is never shown; (2) calls `ApplicationImageCache.shared.getImage(item:)` which on cache miss builds an `ApplicationImage` and (per `ApplicationImage.swift`) hits `NSWorkspace.urlForApplication`; (3) starts two `withObservationTracking` re-arm loops. Doing this N times during `load()` is the dominant per-row cost.
- **Evidence:**
  ```swift
  // HistoryItemDecorator.swift:77-87
  @MainActor
  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.imageData = item.imageData       // full blob retained
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)
    synchronizeItemPin()
    synchronizeItemTitle()
  }
  ```
- **Impact:** For a 999-row image-heavy history this retains up to 999 decoded-or-raw image blobs and runs 999 icon lookups on the main thread at load time.
- **Recommendation:** Lazily fetch `imageData` on first access (the decorator already has `image()` laziness for the `NSImage` decode — extend it to the data itself). Pre-warm only the visible window’s icons/thumbnails when the popup opens.

---

### 3. Insert / Dedup

#### `findsimilar-full-table-refetch-each-copy` — Critical
- **Location:** `Maccy/Observables/History.swift:455-470`.
- **Problem:** On every copy, `findSimilarItem(_:)` builds a bare `FetchDescriptor<HistoryItem>()` (no predicate, no limit), **re-fetches the entire table from SQLite**, computes the candidate’s `duplicateSignature` once, then linearly scans all rows calling `existingItem.supersedes(signature)`. Each `supersedes` constructs a `ContentIndex` and (per content ≥ 16 KiB) recomputes an FNV-1a fingerprint. There is no in-memory signature cache and no signature column/index on disk.
- **Evidence:**
  ```swift
  // History.swift:455-470
  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    let descriptor = FetchDescriptor<HistoryItem>()
    if let all = try? Storage.shared.context.fetch(descriptor) {
      let signature = item.duplicateSignature
      for existingItem in all where existingItem != item {
        if existingItem.supersedes(signature) {
          return existingItem
        }
      }
      return isModified(item)
    }
    return nil
  }
  ```
  This is the per-copy dedup path: `AppDelegate.swift:52` registers `Clipboard.shared.onNewCopy { History.shared.add($0) }`, and `add()` calls `findSimilarItem(item)` (`History.swift:149`).
- **Impact:** O(n) DB fetch + O(n) signature comparison per copy. With n=999 rows and a 0.1 s poll interval, every pasteboard tick pays this. It is the single biggest per-copy cost.
- **Recommendation:**
  - Maintain an in-memory signature index `[Signature: HistoryItem]` (or `[UInt64: [HistoryItem]]` keyed by the FNV-1a fingerprint of the dominant content). Update it on insert/delete/clear. Lookups become O(1)-ish.
  - Optionally persist a `signature` / `contentHash` column on `HistoryItem` and add a unique-ish index; the dedup fetch becomes a `#Predicate { $0.signature == candidate }` with `fetchLimit = 1`.
  - The C++ `fingerprint(for:)` is already correct and cheap; cache its result on the `@Model` (transient `@ObservationIgnored var cachedFingerprint: UInt64?`) instead of recomputing.

#### `duplicatesignature-recomputed-per-existing-item` — Medium
- **Location:** `Maccy/Models/HistoryItem.swift:86-95`; `Maccy/Engine/HistoryItemEngine.swift:46-51, 110-119, 153-165`.
- **Problem:** `existingItem.supersedes(signature)` calls `HistoryItemEngine.contains(contents:signature:)` → `signature.isContained(in: existingItem.contents)` → builds a fresh `ContentIndex(existingItem.contents)` and, for each content ≥ 16 KiB, calls `ClipboardDataProcessor.fingerprintIfLarge` (which calls into C++ `MaccyTextProcessor.fingerprint(for:)`). So for every existing row × every copy, a new `ContentIndex` is built and large blobs are re-fingerprinted.
- **Evidence:** `HistoryItemEngine.swift:153-165`:
  ```swift
  func contains(type: String, value: Data?, fingerprint: UInt64?) -> Bool {
    guard let value else { return nilValueTypes.contains(type) }
    guard let values = contentsByType[type] else { return false }
    return values.contains {
      ClipboardDataProcessor.dataLikelyEqual($0, value, rhsFingerprint: fingerprint)
    }
  }
  ```
  `ContentSignature.init` (`:115-119`) stores `fingerprint = content.value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)` — so the *candidate* fingerprint is computed once, but the *existing* side re-fingerprints via `dataLikelyEqual`’s `lhsFingerprint ?? MaccyTextProcessor.fingerprint(for: lhs)` (`ClipboardDataProcessor.swift:53`).
- **Impact:** For history containing many large text/image blobs, every copy re-fingerprints every existing large blob.
- **Recommendation:** Cache the per-content fingerprint on `HistoryItemContent` (transient or persisted). Build the existing item’s `ContentIndex` once at load time and keep it warm; or short-circuit by comparing the candidate’s `Signature` against a precomputed per-item aggregate signature.

#### `add-resorts-whole-array` — High
- **Location:** `Maccy/Observables/History.swift:191-194`; `Maccy/Sorter.swift:26-49`.
- **Problem:** To find the insertion index of a single new item, `add()` allocates `all.map(\.item) + [item]` (a brand-new `[HistoryItem]` of length n+1) and runs `sorter.sort(...)` which performs **two** stable sorts (`bySortingAlgorithm` then `byPinned`). This is O(n log n) work plus an O(n) allocation on every copy, just to locate one index.
- **Evidence:**
  ```swift
  // History.swift:191-194
  let sortedItems = sorter.sort(all.map(\.item) + [item])
  if let index = sortedItems.firstIndex(of: item) {
    all.insert(itemDecorator, at: index)
  }
  ```
  `Sorter.sort` (`:26-30`): `.sorted(by: bySortingAlgorithm).sorted(by: byPinned)`.
- **Impact:** Per-copy allocation + O(n log n) sort on the main thread; wasteful for a single insertion into an already-sorted array.
- **Recommendation:** Since `all` is already sorted by the same comparator, perform an O(log n) binary search for the insertion index using the same `bySortingAlgorithm` ordering (with the pinned partition handled as a separate sub-range). Drop the temporary `[HistoryItem]` allocation entirely. The same pattern should replace the full re-sort in `togglePin` (`History.swift:439-444`).

#### `dedup-merges-by-copying-value-array` — Medium
- **Location:** `Maccy/Observables/History.swift:149-167`.
- **Problem:** When a duplicate is found and `isModified(item) == nil`, the new item’s contents are rebuilt from the existing item’s contents via `.map { HistoryItemContent(type: $0.type, value: $0.value) }` — a full copy of every `Data` blob. The old `existingHistoryItem` is then deleted (`:168`). For a large image/file duplicate, this transiently doubles the in-memory blob footprint, and the new `HistoryItemContent` rows are inserted while the old ones still exist (until the next save).
- **Evidence:**
  ```swift
  // History.swift:149-167
  if let existingHistoryItem = findSimilarItem(item) {
    if isModified(item) == nil {
      item.contents = existingHistoryItem.contents.map {
        HistoryItemContent(type: $0.type, value: $0.value)
      }
    }
    ...
    Storage.shared.context.delete(existingHistoryItem)
  }
  ```
- **Impact:** Extra allocations and a doubled transient memory footprint per duplicate; the contents are semantically identical to the existing item’s.
- **Recommendation:** Prefer to **update** the existing `HistoryItem` in place (bump `lastCopiedAt`/`numberOfCopies`, refresh `application`/`fromMaccy`) and skip creating new content rows entirely; only re-create contents when `isModified(item) != nil`. If new contents are required, delete the old rows in the same transaction as the insert (see `insert-dedup-ignores-pending-transaction`).

#### `dedup-merge-orphans-inverse-not-rewired` — Medium
- **Location:** `History.swift:149-168`; `Maccy/Models/HistoryItemContent.swift:17-18`.
- **Problem:** `HistoryItemContent(type:value:)` is constructed without an `.item` assignment. The inverse relationship is only established after SwiftData processes pending changes (which `add()` does only at `insertIntoStorage`, called *before* the contents are reassigned at `:151`). Combined with the immediate `context.delete(existingHistoryItem)` at `:168` (which cascades to its contents), there is an ordering window where the new content rows reference a not-yet-linked parent and the old parent is marked for deletion.
- **Evidence:** `HistoryItemContent.init` (`HistoryItemContent.swift:20-23`) sets only `type`/`value`; `@Relationship var item: HistoryItem?` defaults to `nil`. `add()` calls `insertIntoStorage` first (`History.swift:142`), then reassigns `item.contents` (`:151`), then deletes the existing item (`:168`) — these are not wrapped in a single `transaction`.
- **Impact:** Mostly absorbed by SwiftData’s eventual reconciliation, but it is fragile: a crash between `:151` and the final `save()` could leave orphaned `HistoryItemContent` rows (parent still pointing at the deleted `existingHistoryItem`) or violate the cascade invariant under partial-failure modes.
- **Recommendation:** Wrap insert + content reassignment + duplicate-delete in a single `context.transaction { ... }` so the relationship graph is consistent at the save boundary.

---

### 4. Delete / Size-limit

#### `limit-multi-delete-save-storm` — High
- **Location:** `Maccy/Observables/History.swift:122-128` (caller), `:275-295` (`delete`).
- **Problem:** `limitHistorySize(to:)` computes the overflow slice `unpinned[maxSize...]` and calls `delete` once per overflow item. Each `delete()` issues `context.delete` + `processPendingChanges()` + `try? save()` **independently**. So trimming k items = k separate SQLite write transactions on the main thread.
- **Evidence:**
  ```swift
  // History.swift:121-128
  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    let maxSize = max(0, maxSize)
    let unpinned = all.filter(\.isUnpinned)
    if unpinned.count > maxSize {
      unpinned[maxSize...].forEach(delete)   // delete() saves per call
    }
  }
  // History.swift:275-295 (excerpt)
  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    ...
    withLogging("Removing history item") {
      Storage.shared.context.delete(item.item)
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }
    ...
  }
  ```
- **Impact:** When `add()` calls `limitHistorySize(to: historySizeLimit - 1)` (`:177`), every copy at the size ceiling trims ≥ 1 item — each via its own save. A bulk import or rapid-copy storm produces a save storm.
- **Recommendation:** Add a batched `delete(_ items: [HistoryItemDecorator])` that issues all `context.delete`s inside a single `transaction { ... }` followed by one `processPendingChanges()` + one `save()`. Have `limitHistorySize` collect the overflow slice and call the batched variant. Mirror the `clear()` pattern.

#### `delete-pattern-vs-clear-transaction-inconsistent` — High
- **Location:** `History.swift:217-249` (`clear`), `:251-273` (`clearAll`), `:275-295` (`delete`).
- **Problem:** `clear()` and `clearAll()` batch deletes via `context.transaction { context.delete(model:where:) }` (good), but the per-item `delete(_:)` path does **not** wrap its single delete in a transaction, and additionally calls `processPendingChanges()` before `save()` (redundant). The codebase therefore has two divergent delete conventions for no apparent reason.
- **Evidence:**
  ```swift
  // clear():230-242 — transaction
  try? Storage.shared.context.transaction {
    try? Storage.shared.context.delete(model: HistoryItem.self,
                                        where: #Predicate { $0.pin == nil })
    try? Storage.shared.context.delete(model: HistoryItemContent.self,
                                        where: #Predicate { $0.item?.pin == nil })
  }
  Storage.shared.context.processPendingChanges()
  try? Storage.shared.context.save()

  // delete():282-284 — NO transaction
  Storage.shared.context.delete(item.item)
  Storage.shared.context.processPendingChanges()
  try? Storage.shared.context.save()
  ```
- **Impact:** Inconsistent transactional guarantees; per-item deletes are not atomic w.r.t. concurrent reads/writes from other code paths, and the redundancy with `clear()`’s pattern signals unclear ownership.
- **Recommendation:** Standardize on one path: every mutation (insert, single delete, batch delete, dedup merge) goes through a `mutate(_ block: (ModelContext) throws -> Void)` helper that wraps the block in `context.transaction { ... }` and issues a single `save()` (no manual `processPendingChanges`). Remove the ad-hoc `processPendingChanges()` calls.

---

### 5. Writes / Saves / Transactions

#### `add-multi-processpending-save-per-copy` — Critical
- **Location:** `Maccy/Observables/History.swift:130-201`.
- **Problem:** A single `add(item)` invocation can trigger up to three separate save cycles on the main thread:
  1. `insertIntoStorage(item)` at `:142` → `context.insert` + `processPendingChanges()` + `try? save()` (`:133-135`).
  2. If a duplicate is found, `context.delete(existingHistoryItem)` at `:168` — whose eventual flush is *not* in the same save as #1 (the save already happened at `:135`).
  3. `limitHistorySize(to: historySizeLimit - 1)` at `:177` → `delete()` per overflow item, each with its own `processPendingChanges()` + `save()` (`:283-284`).
- **Evidence:** See snippets above for `insertIntoStorage` (`:130-136`), `add` (`:140-201`), `delete` (`:275-295`). The duplicate-delete and limit-delete happen *after* the insert has already been saved.
- **Impact:** Worst-case latency per copy = (insert save) + (dup delete save) + (k limit-delete saves), each blocking the main thread and each flushing WAL. This is the per-copy storage tax.
- **Recommendation:** Make `add()` a single transactional unit: stage the insert, the optional duplicate-delete, and the size-limit trim, then flush once (`context.transaction { … }; save()`). Combined with a background context (`no-background-modelcontext`) the entire copy→persist path becomes off-main.

#### `insert-dedup-ignores-pending-transaction` — High
- **Location:** `History.swift:130-201`.
- **Problem:** Insert + duplicate-delete + size-limit-trim are sequenced as **separate** save cycles. If the process is interrupted (crash, `applicationWillTerminate`, force-quit) between saves, the persisted state can diverge from the in-memory `all` array: e.g. the duplicate is deleted in memory but the new row’s contents were never saved, or the new row is persisted but the overflow trim was not.
- **Evidence:** `insertIntoStorage` saves at `:135` *before* `findSimilarItem` runs (`:149`); the duplicate delete at `:168` is saved only by a later path (or never explicitly saved in `add` — the next copy or the next `delete` flushes it). `limitHistorySize` saves per-item via `delete`.
- **Impact:** Data-safety gap: on-disk and in-memory can disagree across an interruption. For a clipboard manager whose entire value is “remember everything,” this is a correctness risk.
- **Recommendation:** Wrap the whole `add()` body (post-decode) in `context.transaction { … }` with a single terminal `save()`. Crash/quit safety improves because either the entire copy is persisted or none of it is.

#### `try-save-swallowed-silently` — High
- **Location:** `History.swift:135, 241, 265, 284`; `Maccy/Models/HistoryItem.swift:45`; `Maccy/Clipboard.swift:208`.
- **Problem:** Every persistence failure is silenced with `try?` (and `try? … .fetch` in `findSimilarItem`, `availablePins`, `withLogging`). There is no `catch`, no `Logger` call, no user surface, and no retry. A SQLite write failure (disk full, store locked by another process, WAL corruption, sandbox denial) is indistinguishable from success to the rest of the app — `all` keeps the new item but `Storage.sqlite` does not.
- **Evidence:**
  ```swift
  // History.swift:133-135
  Storage.shared.context.insert(item)
  Storage.shared.context.processPendingChanges()
  try? Storage.shared.context.save()        // ← swallowed
  // HistoryItem.swift:45
  let pins = try? Storage.shared.context.fetch(descriptor).compactMap({ $0.pin })
  // Clipboard.swift:208
  try? History.shared.insertIntoStorage(historyItem)
  ```
- **Impact:** Silent data divergence; the user believes a copy was saved when it was not. Also masks the recoverable vs unrecoverable distinction that `recoverContainer` is supposed to handle.
- **Recommendation:** Replace `try?` with `do/catch` that logs via `History.logger` (already present, `History.swift:14`) and surfaces a non-blocking user notification on hard failures; for transient failures (busy store), retry once on a background queue. For reads (`availablePins`), treat a fetch failure pessimistically (assume no free pins) rather than optimistically.

#### `recover-container-deletes-store-data-loss` — High
- **Location:** `Maccy/Storage.swift:37-72`.
- **Problem:** `recoverContainer(from:originalError:)` is called on the **first** container-init failure and immediately calls `removeStoreFiles(for: url)` — deleting `Storage.sqlite`, `-shm`, and `-wal`. There is no backup, no copy aside, no user opt-in, and no diagnostic about what was discarded. If the failure was transient (e.g. a held lock, a momentary sandbox issue, a partial upgrade), the user’s entire clipboard history is destroyed.
- **Evidence:**
  ```swift
  // Storage.swift:37-44
  private static func recoverContainer(from url: URL, originalError: Error) -> ModelContainer {
    removeStoreFiles(for: url)   // ← deletes store, shm, wal unconditionally
    do {
      return try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
    } catch { ... }
  }
  ```
- **Impact:** Catastrophic, silent, irreversible data loss as a recovery default. For a clipboard manager this is the worst-case safety failure short of crash.
- **Recommendation:**
  - Before deleting, **move** the existing store files to a quarantine dir (e.g. `Application Support/Maccy/Storage.sqlite.corrupt-<timestamp>`) and log it; offer the user a restore action.
  - Distinguish error types: schema-mismatch errors deserve migration (not deletion); a transient lock does not warrant deletion at all.
  - Surface the data loss to the user explicitly (the existing `NSAlert` only says “temporary in-memory history,” not “we just deleted your history file”).

#### `processpendingchanges-called-manually-and-redundantly` — Low
- **Location:** `History.swift:134, 240, 264, 283`.
- **Problem:** `processPendingChanges()` is invoked manually immediately before each `save()`. In SwiftData/CoreData, `save()` internally processes pending changes first (it is part of the save lifecycle). The explicit call therefore performs the reconciliation twice for no behavioral benefit and signals confusion about the framework contract.
- **Evidence:** All four sites follow the pattern `context.insert/delete(...); context.processPendingChanges(); try? context.save()`.
- **Impact:** Doubled reconciliation work per save (minor), plus a maintenance hazard — future contributors may rely on the manual call having side effects.
- **Recommendation:** Drop the explicit `processPendingChanges()` calls; rely on `save()`. If a synchronous snapshot of pending state is genuinely needed at a specific point, document why.

#### `modelconfiguration-options-unused` — Medium
- **Location:** `Maccy/Storage.swift:21-35`.
- **Problem:** `ModelConfiguration(url: url)` is created with defaults only. SwiftData options that materially affect the data pipeline are not set: autosave (would eliminate most explicit `save()` calls), `allowsSave`/`allowsUndo`, `cloudKitDatabase` (for sync), and the equivalents of batch operation hints. The testing branch only flips `isStoredInMemoryOnly`.
- **Evidence:**
  ```swift
  // Storage.swift:21-28
  var config = ModelConfiguration(url: url)
  #if DEBUG
  if CommandLine.arguments.contains("enable-testing") {
    config = ModelConfiguration(isStoredInMemoryOnly: true)
  }
  #endif
  ```
- **Impact:** The pipeline pays for explicit `save()` calls and batchless write behavior that autosave or batched operations could remove; future CloudKit sync is not even pre-wired.
- **Recommendation:** Evaluate `ModelConfiguration(url: url, autosaveEnabled: true, …)` (current SwiftData API name at the project’s deployment target) to coalesce trivial writes; explicitly decide on CloudKit; document the choice either way.

---

### 6. Throttling / Coalescing

#### `no-coalesce-of-ingest-writes` — Medium
- **Location:** `Maccy/Clipboard.swift:156-215`; `History.swift:130-201`.
- **Problem:** Clipboard writes are not coalesced. Each `pasteboard.changeCount` tick that survives the early ignores causes a full synchronous ingest: `contents(from:)` → `HistoryItem(contents:)` → `generateTitle()` → `History.add` → insert + dedup fetch + save + (optional) dup-delete save + (optional) limit-delete saves. Applications that bump `changeCount` multiple times per logical copy (BBEdit, Edge — see `Clipboard.swift:191-194` comment) or “select-all + copy” storms therefore replay the entire pipeline N times in quick succession.
- **Evidence:** `Clipboard.checkForChangesInPasteboard` (`:156-215`) returns from `onNewCopyHooks.forEach({ $0(historyItem) })` with no debounce; `AppDelegate.swift:52` registers the un-throttled `History.shared.add($0)` hook.
- **Impact:** Repeated full-table dedup fetches + repeated saves for what is logically one user copy.
- **Recommendation:** Add an ingest coalescer (e.g. a 50–150 ms `Throttler` with a trailing edge) keyed on a content signature, so a burst of pasteboard ticks collapses into one insert/dedup/save. Keep the search `Throttler` separate.

#### `only-search-is-throttled` — Medium
- **Location:** `History.swift:22-36, 57`; `Throttler.swift`.
- **Problem:** The codebase has exactly one `Throttler(minimumDelay: 0.2)`, used only for `searchQuery` updates. Ingest, save, `refreshVisibleItems`, and `popup.needsResize` are unthrottled and run eagerly on every event.
- **Impact:** Search is the only path protected from input storms; every other hot path can overrun the main thread.
- **Recommendation:** Reuse the `Throttler` primitive (or extend it with leading+trailing edges) for ingest coalescing and for resize settling.

---

### 7. Data Flow & Redundancy

#### `sessionlog-holds-strong-historyitem-refs` — Medium
- **Location:** `History.swift:60-61, 179, 227, 260, 289`.
- **Problem:** `@ObservationIgnored private var sessionLog: [Int: HistoryItem]` maps `Clipboard.shared.changeCount` → `HistoryItem`. Entries are added on every insert (`sessionLog[Clipboard.shared.changeCount] = item`, `:179`) and pruned only by `clear()` (`sessionLog.removeValues { $0.pin == nil }`, `:227`), `clearAll()` (`:260`), and `delete()` (`:289`). Crucially, the `clear()` prune **skips pinned items**, so pinned `HistoryItem`s are retained in the log forever even if they were re-copied many times (each copy adds a new entry).
- **Impact:** For long-running sessions the log accumulates entries that mirror (and outlive) the visible `all` array, retaining `@Model` instances and their `contents` blobs in memory. Also used by `isModified(item)` (`:472-478`) to detect “modified” copies, so its growth has a correctness dimension, not just memory.
- **Recommendation:** Cap `sessionLog` size (e.g. evict oldest entries beyond N), use weak references where the `all` array already owns the item, or rebuild the “modified” lookup from a persisted flag rather than a session dictionary.

#### `contentdata-linear-scan-on-many-getters` — Medium
- **Location:** `Maccy/Models/HistoryItem.swift:159-258`.
- **Problem:** `contentData(_:)` and `allContentData(_:)` do O(contents.count) linear scans over the to-many relationship. They are invoked by `htmlData`, `html`, `imageData`, `image`, `rtfData`, `rtf`, `text`, `textPrefix`, `modified`, `fromMaccy`, `universalClipboard`, `universalClipboardText`, `fileURLs`, plus the title/preview path through `HistoryItemEngine`. Multiple getters are called per row per render.
- **Evidence:** `HistoryItem.swift:244-252`:
  ```swift
  private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
    for type in types {
      if let content = contents.first(where: { NSPasteboard.PasteboardType($0.type) == type }) {
        return content.value
      }
    }
    return nil
  }
  ```
- **Impact:** Repeated O(c) scans on hot read paths; especially costly when `contents` fault has just been fired.
- **Recommendation:** Build a `[String: HistoryItemContent]` (or `[NSPasteboard.PasteboardType: HistoryItemContent]`) lookup once per row (lazily cached, invalidated on `contents` mutation) and use it for all typed accessors. The engine’s `ContentIndex` already does this for its own scope; lift the pattern into the model.

---

### 8. Pre-warming / Responsiveness

#### `no-prefetch-on-popup-open` — Medium
- **Location:** `Maccy/Observables/Popup.swift:75-87`; `Maccy/FloatingPanel.swift:74-87`; `Maccy/Views/ContentView.swift:55-57`.
- **Problem:** The popup’s **only** data load is `ContentView.task { try? await appState.history.load() }`, which runs after the SwiftUI view appears — i.e. after the panel is already ordered front and visible. There is no pre-warm when the global hotkey is **pressed** (only after `windowDidBecomeKey`), no prefetch of the visible window’s thumbnails/preview, and no idle-time prepare while the popup is closed. The user goal of “~2× faster UI response with data pre-warmed” is therefore entirely unaddressed.
- **Evidence:** `Popup.handleFirstKeyDown` (`Popup.swift:113-123`) just calls `open(height:)`; `FloatingPanel.open` (`:74-87`) does `setContentSize`/`orderFrontRegardless`/`makeKey`. No data fetch is initiated. `ContentView.task` (`:55-57`) is the first data touch and runs on view appearance.
- **Impact:** Cold-open popup shows an empty/loading list until `load()` finishes on main.
- **Recommendation:**
  - Trigger a background prefetch on hotkey-down (before the panel becomes key): fetch the visible window (e.g. top 50 rows sorted by `lastCopiedAt`) via a background `ModelContext`, realize decorators on main, and cache them so `ContentView` renders instantly.
  - Add an idle pre-warm (e.g. `DispatchSource` timer or `Task.detached` after N seconds of inactivity) that prebuilds thumbnails for the most-recent N items while the popup is closed.
  - Consider keeping the most-recent window “always loaded” (warm) so popup-open is O(visible) not O(n).

---

### 9. Schema / Model

#### `no-indexes-on-predicate-columns` — Medium
- **Location:** `Maccy/Models/HistoryItem.swift:42-48` (`availablePins` predicate `$0.pin != nil`); `Maccy/Observables/History.swift:231-238` (`clear` predicate `$0.pin == nil`, `$0.item?.pin == nil`); `Maccy/Storage.xcdatamodeld/Storage.xcdatamodel/contents:3-16`.
- **Problem:** The `.xcdatamodel` declares **no indexes** on any attribute. `pin`, `firstCopiedAt`, `lastCopiedAt`, and `numberOfCopies` are all used in predicates or sort descriptors at runtime but have no DB-side index. The dedup-fetch (`findSimilarItem`) and load-fetch have no predicate at all, so an index would not help them — but `availablePins` and `clear` would benefit directly.
- **Evidence:** `Storage.xcdatamodel/contents:4-10` lists attributes with no `indexed="YES"`; SwiftData via `usedWithSwiftData="YES"` (`:2`) does not auto-add indexes for `#Predicate` columns.
- **Impact:** `pin != nil` and `pin == nil` are full table scans; `clear()` cost grows linearly with history size. For 999 rows this is negligible in absolute terms, but it is the kind of thing that compounds with CloudKit sync and larger stores.
- **Recommendation:** Add SwiftData `@Attribute(.unique)`/index hints (or modify the model) for `pin`; consider composite indexes for the sort columns. Persist a `contentHash`/`signature` column with an index to turn dedup into a point lookup.

#### `schema-maxvaluestring-203-truncates-title` — Medium
- **Location:** `Maccy/Storage.xcdatamodeld/Storage.xcdatamodel/contents:9`.
- **Problem:** The `title` attribute is declared `maxValueString="203"` in the xcdatamodel, while `HistoryItem.titlePreviewLimit = 1_000` (`HistoryItem.swift:9`) and titles are generated from up to `textPreviewLimit = 10_000` chars (`:10`). The 203-char schema ceiling can silently truncate titles at the persistence layer (SQLite `TEXT` is not actually length-constrained at runtime, but the modeler-declared constraint may be enforced by SwiftData validation on save).
- **Evidence:** `contents:9` — `<attribute name="title" optional="YES" attributeType="String" maxValueString="203"/>`.
- **Impact:** Latent truncation/validation-failure risk on long titles; mismatch between the in-memory cap (1000) and the schema cap (203).
- **Recommendation:** Align the schema with the in-memory limit (or drop the constraint entirely if titles are meant to be ≤ `titlePreviewLimit`). Verify whether SwiftData enforces `maxValueString` on `save()`; if it does, long titles currently throw inside the `try? save()` and are silently dropped.

#### `xcdatamodel-classname-mismatch-historyitemL` — Low
- **Location:** `Maccy/Storage.xcdatamodeld/Storage.xcdatamodel/contents:3,12`.
- **Problem:** Both entities declare `representedClassName="HistoryItemL"` / `"HistoryItemContentL"` — a legacy suffix that does not match the Swift `@Model` class names `HistoryItem` / `HistoryItemContent`. This works only because `usedWithSwiftData="YES"` (`:2`) lets SwiftData map by entity name rather than Obj-C class; it is a latent confusion/error surface for anyone reading the schema or migrating.
- **Recommendation:** Rename `representedClassName` to match the Swift class, or drop the legacy `.xcdatamodeld` package entirely if SwiftData generates its own schema (verify migration implications first).

#### `empty-legacy-xcdatamodeld-history` — Low
- **Location:** `Maccy/History.xcdatamodeld/History.xcdatamodel/contents`.
- **Problem:** The repo ships a second `.xcdatamodeld` package (`History.xcdatamodeld`) whose model is empty (`<elements/>`). It is dead weight — a leftover from the CoreData→SwiftData migration. It still gets compiled/shipped and can confuse readers about which schema is authoritative.
- **Evidence:** `History.xcdatamodel/contents` is `<model ...><elements/></model>`.
- **Recommendation:** Delete `Maccy/History.xcdatamodeld` once you confirm no build phase references it.

#### `fetchcount-withLogging-on-every-mutation` — Low
- **Location:** `Maccy/Observables/History.swift:204-214, 220, 255, 281`.
- **Problem:** `withLogging(_:block:)` issues **two** `context.fetchCount(FetchDescriptor<HistoryItem>())` + `… <HistoryItemContent>()` queries before and after every `clear`/`clearAll`/`delete` — 4 `SELECT COUNT(*)` round-trips of pure diagnostics, on the main thread, in production builds. The `logger.info(...)` calls themselves are also unconditional.
- **Evidence:** `History.swift:204-214`:
  ```swift
  func dataCounts() -> String {
    let historyItemCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
    let historyContentCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>())
    return "HistoryItem=\(historyItemCount ?? 0) HistoryItemContent=\(historyContentCount ?? 0)"
  }
  logger.info("\(msg) Before: \(dataCounts())")
  try? block()
  logger.info("\(msg) After: \(dataCounts())")
  ```
- **Impact:** 4 extra DB round-trips per delete/clear; noise in production logs.
- **Recommendation:** Gate `withLogging` behind `#if DEBUG` or the existing logger level check; in release, skip the `fetchCount` queries entirely.

#### `sorter-pinned-double-sort` — Low
- **Location:** `Maccy/Sorter.swift:26-30`.
- **Problem:** `sort` composes `.sorted(by: bySortingAlgorithm).sorted(by: byPinned)` — two full stable sorts. For a single-insert case (`add`, `togglePin`) the input is already sorted by `bySortingAlgorithm`, so the first sort is wasted work and the second is the only meaningful change.
- **Evidence:** `Sorter.swift:26-30`:
  ```swift
  func sort(_ items: [HistoryItem], by: By = Defaults[.sortBy]) -> [HistoryItem] {
    return items.sorted(by: { bySortingAlgorithm($0, $1, by) }).sorted(by: byPinned)
  }
  ```
- **Impact:** Minor — O(n log n) twice per call; called on every insert/pin-toggle.
- **Recommendation:** Use a single comparator that combines both criteria (pinned partition first, then `bySortingAlgorithm` within each partition). For single-insert, use binary search (see `add-resorts-whole-array`).

#### `unpinning-and-pin-randomavailablepin-extra-fetch` — Low
- **Location:** `Maccy/Observables/HistoryItemDecorator.swift:219-225`; `Maccy/Models/HistoryItem.swift:40-48`.
- **Problem:** `togglePin()` → `HistoryItem.randomAvailablePin` → `availablePins` issues a `context.fetch` over all pinned rows (`#Predicate { $0.pin != nil }`) just to compute `supportedPins.subtracting(assignedPins).randomElement()`. One DB round-trip per pin action.
- **Evidence:** `HistoryItem.swift:42-48`:
  ```swift
  let descriptor = FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin != nil })
  let pins = try? Storage.shared.context.fetch(descriptor).compactMap({ $0.pin })
  ```
- **Impact:** Minor latency per pin; multiplied if the user pins several items in a row.
- **Recommendation:** Track assigned pins in memory (the `History.all` array already knows each item’s `pin`); derive `availablePins` from the in-memory set without a fetch.

#### `macos15-insert-twice-branch` — Low
- **Location:** `Maccy/Observables/History.swift:141-146`; `Maccy/Clipboard.swift:204-209`.
- **Problem:** Insert forks on `if #available(macOS 15.0, *)`. On macOS 15+ the item is inserted inside `add()` (`:142`); on macOS 14 the item is inserted inside `Clipboard.checkForChangesInPasteboard` (`Clipboard.swift:208`) and `add()` skips the insert via the `else` comment. The two paths are easy to regress (a future refactor that removes the macOS-14 branch would silently double-insert on macOS 14; a refactor that removes the macOS-15 branch would never persist on macOS 15).
- **Evidence:** `History.swift:141-146` and `Clipboard.swift:204-209`:
  ```swift
  if #unavailable(macOS 15.0) {
    try? History.shared.insertIntoStorage(historyItem)   // macOS 14 only
  }
  ```
- **Impact:** Fragile; the data-pipeline correctness depends on two call sites staying in sync across an OS-version branch.
- **Recommendation:** Centralize insert in `add()` for all OS versions and drop the `#unavailable` insert in `Clipboard`; if macOS 14 truly needs earlier insertion, document the invariant with an assertion.

#### `availablepins-fetch-uses-try-swallow` — Low
- **Location:** `Maccy/Models/HistoryItem.swift:42-48`.
- **Problem:** `availablePins` does `try? Storage.shared.context.fetch(...)` then `?? []`. A fetch failure is silently treated as “all pins free,” which could cause `togglePin` to assign a pin that is already in use.
- **Evidence:** `:45` `let pins = try? Storage.shared.context.fetch(descriptor).compactMap({ $0.pin })`.
- **Impact:** Low-frequency correctness bug under storage errors.
- **Recommendation:** On fetch failure, treat the assigned-pins set as **unknown** and conservatively refuse to assign a new pin (or fall back to the in-memory `History.all` set).

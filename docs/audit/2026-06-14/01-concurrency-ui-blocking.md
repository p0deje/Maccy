# Concurrency & UI-Blocking Audit — Maccy

**Date:** 2026-06-14
**Scope:** Pasteboard observation, history load/insert/dedup, search, rendering/resize churn, threading/isolation model, concurrency hazards.
**Method:** Direct read of source at repo root `/lzcapp/document/Projects/Maccy`. Every file:line cited was read; snippets are quoted verbatim.
**Verified baseline:** `Maccy/Storage.swift:5,10` — entire pipeline is `@MainActor` and uses only `container.mainContext`. Codebase tally confirmed by grep: **0 `actor`, 0 `nonisolated`, 2 `@unchecked Sendable` (`AppDelegate`, `HistoryItemDecorator`), 6 `DispatchQueue.main.async*`, 1 `DispatchQueue.global()` (`ApplicationImage.swift:58`), 6 declared `async` funcs, ~62 `@MainActor` sites. Build is `SWIFT_VERSION = 5.0` with **no** `SWIFT_STRICT_CONCURRENCY` flag set — i.e. no Swift 6 migration work has begun.

---

## Summary Table

| ID | Severity | Location | One-line problem |
|---|---|---|---|
| `load-no-pipeline-offload` | Critical | `History.swift:106-119` | `load()` does fetch-all + sort-all + decorate-all synchronously on the main thread with no limit/fault/batch. |
| `findsimilar-full-refetch` | Critical | `History.swift:456-470` | `findSimilarItem()` re-fetches the ENTIRE table on every paste to find a duplicate, then O(n)-compares. |
| `pasteboard-polling-callback-heavy` | Critical | `Clipboard.swift:55-64, 156-215` | Timer polling at 0.1–N s fires `@MainActor` handler that runs the entire ingest pipeline synchronously on the main thread. |
| `limit-multi-save-storm` | High | `History.swift:122-128, 275-295` | Size-limit overflow invokes `delete()` per item, each issuing its own `processPendingChanges() + save()` (N SQLite round-trips on main). |
| `insert-resorts-whole-array` | High | `History.swift:191-194` | `add()` re-sorts the entire `all` array (via `sorter.sort(all.map(\.item) + [item])`) just to find the insertion index. |
| `add-does-3-pending-changes-saves` | High | `History.swift:130-201` | A single copy triggers up to 3 separate `processPendingChanges() + save()` cycles (insertIntoStorage + limit + delete-dup), each blocking main. |
| `search-throttle-still-runs-main` | High | `History.swift:22-36`, `Search.swift:46-161` | Throttler(0.2 s) only coalesces keystrokes; the full-scan search + `highlight()` per visible item still run synchronously on main. |
| `richtext-sync-decode-on-ingest` | High | `Clipboard.swift:316-336` | `richText()` synchronously constructs `NSAttributedString(rtf:/html:)` on the main thread on every copy (up to 512 KiB). |
| `regex-shouldignore-on-ingest` | High | `Clipboard.swift:275-302` | `shouldIgnore(item:)` runs every user regex over the pasteboard string synchronously on main on every poll that yields a change. |
| `ocr-vision-on-main` | High | `HistoryItem.swift:97-123` | `generateTitle()` for image items spawns `Task { @MainActor ... }` that runs `NSImage(data:)` + `VNRecognizeTextRequest.perform` on the main thread. |
| `decorator-init-main-decode-icon` | High | `HistoryItemDecorator.swift:77-87`, `ApplicationImage.swift:25-93` | Decorator init (called per item during `load()`) eagerly resolves the app icon via `ApplicationImageCache` / `NSWorkspace.urlForApplication` on main. |
| `no-background-modelcontext` | High | `Storage.swift:5-10` | Only `mainContext` exists; no `newBackgroundContext`, no actor wrapping SwiftData. All DB I/O is main-thread by construction. |
| `timer-no-tolerance-mode` | Medium | `Clipboard.swift:55-64` | `Timer.scheduledTimer` with no `tolerance`, default `.common` mode — pauses under modal tracking and is not power-efficient. |
| `insertionindex-binsearchable` | Medium | `History.swift:191-194`, `Sorter.swift:26-49` | Insert position can be O(log n) binary-searched; current code is O(n log n) per insert. |
| `highlight-rebuild-per-keystroke` | Medium | `HistoryItemDecorator.swift:191-216`, `History.swift:480-489` | `updateItems()` re-runs `highlight()` over up to 500 chars per visible item on every throttled keystroke. |
| `updateunpinned-double-pass` | Medium | `History.swift:516-527` | `updateUnpinnedShortcuts()` mutates every visible unpinned item twice (clear, then re-assign), called on insert/delete/search/pin. |
| `contentdata-linear-scan` | Medium | `HistoryItem.swift:244-258` | `contentData(_:)` / `allContentData(_:)` are O(contents.count) linear scans and are re-invoked on many getters (`imageData`, `text`, `rtf`, `html`, `modified`, …). |
| `contents-multi-dataforType` | Medium | `Clipboard.swift:219-239` | `contents(from:)` calls `item.data(forType:)` once per enabled type plus up to 3 extra reads in `isEmptyString`/`richText`/`shouldIgnore`, all on main. |
| `cleanup-recaches-main` | Medium | `HistoryItemDecorator.swift:137-147` | `cleanupImages()` calls `recache()` (drops bitmap caches) on every `imageMaxHeight` change and on invalidate; main-thread. |
| `ondoublecloselocation-resize-task` | Medium | `History.swift:33, 117, 198, 247, 271, 293`, `HistoryListView.swift:133-141` | `needsResize = true` is sprinkled across insert/delete/search/clear and resolved via `Task.sleep(10 ms)` polling inside a SwiftUI body — reactive but fragile. |
| `combine-crossing-defaults` | Medium | `AppDelegate.swift:55-101`, `History.swift:69-103` | Many `Defaults.updates(...)` async loops mutate main-actor state from cooperative Tasks; no explicit actor boundary or priority hint. |
| `historyitem-unchecked-sendable` | Medium | `HistoryItemDecorator.swift:8` | `@unchecked Sendable` on a class with mutable `var` properties and `@MainActor`-isolated methods — false promise that invites data races under Swift 6. |
| `appdelegate-unchecked-sendable` | Medium | `AppDelegate.swift:6` | `@unchecked Sendable` on a `class` with mutable `var panel` — same hazard. |
| `synctrack-dispatch-main-reentry` | Medium | `HistoryItemDecorator.swift:227-263` | `synchronizeItemPin`/`synchronizeItemTitle` re-arm via `DispatchQueue.main.async` recursion instead of a Swift `Task`/`@Observable` binding; can fire post-invalidate. |
| `storage-recover-task-modal` | Low | `Storage.swift:43-51` | Recovery path uses `Task { @MainActor in NSAlert().runModal() }` — modal runs concurrently with the rest of `recoverContainer`; ordering is incidental. |
| `pressedshortcutitem-each-keystroke` | Low | `History.swift:38-53` | `pressedShortcutItem` is a computed property doing `Sauce.shared.key(...)` + O(items) scan; called from key handling. |
| `applicationimage-dispatchsource-leak-risk` | Low | `ApplicationImage.swift:48-87` | File-system `DispatchSource` is created on the main thread on cache miss; `print(...)` debug logging left in production path. |
| `notifier-uses-unowned-queue` | Low | `Notifier.swift:16-31` | `UNUserNotificationCenter` callbacks run on a background queue; touching `hasRequestedAuthorization` is unsynchronized. |
| `string-shortened-alloc-per-render` | Low | `HistoryItemDecorator.swift:197`, `AppState.swift:28-32` | `title.shortened(to: 500)` and `menuIconText` recompute on every render; small but repeated allocations. |
| `clear-batch-transaction-not-applied-to-processpending` | Low | `History.swift:230-242` | `transaction { ... }` wraps deletes but `processPendingChanges() + save()` still run sequentially after; not a single batched flush. |
| `throttler-no-coalesce-trailing` | Low | `Throttler.swift:16-33` | Throttler cancels-and-replaces; no leading+trailing edge, so rapid typing can delay the final result by 0.2 s. |

**Correct code (do not "fix"):**
- `ApplicationImageCache` is `@MainActor` and dedupes per bundle id (`ApplicationImageCache.swift:1-36`) — good.
- `Search.isLikelyUnsafeRegularExpression` rejects nested-quantifier regexes before running them (`Search.swift:40-44`) — good defensive measure.
- `HistoryItemContent.maxValueSize` caps any single content blob before storage (`HistoryItemContent.swift:7-12`).
- `ClipboardDataProcessor.dataLikelyEqual` short-circuits on length and fingerprints blobs ≥ 16 KiB rather than always comparing bytes (`ClipboardDataProcessor.swift:39-60`) — good.
- `findSimilarItem` correctly avoids comparing the candidate against itself (`existingItem != item`, `History.swift:460`).
- `HistoryItemDecorator.ensureThumbnailImage/ensurePreviewImage` guard against re-entrancy via the `…GenerationTask` slots (`HistoryItemDecorator.swift:90-119`) — the *spawn* is correct; only the *work inside* is mis-isolated (see `ocr-vision-on-main`).
- `clear()`/`clearAll()` use a single `context.transaction { ... }` to group deletes (`History.swift:230-242`, `262-265`) — directionally correct, see `clear-batch-transaction-not-applied-to-processpending` for the remaining gap.

---

## Grouped Findings

### 1. Ingestion (pasteboard observation + decode)

#### `pasteboard-polling-callback-heavy` — Critical
- **Location:** `Maccy/Clipboard.swift:55-64` (`start()`), `:156-215` (`checkForChangesInPasteboard`).
- **Problem:** The clipboard is observed with a repeating `Timer.scheduledTimer` whose selector is `@MainActor @objc checkForChangesInPasteboard`. On every change, the entire ingest pipeline (type read → `contents(from:)` → `HistoryItem(contents:)` → `generateTitle()` → `onNewCopyHooks.forEach`) runs **synchronously on the main thread**, before control returns to the run loop. There is no `Task.detached`, no actor hop, no `DispatchQueue.global()`.
- **Evidence:**
  ```swift
  // Clipboard.swift:55-64
  func start() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(
      timeInterval: max(0.1, Defaults[.clipboardCheckInterval]),
      target: self, selector: #selector(checkForChangesInPasteboard),
      userInfo: nil, repeats: true
    )
  }
  // Clipboard.swift:156-215 (excerpt)
  @objc @MainActor
  func checkForChangesInPasteboard() {
    ...
    pasteboard.pasteboardItems?.forEach({ item in itemContents += contents(from: item) })
    ...
    let historyItem = HistoryItem(contents: itemContents)
    historyItem.title = historyItem.generateTitle()
    onNewCopyHooks.forEach({ $0(historyItem) })   // → History.shared.add → Storage.context.save on main
  }
  ```
  Call path: `Timer fire → checkForChangesInPasteboard → contents(from:) (Clipboard.swift:219) → richText (316) + shouldIgnore (275) + isEmptyString (304)` → `HistoryItem.generateTitle() (HistoryItem.swift:97)` → `onNewCopyHooks → History.add (History.swift:140) → findSimilarItem (456) + insertIntoStorage (130) + delete-storm (122)` → `Storage.context.save()`.
- **Impact:** Every paste of a large image, RTF document, or long string blocks the UI for the full decode + DB-write duration. Worst case is exactly the user-visible symptom: "lag on images & large text". At a 0.1 s poll interval this can repeatedly clip the frame budget.
- **Recommendation:** Move the heavy body to a background context:
  - Introduce `Storage.shared.backgroundContext` (`container.newBackgroundContext()`), and do `contents(from:)`, regex checks, `NSAttributedString` decode, and OCR off-main; only the final `HistoryItem` insertion hops back to `@MainActor` for UI update.
  - Or wrap `Clipboard` in its own `actor PasteboardObserver` that performs `checkForChangesInPasteboard` work and `await`s the main actor only for the hook fan-out.
  - Consider modernizing the *trigger*: macOS still lacks a KVO-style notification for `NSPasteboard.changeCount`, but switching to a `Task`-based `while !Task.isCancelled { try await sleep; await check() }` on a background-priority task (instead of a main-run-loop `Timer`) keeps the wake-up off the main thread entirely.

#### `richtext-sync-decode-on-ingest` — High
- **Location:** `Maccy/Clipboard.swift:316-336`.
- **Problem:** `richText(_ item:)` constructs `NSAttributedString(rtf:)` and `NSAttributedString(html:)` synchronously. Both initWithData options are well-known main-thread heavyweights (TextKit/WebKit parsing). The 512 KiB guard (`richTextParsingLimit`) bounds *size*, not *cost*: a 200 KiB HTML blob from a webpage can still take tens of milliseconds to parse.
- **Evidence:**
  ```swift
  // Clipboard.swift:321-323
  if let attributedString = NSAttributedString(rtf: rtf, documentAttributes: nil) {
    return !attributedString.string.isEmpty
  }
  ```
  Called from `contents(from:)` (`Clipboard.swift:221`) which is itself called from `checkForChangesInPasteboard` (main).
- **Impact:** Copying rich text from Safari/Word/IDEs spikes main-thread latency on every copy. The result is only used to decide *whether to keep the rich-text flavor*; the decode is effectively thrown away.
- **Recommendation:** Either (a) defer the rich-text "is it empty?" check to the same background context that decodes the item for storage, or (b) keep only the raw RTF/HTML bytes on the pasteboard path and validate lazily when rendering. Better: cache `NSAttributedString(rtf:)` once on the background actor and reuse it for both the empty-check and any later title generation (`HistoryItemEngine.previewableTextPrefix` re-parses it again at `HistoryItemEngine.swift:171-185`).

#### `regex-shouldignore-on-ingest` — High
- **Location:** `Maccy/Clipboard.swift:275-302`.
- **Problem:** `shouldIgnore(_ item: NSPasteboardItem)` reads up to 2 000 bytes of the string flavor, then runs **every** regex in `Defaults[.ignoreRegexp]` over it (after the unsafe-pattern filter in `Search.isLikelyUnsafeRegularExpression`). The compiled regex cache (`ignoredRegexps`) helps, but the matching itself is O(regexes × string-length) on the main thread.
- **Evidence:**
  ```swift
  // Clipboard.swift:297
  if regex.numberOfMatches(in: string, range: NSRange(string.startIndex..., in: string)) > 0 {
    return true
  }
  ```
  Two call sites in `checkForChangesInPasteboard` (via `contents(from:)` at `Clipboard.swift:225` and via `shouldIgnore(Set(pasteboard.types ?? []))` indirectly).
- **Impact:** With several user-configured ignore patterns, each paste pays a regex sweep on main. Even well-formed regexes against long string flavors cost microseconds-to-milliseconds multiplied by pattern count.
- **Recommendation:** Move the entire ignore-evaluation onto the background actor proposed above. Pre-compile all patterns into a single `NSRegularExpression` array on `Defaults[.ignoreRegexp]` change (today it's lazily filled on first use).

#### `contents-multi-dataforType` — Medium
- **Location:** `Maccy/Clipboard.swift:219-239`, `:304-336`.
- **Problem:** `contents(from:)` reads `item.data(forType:)` once per enabled type, but on the same item it *also* calls `isEmptyString(item)` (one more `.string` read), `richText(item)` (`.rtf` + `.html` reads), and `shouldIgnore(item)` (another `.string` read). For a typical rich copy this is 4–6 IPC round-trips into the pasteboard server per item, all on main.
- **Evidence:**
  ```swift
  // Clipboard.swift:220-238
  var types = Set(item.types)
  if types.contains(.string) && isEmptyString(item) && !richText(item) { return [] }
  if shouldIgnore(item) { return [] }
  types = filteredTypes(types)
  return types.compactMap { type in
    let value = item.data(forType: type)   // re-read for every flavor, even ones we already fetched
    ...
  }
  ```
- **Impact:** Increased main-thread cost on every copy, especially when many types are present (file URL + RTF + HTML + string, common from browsers).
- **Recommendation:** Read each type once into a `[PasteboardType: Data]` dictionary on the background actor and pass that into the filter/decode/regex stages.

---

### 2. Loading

#### `load-no-pipeline-offload` — Critical
- **Location:** `Maccy/History.swift:106-119`.
- **Problem:** `load()` is `@MainActor func load() async throws` but does no `await` work — it is synchronous code in async clothing. On launch and on every `sortBy`/`pinTo` default change (`History.swift:76-86`), it:
  1. Fetches **all** `HistoryItem` rows with no `fetchLimit`, no `propertiesToFetch`, no `fetchBatchSize` (`FetchDescriptor<HistoryItem>()` with defaults — SwiftData will materialize every row).
  2. Sorts the entire result via `sorter.sort(results)` (`Sorter.swift:26-30` — `.sorted` chained twice).
  3. Maps every result through `HistoryItemDecorator($0)`, whose init synchronously resolves the app icon (see `decorator-init-main-decode-icon`).
  4. Calls `limitHistorySize(to:)`, which can in turn invoke `delete()` N times (see `limit-multi-save-storm`).
- **Evidence:**
  ```swift
  // History.swift:107-114
  let descriptor = FetchDescriptor<HistoryItem>()
  let results = try Storage.shared.context.fetch(descriptor)
  all = sorter.sort(results).map { HistoryItemDecorator($0) }
  items = all
  limitHistorySize(to: historySizeLimit)
  updateShortcuts();
  ```
  Triggered from `ContentView.task { try? await appState.history.load() }` (`ContentView.swift:55-57`), and re-triggered on every `sortBy`/`pinTo` change.
- **Impact:** First-launch latency scales linearly with history size; on a 1 000-row store with images this is multiple seconds of frozen UI. Re-sorting via the settings pane replays the entire cost.
- **Recommendation:**
  - Set `descriptor.fetchLimit = historySizeLimit + pinnedItems.count` and use `fetchBatchSize` (SwiftData 1.1+) / `propertiesToFetch` to avoid loading blob columns.
  - Move the fetch+sort off-main: `await` a `ModelContext`-perform block on a background context (`Storage.backgroundContext.perform { … }`) and only the final `HistoryItemDecorator` materialization (which needs `@MainActor` for `NSWorkspace`) hops back.
  - Decorate lazily — only items that scroll into view need an `ApplicationImage` resolved; today `HistoryItemDecorator.init` eagerly touches `ApplicationImageCache.shared.getImage(item:)`.

#### `decorator-init-main-decode-icon` — High
- **Location:** `Maccy/HistoryItemDecorator.swift:77-87`, `Maccy/ApplicationImageCache.swift:10-23`, `Maccy/ApplicationImage.swift:25-93`.
- **Problem:** Each `HistoryItemDecorator.init` calls `ApplicationImageCache.shared.getImage(item: item)` and stores `applicationImage`. `getImage` is cheap (cache hit), but on a *miss* the first read of `applicationImage.nsImage` (triggered by the SwiftUI body via `appIcon:` in `HistoryItemView.swift:38`) will call `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` + `NSWorkspace.shared.icon(forFile:)` on the main thread, plus install a `DispatchSource` file-system watcher (`ApplicationImage.swift:42-87`).
- **Evidence:**
  ```swift
  // HistoryItemDecorator.swift:82-83
  self.imageData = item.imageData
  self.applicationImage = ApplicationImageCache.shared.getImage(item: item)
  // ApplicationImage.swift:42-46
  if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
    let img = NSWorkspace.shared.icon(forFile: appURL.path)   // main-thread LaunchServices call
    ...
  ```
  `load()` constructs all decorators up-front (`History.swift:109`), so the icon lookup cost is paid at load time even though icons are not displayed until the popup opens.
- **Impact:** Compounds `load-no-pipeline-offload`; cold load does main-thread LaunchServices work for every distinct bundle id.
- **Recommendation:** Resolve `applicationImage.nsImage` lazily inside `HistoryItemView.onAppear` (next to `item.ensureThumbnailImage()` at `HistoryItemView.swift:49-51`), and cache misses should pre-warm on a background queue. Pre-warming the top N most-recent items' icons (per the user's "~2x faster UI response with data pre-warmed" goal) is straightforward here.

---

### 3. Insertion & De-duplication

#### `findsimilar-full-refetch` — Critical
- **Location:** `Maccy/History.swift:456-470`.
- **Problem:** `findSimilarItem(_ item:)` issues a fresh `Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())` — i.e. **the entire `HistoryItem` table including all `contents` blobs** — on **every paste**, then does an O(n) signature compare against the in-memory array. It is called from `add()` (`History.swift:149`), which is the `onNewCopy` hook registered in `AppDelegate.swift:52`.
- **Evidence:**
  ```swift
  // History.swift:457-464
  let descriptor = FetchDescriptor<HistoryItem>()
  if let all = try? Storage.shared.context.fetch(descriptor) {
    let signature = item.duplicateSignature
    for existingItem in all where existingItem != item {
      if existingItem.supersedes(signature) {   // → HistoryItemEngine.contains → ContentIndex.contains → dataLikelyEqual
        return existingItem
      }
    }
    return isModified(item)
  }
  ```
  `existingItem.supersedes(signature)` resolves the `@Relationship deleteRule: .cascade inverse: \HistoryItemContent.item` (`HistoryItem.swift:73-74`) — i.e. it lazily faults **all** of the existing item's contents per comparison. On a 500-row history this is potentially hundreds of relationship faults per paste.
- **Impact:** Every copy pays a full-table fetch + per-row relationship faulting on the main thread. This is the single largest contributor to "UI blocks right after I copy something" once the history grows past a few hundred items.
- **Recommendation:**
  - Maintain an in-memory `[Signature: HistoryItem]` index (built once in `load()` and updated on `add`/`delete`/`clear`). `HistoryItemEngine.Signature` is already `Hashable`-able by content type + fingerprint; O(1) lookup replaces O(n) compare and eliminates the re-fetch entirely.
  - Until the index exists, at least restrict the fetch with a `#Predicate` (e.g. by `lastCopiedAt` within a window) and set `propertiesToFetch` to exclude blob values when only checking signatures.
  - C++ angle: a content-addressed hash index (e.g. xxHash3 over `value`) kept in a small C++ sidecar with a stable FFI would make the dedup lookup both background-safe and trivially fast, complementing the existing `MaccyTextProcessor.fingerprint` path that already lives in C++.

#### `insert-resorts-whole-array` — High
- **Location:** `Maccy/History.swift:191-194`, `Maccy/Sorter.swift:26-49`.
- **Problem:** On each non-pinned insert, `add()` builds `all.map(\.item) + [item]` (allocating a new `n+1`-sized array) and runs `sorter.sort(...)` (two `.sorted` passes — `Sorter.swift:27-29`) purely to find the insertion index. Result is discarded except for `firstIndex(of: item)`.
- **Evidence:**
  ```swift
  // History.swift:191-194
  let sortedItems = sorter.sort(all.map(\.item) + [item])
  if let index = sortedItems.firstIndex(of: item) {
    all.insert(itemDecorator, at: index)
  }
  ```
  The same pattern repeats in `togglePin` (`History.swift:439-444`).
- **Impact:** O(n log n) work + an O(n) allocation on every copy. Visible as wasted main-thread time on large histories.
- **Recommendation:** Compute the insertion index with a single `O(log n)` binary search on `all` keyed by the active sort comparator (or, simpler, since the default sort is `lastCopiedAt >`, prepend to `all` for new items and only re-sort on `pin` changes).

#### `add-does-3-pending-changes-saves` — High
- **Location:** `Maccy/History.swift:130-201`.
- **Problem:** A single `add(item)` can invoke:
  1. `insertIntoStorage(item)` → `processPendingChanges() + save()` (`History.swift:131-136`, called at `:142` for macOS 15+).
  2. `limitHistorySize(to: historySizeLimit - 1)` → `delete()` per overflowing item, each calling `processPendingChanges() + save()` (`History.swift:275-295`).
  3. When a duplicate is found, `Storage.shared.context.delete(existingHistoryItem)` (`:168`) is followed by another `processPendingChanges + save` if the duplicate path also touched `limitHistorySize`.

  Each `processPendingChanges()` forces SwiftData to flush lazy faulting, and each `save()` is a synchronous SQLite write (typically fsync). These are serialized on the main thread.
- **Evidence:**
  ```swift
  // History.swift:131-136
  func insertIntoStorage(_ item: HistoryItem) throws {
    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
  }
  ```
- **Impact:** Per-paste DB round-trips multiply; on slow disks (sandboxed Container援) this is dozens of milliseconds of UI freeze, on top of `findsimilar-full-refetch`.
- **Recommendation:** Batch the whole `add()` into one `context.transaction { … }` with a single trailing `save()`, or move the writes to a background context and `await` once.

#### `limit-multi-save-storm` — High
- **Location:** `Maccy/History.swift:122-128`, `:275-295`.
- **Problem:** `limitHistorySize(to:)` invokes `delete` for each overflowing unpinned item (`unpinned[maxSize...].forEach(delete)`). `delete(_:)` independently calls `throttler.cancel()` + `cleanup(item)` + `withLogging` (which does *two* `fetchCount` calls — `History.swift:206-208`) + `context.delete` + `processPendingChanges()` + `save()` + `all.removeAll` + `items.removeAll` + `updateUnpinnedShortcuts()` + `Task { needsResize }`. That's ~10 main-thread operations per deleted item.
- **Evidence:**
  ```swift
  // History.swift:122-127
  private func limitHistorySize(to maxSize: Int) {
    let maxSize = max(0, maxSize)
    let unpinned = all.filter(\.isUnpinned)
    if unpinned.count > maxSize {
      unpinned[maxSize...].forEach(delete)
    }
  }
  ```
- **Impact:** If `Defaults[.size]` is reduced, or a large bulk copy occurs, deleting k items means k separate SQLite writes *and* k separate `updateUnpinnedShortcuts()` passes.
- **Recommendation:** Hoist the cleanup and shortcut refresh out of the loop; delete in one `context.transaction { ... }` and `save()` once.

---

### 4. Search

#### `search-throttle-still-runs-main` — High
- **Location:** `Maccy/History.swift:22-36`, `Maccy/Search.swift:46-161`, `Maccy/Throttler.swift:16-33`.
- **Problem:** `searchQuery.didSet` routes through `Throttler(minimumDelay: 0.2)` — which runs on `DispatchQueue.main` (`Throttler.swift:11`). The throttled block calls `search.search(string:within: all)` (full linear scan of all decorators), then `updateItems(...)` which runs `highlight()` per result, plus `updateUnpinnedShortcuts()`. None of this leaves the main thread.
- **Evidence:**
  ```swift
  // History.swift:22-36
  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        updateItems(search.search(string: searchQuery, within: all))
        ...
        AppState.shared.popup.needsResize = true
      }
    }
  }
  // Search.swift:63-70 (representative)
  private func fuzzySearch(string: String, within: [Searchable]) -> [SearchResult] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [SearchResult] = within.compactMap { ... }
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults
  }
  ```
- **Impact:** Typing in the search field stutters on large histories, exactly the second user-reported symptom ("slow UI response"). Fuzzy mode is O(n × query-length × title-length) on every keystroke.
- **Recommendation:**
  - Run the search on a background priority `Task`/actor and apply results to `items` via a single `@MainActor` hop.
  - Pre-build a per-item title index (or, in C++, a trigram/roaring-bitmap index over titles) and `await` lookups.
  - Use a real debounce (trailing edge) plus cancellation of the in-flight search when a new keystroke arrives — `Throttler.cancel()` only cancels the not-yet-fired work item, not a running scan.

#### `highlight-rebuild-per-keystroke` — Medium
- **Location:** `Maccy/HistoryItemDecorator.swift:191-216`, `Maccy/History.swift:480-489`.
- **Problem:** `updateItems` re-runs `item.highlight(searchQuery, result.ranges)` for every visible search result. `highlight` allocates a fresh `AttributedString(title.shortened(to: 500))`, walks every range, and applies per-range `AttributedString` mutations — non-trivial with many matches.
- **Evidence:**
  ```swift
  // HistoryItemDecorator.swift:197-216
  var attributedString = AttributedString(title.shortened(to: 500))
  for range in ranges {
    if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
       let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
      switch Defaults[.highlightMatch] { ... }
    }
  }
  ```
- **Impact:** Repeated allocations and `AttributedString` index resolution per keystroke. Sub-millisecond each, but multiplied by visible items × keystrokes.
- **Recommendation:** Cache `attributedTitle` keyed by `(query, ranges)`; invalidate only on title or query change. Or, more simply, build the highlighted string once when search results arrive (it already is) and stop re-highlighting items whose ranges haven't changed (today `updateItems` re-runs for the whole result list).

---

### 5. Rendering / Resize churn

#### `ondoublecloselocation-resize-task` — Medium
- **Location:** `Maccy/History.swift:33, 117, 198, 247, 271, 293`; `Maccy/Popup.swift:40, 107-111`; `Maccy/Views/HistoryListView.swift:130-142`.
- **Problem:** Six distinct sites set `popup.needsResize = true`. The actual resize is performed by a SwiftUI `Color.clear.task(id: appState.popup.needsResize) { try? await Task.sleep(.milliseconds(10)); if needsResize { popup.resize(...) } }`. This is a hand-rolled debounce using a 10 ms `Task.sleep`, re-keyed on every boolean flip.
- **Evidence:**
  ```swift
  // HistoryListView.swift:130-141
  .background {
    GeometryReader { geo in
      Color.clear
        .task(id: appState.popup.needsResize) {
          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }
          if appState.popup.needsResize { appState.popup.resize(height: geo.size.height) }
        }
    }
  }
  ```
  `popup.resize` (`Popup.swift:107-111`) computes a new height and calls `panel.verticallyResize(to:)` — itself triggering AppKit layout.
- **Impact:** Each insert/delete/clear/pin/search toggle fires the task; if the boolean flips twice within 10 ms the task cancels and restarts, producing flicker on rapid operations. The `Bool` "needs resize" can also be coalesced away by SwiftUI before the sleep finishes, missing legitimate resizes.
- **Recommendation:** Replace with `@Observable` flow that explicitly debounces (e.g. a `Task` cancelled and restarted on each geometry change) and emits a `popup.targetHeight: CGFloat?` rather than a boolean flag.

#### `cleanup-recaches-main` — Medium
- **Location:** `Maccy/HistoryItemDecorator.swift:137-147`, `Maccy/History.swift:96-102`.
- **Problem:** On every `imageMaxHeight` default change, `History.swift:96-102` iterates **all** `items` and calls `item.cleanupImages()` — which cancels tasks and calls `recache()` on `thumbnailImage`, `previewImage`, and `decodedImage`. `recache()` drops the bitmap representations, forcing a fresh `NSImage(data:)` decode next time the item is displayed (see `image()` at `HistoryItemDecorator.swift:178-189`).
- **Evidence:**
  ```swift
  // HistoryItemDecorator.swift:138-147
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImage?.recache()
    previewImage?.recache()
    decodedImage?.recache()
    thumbnailImage = nil; previewImage = nil; decodedImage = nil
  }
  // History.swift:96-102
  Task { @MainActor in
    for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
      for item in items { item.cleanupImages() }
    }
  }
  ```
- **Impact:** Changing the image-height preference is O(items) main-thread work, and re-decoding happens lazily — UI jank when scrolling afterwards.
- **Recommendation:** Only invalidate items currently displayed (visible window), or background the recache and re-decode lazily with `Task.detached`.

#### `updateunpinned-double-pass` — Medium
- **Location:** `Maccy/History.swift:516-527`.
- **Problem:** `updateUnpinnedShortcuts()` first clears `shortcuts = []` for every visible unpinned item, then assigns `KeyShortcut.create(...)` to the first 9. The clear pass causes a SwiftUI observation notification per item, even for items whose shortcut was already empty.
- **Evidence:**
  ```swift
  // History.swift:517-526
  let visibleUnpinnedItems = unpinnedItems.filter(\.isVisible)
  for item in visibleUnpinnedItems { item.shortcuts = [] }
  var index = 1
  for item in visibleUnpinnedItems.prefix(9) {
    item.shortcuts = KeyShortcut.create(character: String(index)); index += 1
  }
  ```
  Called from `updateItems` (every search keystroke), `refreshVisibleItems` (every insert), `delete`, `togglePin`, `updateShortcuts`.
- **Impact:** Per-keystroke churn on the observation graph for items whose shortcut didn't actually change.
- **Recommendation:** Diff against the current assignment and only set `shortcuts` when the new value differs.

---

### 6. Threading / Isolation model

#### `no-background-modelcontext` — High
- **Location:** `Maccy/Storage.swift:5-10`.
- **Problem:** `Storage` is `@MainActor` and exposes only `container.mainContext`. There is no `newBackgroundContext`, no `ModelActor`, and no `perform {}` boundary anywhere in the codebase (grep confirms: only `mainContext` is referenced outside `PinsSettingsPane.swift:116`). All `context.fetch/insert/delete/processPendingChanges/save/transaction/fetchCount` calls therefore run on the main thread by construction. This single architectural fact underpins most of the other criticals.
- **Evidence:**
  ```swift
  // Storage.swift:5-10
  @MainActor
  class Storage {
    static let shared = Storage()
    var container: ModelContainer
    var context: ModelContext { container.mainContext }
  ```
- **Impact:** Any growth in history size directly grows main-thread latency. Impossible to fix UI blocking for images/large text without addressing this.
- **Recommendation:**
  - Introduce `Storage.backgroundContext: ModelContext` (`container.newBackgroundContext()`) and a `ModelActor`-conforming type (`HistoryStore`) that owns it.
  - Migrate reads (`load`, `findSimilarItem`, `fetchCount` in `withLogging`) and writes (`insert/delete/save/clear`) to `await historyStore.perform { … }`.
  - Pre-warm the background context during `AppDelegate.applicationWillFinishLaunching` so the first paste doesn't pay context-creation cost.
  - This is the foundation for both the Swift 6 migration and the C++ sidecar; do it first.

#### `historyitem-unchecked-sendable` — Medium
- **Location:** `Maccy/HistoryItemDecorator.swift:8`.
- **Problem:** `class HistoryItemDecorator: ..., @unchecked Sendable` is declared Sendable-by-fiat despite having mutable `var title`, `attributedTitle`, `isVisible`, `selectionIndex`, `shortcuts`, `previewImage`, `thumbnailImage`, plus `@MainActor`-isolated methods. The `Sendable` conformance is unsound: nothing prevents mutation from a non-main context once a `Task` captures the decorator.
- **Evidence:**
  ```swift
  // HistoryItemDecorator.swift:7-8
  @Observable
  class HistoryItemDecorator: Identifiable, Hashable, HasVisibility, @unchecked Sendable {
  ```
- **Impact:** Hides data-race risks; under Swift 6 strict concurrency this declaration would either be rejected or silently permit races.
- **Recommendation:** Drop `@unchecked Sendable` and make the class truly `@MainActor`-isolated (it effectively already is). Pass immutable snapshots across actor boundaries instead.

#### `appdelegate-unchecked-sendable` — Medium
- **Location:** `Maccy/AppDelegate.swift:6`.
- **Problem:** `class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable` declares `var panel: FloatingPanel<ContentView>!` (mutable, non-Sendable). The conformance papers over the actual non-Sendability of the type.
- **Evidence:**
  ```swift
  // AppDelegate.swift:6-7
  class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    var panel: FloatingPanel<ContentView>!
  ```
- **Impact:** Same as above; under Swift 6 the unchecked conformance is the wrong escape hatch.
- **Recommendation:** Mark `AppDelegate` `@MainActor` (AppKit delegates already are, effectively) and remove the `@unchecked Sendable`.

#### `combine-crossing-defaults` — Medium
- **Location:** `Maccy/AppDelegate.swift:55-101`, `Maccy/History.swift:69-103`.
- **Problem:** ~12 `Task { for await _ in Defaults.updates(...) }` loops are spawned at startup, all inheriting `@MainActor` isolation implicitly (via the enclosing `@MainActor` class for `AppDelegate`, and the explicit `Task { @MainActor in … }` in `History`). They cooperatively share the main actor with no priority hints. They're benign today, but each `Defaults.updates` emission is processed synchronously on main.
- **Evidence:**
  ```swift
  // History.swift:88-94
  Task { @MainActor in
    for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
      for item in items {
        updateTitle(item: item, title: item.item.generateTitle())  // re-runs generateTitle over all items on main
      }
    }
  }
  ```
  The `showSpecialSymbols` branch re-runs `generateTitle()` for **every** item on every preference toggle.
- **Impact:** Changing the "show special symbols" preference blocks the UI proportional to history size.
- **Recommendation:** Move the title regeneration onto the background store actor and apply results via a single main-actor batch.

#### `synctrack-dispatch-main-reentry` — Medium
- **Location:** `Maccy/HistoryItemDecorator.swift:227-263`.
- **Problem:** `synchronizeItemPin` and `synchronizeItemTitle` use `withObservationTracking { } onChange: { DispatchQueue.main.async { … } }` to re-arm themselves recursively. The re-arming hop goes through `DispatchQueue.main.async`, which is decoupled from the `@MainActor` priority system. If the decorator has been `invalidate()`d, the closure still captures `self` weakly and re-checks `isInvalidated`, but there's a window between the change and the dispatch where the decorator is dead.
- **Evidence:**
  ```swift
  // HistoryItemDecorator.swift:247-263
  private func synchronizeItemTitle() {
    guard !isInvalidated else { return }
    _ = withObservationTracking { item.title } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isInvalidated else { return }
        self.title = self.item.title
        self.synchronizeItemTitle()
      }
    }
  }
  ```
- **Impact:** Latent correctness window; also every title change in SwiftData triggers a `DispatchQueue.main.async` per live decorator (since `load()` builds all of them up front).
- **Recommendation:** Convert to `@Observable`'s native recomputation, or use a `Task { @MainActor in … }` with cooperative cancellation.

#### `timer-no-tolerance-mode` — Medium
- **Location:** `Maccy/Clipboard.swift:55-64`.
- **Problem:** `Timer.scheduledTimer(timeInterval:target:selector:userInfo:repeats:)` is scheduled on the current run loop in `.default` mode (no `add(to:forMode:)` call). It has no `tolerance` set, so macOS cannot coalesce it with other timers, hurting energy use. The default mode also means the timer pauses during modal tracking (e.g. menu tracking, drag) — copies made during those windows are missed until the modal ends.
- **Evidence:** No `timer.tolerance = …` and no explicit `RunLoop.main.add(timer, forMode: .common)`.
- **Impact:** Missed/late paste detection during modal interaction; minor battery drain.
- **Recommendation:** Set `timer.tolerance = max(0.05, interval * 0.1)` and add to `.common` mode. Better: switch to a `Task`-based loop on a background actor as discussed above.

---

### 7. Minor / latent

#### `storage-recover-task-modal` — Low
- **Location:** `Maccy/Storage.swift:37-61`.
- **Problem:** `recoverContainer` synchronously creates a new `ModelContainer`, then in the `catch` path it `Task { @MainActor in NSAlert().runModal() }` *and then immediately* returns an in-memory container. The modal runs asynchronously while the app continues with the in-memory store; the alert isn't truly gating anything.
- **Recommendation:** Either block on the alert (acceptable at startup) or surface the failure via a state flag the UI observes.

#### `pressedshortcutitem-each-keystroke` — Low
- **Location:** `Maccy/History.swift:38-53`.
- **Problem:** `pressedShortcutItem` is a computed property that calls `Sauce.shared.key(for:)` and `items.first { … }` on every read. Read from `Popup.handleRepeatedHotKeyDown` (`Popup.swift:195`) on each cycle key press.
- **Recommendation:** Cache the result for the duration of a key event.

#### `applicationimage-dispatchsource-leak-risk` — Low
- **Location:** `Maccy/ApplicationImage.swift:42-87`.
- **Problem:** On every cache miss, `nsImage` opens the app bundle with `O_EVTONLY`, creates a `DispatchSource.makeFileSystemObjectSource(... queue: .global())`, and calls `print(...)` for both error and event branches. The prints are debug noise left in production paths. The `eventSource` is cancelled on `deinit` and on `.delete`, but the source is created with no `.weak` capture, only `[weak self]` in the handler — fine, but the cancellation ordering on `invalidate()` (decorator) doesn't reach `ApplicationImage`, which lives in the cache.
- **Recommendation:** Remove `print` statements; consider routing the icon refresh through the same background-actor proposal so the DispatchSource isn't installed from main.

#### `notifier-uses-unowned-queue` — Low
- **Location:** `Maccy/Notifier.swift:16-31`.
- **Problem:** `UNUserNotificationCenter` callbacks (`requestAuthorization`, `getNotificationSettings`, `add`) execute on background queues. `hasRequestedAuthorization` is mutated from `authorize()` without synchronization — `authorize()` is called from `notify()` (`Notifier.swift:40`) which is reachable from `Task { Notifier.notify(...) }` in `History.swift:171` and `Clipboard.swift:111`.
- **Recommendation:** Either pin `Notifier` to `@MainActor` or guard `hasRequestedAuthorization` with a lock.

#### `string-shortened-alloc-per-render` — Low
- **Location:** `Maccy/HistoryItemDecorator.swift:197`, `Maccy/AppState.swift:28-33`.
- **Problem:** `AttributedString(title.shortened(to: 500))` allocates a substring + AttributedString on every `highlight()` call; `menuIconText` recomputes on every observation read by computing `unpinnedItems.first?.text.shortened(to: 100).trimmingCharacters(...)`.
- **Recommendation:** Cache both.

#### `clear-batch-transaction-not-applied-to-processpending` — Low
- **Location:** `Maccy/History.swift:230-242`.
- **Problem:** `clear()` wraps the bulk delete in `context.transaction { … }`, but then calls `processPendingChanges()` + `save()` outside the transaction. The pattern is half-batched — better than `delete()`'s per-item saves, but still one extra flush.
- **Recommendation:** Move `processPendingChanges + save` inside the transaction.

#### `throttler-no-coalesce-trailing` — Low
- **Location:** `Maccy/Throttler.swift:16-33`.
- **Problem:** Every call cancels the pending work item and reschedules. With rapid typing, the final keystroke always waits the full `minimumDelay` (0.2 s) before results appear; there is no leading-edge fire. The implementation is "debounce", mislabeled "throttle".
- **Recommendation:** Either rename to `Debouncer`, or implement leading+trailing so the first keystroke shows results immediately and subsequent ones are coalesced.

---

## Cross-cutting implications

**Swift 6 migration:**
- The codebase is at `SWIFT_VERSION = 5.0` with no `SWIFT_STRICT_CONCURRENCY` flag. Enabling minimal mode would surface: `@unchecked Sendable` on `AppDelegate` and `HistoryItemDecorator` (would need justification), the implicit main-actor inheritance from `@MainActor class Storage` into every `Storage.shared.*` call site, and the `DispatchQueue.main.async`-based re-arming loops in `HistoryItemDecorator`.
- A background `ModelContext` introduced via a `ModelActor`-conforming `HistoryStore` is the natural target for `nonisolated`/`Sendable` boundaries and makes most of the criticals above trivially safe.

**C++ sidecar opportunity:**
- `MaccyTextProcessor` already provides `validUTF8PrefixLength` and `fingerprint` (`ClipboardDataProcessor.swift:15, 53, 67`) — extending the same module with:
  - A content-addressed duplicate index (hash → HistoryItem id) replacing `findsimilar-full-refetch`.
  - A title trigram/roaring-bitmap index for search.
  - Synchronous OCR pre-classification (image format + size heuristics) so the Vision call only fires for plausible images.
- All of these are CPU-bound, branchy, and trivially `Sendable` — ideal for a C++ worker invoked from the background actor.

**Pre-warming for "~2x faster UI response":**
- The cheapest pre-warms, ranked: (1) decorate only the first viewport-full of items in `load()` and decorate the rest lazily in `HistoryItemView.onAppear`; (2) resolve `ApplicationImage.nsImage` for the top-N items on a background queue right after `load()`; (3) eagerly call `ensureThumbnailImage()` for the first ~10 visible items so the popup opens with thumbnails already decoded.

# Memory & Caching Audit — Maccy

**Date:** 2026-06-14
**Scope:** In-memory item realization, image bitmaps (full-res / decoded / preview / thumbnail), per-app icon cache, regex cache, color cache, session log, settings arrays, SwiftData faulting/realization, retain cycles, autoreleasepool usage, SwiftUI retention, memory-warning handling.
**Method:** Direct read of every cited file:line at repo root `/lzcapp/document/Projects/Maccy`. Snippets are quoted verbatim. Codebase-wide greps back the absence claims (no `NSCache`, no `autoreleasepool`, no `didReceiveMemoryWarning`, no `purge`).
**Verified baseline:**
- `Maccy/Storage.swift:5,10` — `@MainActor class Storage`, only `container.mainContext`. No background context.
- `Maccy/Observables/History.swift:16,67,106` — `items` AND `all` are `[HistoryItemDecorator]`; `load()` fetches + sorts + decorates ALL rows.
- `Maccy/Observables/HistoryItemDecorator.swift:13,46-52` — `previewImageSize` = full `visibleFrame` (fallback 2048×1536); each decorator may retain `previewImage`, `thumbnailImage`, `applicationImage`, `imageData`, `decodedImage`, `textPreviewCache`.
- `Maccy/ApplicationImageCache.swift:8` — `private var cache: [String: ApplicationImage] = [:]`, unbounded.
- `Maccy/Models/HistoryItemContent.swift:7-12` — `maxValueSize` bounds a single BLOB; there is NO byte budget on total memory.
- `Maccy/Extensions/Defaults.Keys+Names.swift:66` — `Defaults[.size]` default 200, max 999 (see `StorageSettingsPane.swift:69`). Bounds COUNT only.
- Grep tallies (whole `Maccy/`): **0** `NSCache`, **0** `autoreleasepool`, **0** `didReceiveMemoryWarning` / `applicationDidReceiveMemoryWarning`, **0** `purge*.removeAllObjects`, **0** `totalCostLimit` / `countLimit`.

Build is `SWIFT_VERSION = 5.0`, **no** `SWIFT_STRICT_CONCURRENCY` flag — no Swift 6 migration work has begun.

---

## Summary Table

| ID | Severity | Location | One-line problem |
|---|---|---|---|
| `img-fullres-dup-storage` | **Critical** | `HistoryItemDecorator.swift:50,82` + `HistoryItem.swift:175-183` | Full-resolution image `Data` is copied from SwiftData into a second `let imageData` on every decorator — image bytes live twice per item. |
| `img-decoded-nsimage-retained` | **Critical** | `HistoryItemDecorator.swift:51,178-189` | Once any thumbnail/preview is requested, the FULL-RES decoded `NSImage` (CG bitmap) is cached on the decorator forever — multiple full-size bitmaps per image item. |
| `img-preview-fullscreen-bitmap` | **Critical** | `HistoryItemDecorator.swift:13,158-165,105-119` | `previewImage` is sized to the entire popup screen `visibleFrame` (retina ≈ 16 Mpx → ~50–60 MiB per image); retained per image item until `invalidate()`. |
| `all-realized-decorators` | **Critical** | `History.swift:16,67,106-119` | `load()` realizes + decorates ALL persisted rows (up to 999) into memory at once; no paging/faulting/windowing. |
| `img-no-evict-on-scrollout` | **High** | `HistoryItemView.swift:49-51`, `HistoryItemDecorator.swift:90-119,137-147` | `LazyVStack` lazily builds views but **never** releases decorator-side `decodedImage`/`previewImage`/`thumbnailImage` on scroll-out; only `invalidate()` (delete/clear) frees them. |
| `appicon-cache-unbounded` | **High** | `ApplicationImageCache.swift:8-23`, `ApplicationImage.swift:14,55-87` | `[String: ApplicationImage]` has no eviction; each entry keeps an `NSImage` and a live `DispatchSourceFileSystemObject` (open fd) per bundle id forever. |
| `no-memwarning-handling` | **High** | `AppDelegate.swift` (no override), repo-wide grep | `applicationDidReceiveMemoryWarning` is not implemented; no path purges `decodedImage` / `previewImage` under pressure. |
| `sessionlog-keeps-historyitem` | **High** | `History.swift:60-61,179,227,260,289` | `sessionLog: [Int: HistoryItem]` retains `HistoryItem` managed objects (and their `contents` blobs) for every paste since launch; only cleared on `clear()`/`clearAll()`/`delete()`. |
| `regex-cache-unbounded` | **Medium** | `Clipboard.swift:13,282-300` | `ignoredRegexps: [String: NSRegularExpression]` accumulates one compiled regex per distinct user pattern and never evicts. |
| `title-duplicated` | **Medium** | `HistoryItemDecorator.swift:18,81`, `HistoryItem.swift:71`, `History.swift:158,511-514` | Title string lives on BOTH `decorator.title` and `item.title`; pin/merge paths copy it back and forth. |
| `textpreview-cache-per-item` | **Medium** | `HistoryItemDecorator.swift:52-63`, `HistoryItem.swift:10` | Up to 10 000-char `String` cached per decorator — ~20 KiB each × N items, computed lazily but never released. |
| `contents-array-realized` | **Medium** | `HistoryItem.swift:73-74,244-258`, `HistoryItemContent.swift:14-18` | `@Relationship` `contents` eagerly realizes all `HistoryItemContent` rows (all BLOBs) on first access of any getter; no lazy/faulted access. |
| `img-sizeimages-both-bitmaps` | **Medium** | `HistoryItemDecorator.swift:167-175` | `sizeImages()` materializes BOTH preview (≈50 MiB) and thumbnail at once. Currently uncalled (dead code) — a latent footgun if anyone wires it up. |
| `cleanup-recache-only` | **Medium** | `HistoryItemDecorator.swift:137-147` | `cleanupImages()` calls `recache()` then `nil`s the image — but `recache()` on `NSImage` only drops cached representations; the `imageData` `Data` and the underlying SwiftData BLOB remain. Cleanup is partial. |
| `colorimage-rebuild-per-render` | **Medium** | `ColorImage.swift:4-16`, `HistoryItemView.swift:40`, `PasteStackItemView.swift:30` | `ColorImage.from(item.title)` builds a fresh 12×12 NSImage via `lockFocus`/`unlockFocus` on EVERY render of every non-image row; no cache. |
| `appimage-fd-leak-on-uninstall` | **Medium** | `ApplicationImage.swift:14,48-87` | The `DispatchSource` fd handler is created on cache miss but if `ApplicationImage` is never evicted (cache is unbounded), the entry (and its event handler closure capturing `appURL`) lives for the process even if the app icon is never used again. |
| `defaults-arrays-grow` | **Low** | `Defaults.Keys+Names.swift:35-46` | `ignoredApps`, `ignoredPasteboardTypes`, `ignoreRegexp` are user-extensible arrays/sets; no UI limit. Bounded in practice but unbounded in code. |
| `no-autoreleasepool-loops` | **Low** | `History.swift:106-119,221-266` | Tight loops in `load()`, `clear()`, `clearAll()` build `NSImage`/`NSAttributedString`/`AttributedString` without `autoreleasepool`; transient AppKit allocations pile up in the current main-thread pool until the run loop spins. |
| `add-contents-copies-on-dedup` | **Low** | `History.swift:151-153` | On duplicate-merge, `item.contents = existingHistoryItem.contents.map { HistoryItemContent(type: $0.type, value: $0.value) }` deep-copies each BLOB `Data` (CoW ref + new row) — brief double-buffering of large blobs on main. |
| `decorator-title-set-after-merge` | **Low** | `History.swift:158,511-514`, `HistoryItemDecorator.swift:247-263` | `synchronizeItemTitle` re-arms via `DispatchQueue.main.async`; combined with the eager `self.title = item.title` in `init`, the title can be set three times for a single change. Minor extra allocations. |
| `applicationimage-debug-prints` | **Low** | `ApplicationImage.swift:51-53,73-79` | `print(...)` debug logging left in production hot path on the icon-resolve branch; also signals that the file-system-event path was never audited. |
| `applicationimage-cache-not-shared-by-macmenu` | **Low** | `AppState.swift:28-32`, `HistoryItemView.swift:40` | `menuIconText` and the menu bar use a *separate* `String.shortened(to:)` allocation path from the in-list rendering; multiple parallel string copies of the most recent item exist (menu bar title, decorator.title, item.title, attributedTitle). |
| `strong-self-closure-throttler` | **Low** | `History.swift:22-36` | `searchQuery.didSet` captures `[self]` inside `throttler.throttle { ... }`; safe because `History` is a singleton, but worth noting under Swift 6 (would need explicit isolation). |
| `closure-captures-self-search` | **Low** | `History.swift:25,480-498` | `search.search(string:within: all)` and `updateItems(_:)` are reached through a `@MainActor` closure that implicitly captures `self`; same Swift 6 caveat. |
| `no-thumbnail-disk-cache` | **Low** | `HistoryItemDecorator.swift:137-156` | Thumbnails are recomputed from the full-res blob every time `cleanupImages()` runs (e.g. on every `imageMaxHeight` change); no disk cache for small downscaled bitmaps. |
| `pasteStack-retains-decorators` | **Low** | `History.swift:17,351-355`, `PasteStack.swift` (refs) | `pasteStack: PasteStack?` holds the user-selected decorators until interrupt/drain; minor in normal use but adds a second retention path for visible items. |

**Correct code (do not "fix"):**
- `ApplicationImageCache.getImage(item:)` correctly dedupes by bundle id (`ApplicationImageCache.swift:10-23`) and reuses the same `ApplicationImage` instance across decorators — reference-shared, not copied.
- `LazyVStack` is used in `MultipleSelectionListView.swift:9` so SwiftUI view bodies (not the underlying decorators) are built lazily.
- `ApplicationImage.deinit` cancels its `DispatchSource` (`ApplicationImage.swift:21-23`) — the fd would leak if the cache were bounded and evicted; the cancellation path is correct.
- `HistoryItemContent.maxValueSize` caps any single BLOB before storage (`HistoryItemContent.swift:7-12`).
- The image generation `Task`s use `[weak self, image]` captures (`HistoryItemDecorator.swift:100,116`) — no retain cycle on the decorator through the task.
- `synchronizeItemPin`/`synchronizeItemTitle` use `[weak self]` in their `DispatchQueue.main.async` re-arm (`HistoryItemDecorator.swift:235,255`) — correctly avoids a strong cycle.
- `limitHistorySize(to:)` (`History.swift:121-128`) bounds COUNT so the in-memory array does not grow without limit beyond the user-set history size.

---

## Image Memory

### `img-fullres-dup-storage` — Full-res image `Data` is duplicated per item
**Severity:** Critical
**Location:** `Maccy/Observables/HistoryItemDecorator.swift:50,82`; `Maccy/Models/HistoryItem.swift:175-183`.
**Problem:** The decorator copies the full image bytes out of the SwiftData row into a second `private let imageData: Data?` on `init`. The same bytes are already retained by the SwiftData `HistoryItem.contents[...].value` relationship.

**Evidence (call path):**
```swift
// HistoryItemDecorator.swift:50,77-87
private let imageData: Data?
@MainActor
init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
  ...
  self.imageData = item.imageData            // ← second copy
  ...
}
// HistoryItem.swift:175-183
var imageData: Data? {
  var data: Data?
  data = contentData([.tiff, .png, .jpeg, .heic])   // ← reads contents[].value
  ...
}
```
`item.imageData` returns the `Data` stored on `HistoryItemContent.value` (the persistent row). SwiftData returns a value type `Data`; assigning it to `let imageData` may CoW-share the underlying buffer for a pure read, BUT the moment any code path mutates either side (or once SwiftData re-faults), the buffer splits. The safer reading — and the explicit intent of the copy — is that the decorator wants its own stable snapshot.
**Impact:** Worst case the *same* bytes are charged twice to RSS. With `maxValueSize` defaulting to 10 MiB (configurable up to 1024 MiB; `Defaults.Keys+Names.swift:24-27`) and N image items, this is **up to 2 × 10 MiB × N_image**. For 100 image items at 10 MiB → ~2 GiB retained just on the decorator snapshot.
**Recommendation:** Drop `let imageData` and read `item.imageData` lazily on demand (SwiftData caches the realized object on the main context anyway). If a stable snapshot is required for off-main decoding, keep it as a `@ObservationIgnored private var imageData: Data?` that is `nil`-able on memory pressure and re-fetched on demand.

---

### `img-decoded-nsimage-retained` — Full-res decoded NSImage retained
**Severity:** Critical
**Location:** `Maccy/Observables/HistoryItemDecorator.swift:51,177-189`.
**Problem:** The first call to `image()` decodes the full-res bytes into an `NSImage` and caches it on `private var decodedImage: NSImage?` indefinitely. `NSImage(data:)` for a raster format produces an `NSBitmapImageRep` (or `CGImage`-backed rep) at the *source* pixel dimensions, not the display size.

**Evidence:**
```swift
// HistoryItemDecorator.swift:177-189
@MainActor
private func image() -> NSImage? {
  if let decodedImage {
    return decodedImage
  }
  guard let imageData, let image = NSImage(data: imageData) else {
    return nil
  }
  decodedImage = image            // ← full-res decoded bitmap cached forever
  return image
}
```
`decodedImage` is only released by `cleanupImages()` (called from `invalidate()` on delete/clear, or on `imageMaxHeight` change). For an item that stays in history, `decodedImage` is leaked until process exit.
**Impact:** A single 12 MP iPhone photo (~4032×3024) decodes to ~49 MiB of RGBA bitmap (4032 × 3024 × 4 bytes). With 100 image items retained that have had any thumbnail/preview generated → ~4.8 GiB of decoded bitmaps that the user never looks at again. This is independent of (and in addition to) `previewImage`/`thumbnailImage` below.
**Recommendation:**
- Treat `decodedImage` as a *transient* decode cache: drop it as soon as `thumbnailImage` and `previewImage` are produced (the resized output is what the UI uses).
- Or use `NSCache` keyed by `item.id` with `countLimit` and `totalCostLimit`, and let the OS evict under pressure.
- Implement `applicationDidReceiveMemoryWarning` in `AppDelegate` to call a `History.shared.purgeTransientImages()` that nils out `decodedImage` (and optionally `previewImage`) for non-visible items.

---

### `img-preview-fullscreen-bitmap` — Preview bitmap is screen-sized (retina)
**Severity:** Critical
**Location:** `Maccy/Observables/HistoryItemDecorator.swift:13,105-119,158-165`; `PreviewItemView.swift:17-24`.
**Problem:** `previewImage` is generated at `HistoryItemDecorator.previewImageSize` = the popup screen's full `visibleFrame.size`, fallback **2048×1536**. On a retina display this backing store is `(width × scaleFactor) × (height × scaleFactor) × 4 bytes`.

**Evidence:**
```swift
// HistoryItemDecorator.swift:13
static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
// :158-165
@MainActor
private func generatePreviewImage(from image: NSImage) {
  guard !isInvalidated else { return }
  previewImage = image.resized(to: HistoryItemDecorator.previewImageSize)   // ← full-screen bitmap
}
```
The popup is a small overlay (default `NSSize(width: 450, height: 800)`, `Defaults.Keys+Names.swift:69`), and the preview slide-out defaults to `previewWidth = 400` (`Defaults.Keys+Names.swift:72`). The image is therefore decoded and *kept* at far larger pixel dimensions than the on-screen footprint. `resized(to:)` (`NSImage+Resized.swift:5-27`) returns a drawing closure-backed `NSImage`; once drawn into an `Image(nsImage:)` SwiftUI caches the rendered bitmap at full backing-store size.
**Impact:** 2048×1536 RGBA = ~12 MiB at 1×; at 2× retina = ~50 MiB; at 3× (Pro Display XDR) = ~113 MiB — per image item that has been previewed. `ensurePreviewImage()` is called from `PreviewItemView` via `asyncGetPreviewImage()` (`HistoryItemDecorator.swift:121-129`) each time the preview slide-out opens for an item; once materialized, it is never released short of `invalidate()`.
**Recommendation:**
- Cap `previewImageSize` at the **actual** slide-out content rect (`previewWidth × popup.height` × screen scale), not the whole `visibleFrame`.
- Downsample at ingest using `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = previewWidth * scale`; this avoids ever decoding the full-res bitmap on the main thread.
- Release `previewImage` when the preview slide-out switches to a different item (the preview only ever shows one item at a time).

---

## In-Memory Item Realization

### `all-realized-decorators` — All history rows realized + decorated at load
**Severity:** Critical
**Location:** `Maccy/Observables/History.swift:16,67,106-119`.
**Problem:** `load()` does an unbounded `FetchDescriptor<HistoryItem>()` and immediately constructs a `HistoryItemDecorator` for *every* row.

**Evidence:**
```swift
// History.swift:105-119
@MainActor
func load() async throws {
  let descriptor = FetchDescriptor<HistoryItem>()
  let results = try Storage.shared.context.fetch(descriptor)
  all = sorter.sort(results).map { HistoryItemDecorator($0) }   // ← every row decorated
  items = all
  limitHistorySize(to: historySizeLimit)
  ...
}
```
Each decorator's `init` (`HistoryItemDecorator.swift:77-87`) eagerly:
1. Snapshots `self.imageData = item.imageData` (full-res bytes — see `img-fullres-dup-storage`),
2. Resolves `self.applicationImage = ApplicationImageCache.shared.getImage(item: item)` (which calls `NSWorkspace.urlForApplication` synchronously on main),
3. Arms two `withObservationTracking` recursive observers.

`lazyVStack` lazily builds *views*, not decorators; the decorator array is fully realized regardless of which row is on screen.
**Impact:** At `Defaults[.size] = 999` with even 10% image items at 3 MiB each: ~3 GiB of `imageData` snapshots materialized at launch, before the user has interacted with anything.
**Recommendation:**
- Add `FetchDescriptor.fetchLimit` / paging and only realize decorators for the visible window plus a small overscan.
- Or adopt a "shell + detail" pattern: keep a lightweight array of `(id, sortKey, pin, titlePreview)` and instantiate the full `HistoryItemDecorator` lazily for visible rows.
- Move sort off-main onto a `ModelContext` from `newBackgroundContext` (see `04-data-pipeline-storage.md`).
- Consider SwiftData `fetchLimit` + `sortBy` in the descriptor so the DB does the sort, not Swift.

---

## Caches (app icon / regex / color)

### `appicon-cache-unbounded` — `ApplicationImageCache` never evicts
**Severity:** High
**Location:** `Maccy/ApplicationImageCache.swift:8-23`; `Maccy/ApplicationImage.swift:14,48-87`.
**Problem:** `cache: [String: ApplicationImage]` grows with the number of distinct bundle ids ever seen. Each `ApplicationImage`, once its icon is resolved, retains:
- `image: NSImage?` (~64×64 icon, but `NSWorkspace.icon(forFile:)` returns a 32×32 / 64×64 multipage image — a few hundred KiB),
- `eventSource: (any DispatchSourceFileSystemObject)?` — a live open file descriptor (`open(appURL.path, O_EVTONLY)`, `ApplicationImage.swift:49`) with a `setEventHandler` closure that captures `appURL`,
- `lastChecked: Date?`.

**Evidence:**
```swift
// ApplicationImageCache.swift:8-23
private var cache: [String: ApplicationImage] = [:]
func getImage(item: HistoryItem) -> ApplicationImage {
  guard let bundleIdentifier = bundleIdentifier(for: item) else { return fallback }
  if let image = cache[bundleIdentifier] { return image }
  let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
  cache[bundleIdentifier] = image
  return image
}
// ApplicationImage.swift:48-60 (the fd + source are created on icon resolution)
eventSource?.cancel()
let descriptor = open(appURL.path, O_EVTONLY)
...
let source = DispatchSource.makeFileSystemObjectSource(...)
```
There is no LRU, no `countLimit`, no eviction triggered by `applicationDidReceiveMemoryWarning`, no eviction on app removal.
**Impact:**
- Each entry holds an open fd → in the worst case (a clipboard that records items from many distinct apps over a long-running session) the per-process fd count grows without bound. macOS default soft fd limit is 256.
- Each entry retains an `NSImage`; with 100 distinct apps at ~200 KiB → ~20 MiB (not the dominant cost but it accumulates).
- The `setEventHandler` closure also captures `appURL` (a `URL` value), keeping the path string alive.
**Recommendation:**
- Switch to `NSCache<NSString, ApplicationImage>` with `countLimit` (e.g. 64) so the OS evicts under pressure. `NSCache` does not copy keys (good for `NSString` bridging) and is thread-safe (relevant under Swift 6).
- Add `applicationDidReceiveMemoryWarning` → `ApplicationImageCache.shared.cache.removeAllObjects()` (cancelling each `ApplicationImage`'s `eventSource` via `deinit`).
- Optionally bound the fd count explicitly and prefer re-resolving icons on demand over pinning them forever.

---

### `regex-cache-unbounded` — `Clipboard.ignoredRegexps` grows with user patterns
**Severity:** Medium
**Location:** `Maccy/Clipboard.swift:13,282-300`.
**Problem:** The regex cache accumulates one compiled `NSRegularExpression` per distinct user pattern in `Defaults[.ignoreRegexp]`. There is no eviction when a user removes a pattern from settings.

**Evidence:**
```swift
// Clipboard.swift:13
private var ignoredRegexps: [String: NSRegularExpression] = [:]
// :282-300
for regexp in Defaults[.ignoreRegexp] {
  ...
  if let cached = ignoredRegexps[regexp] {
    regex = cached
  } else if let compiled = try? NSRegularExpression(pattern: regexp) {
    ignoredRegexps[regexp] = compiled
    regex = compiled
  } else { continue }
  ...
}
```
When the user removes a regex from `Defaults[.ignoreRegexp]`, the corresponding dictionary entry is never deleted (the lookup is keyed on the current settings list, so it's just unused, not removed).
**Impact:** Negligible memory per regex (typically a few KiB). Real issue is staleness + the unbounded-dictionary anti-pattern.
**Recommendation:** Rebuild the cache from `Defaults[.ignoreRegexp]` whenever it changes (observe via `Defaults.updates(.ignoreRegexp)`); drop entries not in the current set. Or use `NSCache<NSString, NSRegularExpression>`.

---

### `colorimage-rebuild-per-render` — No color swatch cache
**Severity:** Medium
**Location:** `Maccy/ColorImage.swift:4-16`; `HistoryItemView.swift:40`; `PasteStackItemView.swift:30`.
**Problem:** Every render of a non-image list row calls `ColorImage.from(item.title)`, which:
1. Parses a hex string with `NSColor(hexString:)`,
2. Allocates an `NSImage(size: 12×12)`,
3. Calls `lockFocus()` / `drawSwatch` / `unlockFocus()` (each of which spins up a graphics context and a bitmap rep).

**Evidence:**
```swift
// HistoryItemView.swift:40
accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
// ColorImage.swift:10-14
let image = NSImage(size: NSSize(width: 12, height: 12))
image.lockFocus()
color.drawSwatch(in: NSRect(x: 0, y: 0, width: 12, height: 12))
image.unlockFocus()
```
There is no cache keyed by hex string, and SwiftUI re-evaluates `body` on many state changes (selection, hover, highlight).
**Impact:** Each call allocates a small bitmap (~576 bytes for 12×12 RGBA + context overhead). At 200 visible rows × many renders/sec, this is hundreds of transient allocations per second on the main thread, contributing to GC pressure and frame drops.
**Recommendation:** Add an `NSCache<NSString, NSImage>` keyed by hex string inside `ColorImage`, or precompute swatches once and store on the decorator.

---

## Retain Cycles / Combine

### Verified — no retain cycles found
A scan of every closure site that captures `self` confirms the existing code is correct on this axis:

| Site | Capture | Verdict |
|---|---|---|
| `HistoryItemDecorator.swift:100,116` (`ensureThumbnailImage` / `ensurePreviewImage`) | `[weak self, image]` | OK — task does not retain decorator. |
| `HistoryItemDecorator.swift:232-244,252-262` (`synchronizeItemPin` / `synchronizeItemTitle`) | `[weak self]` in `DispatchQueue.main.async` | OK — re-arm uses `weak self`, guarded by `isInvalidated`. |
| `HistoryItem.swift:103` (OCR title generation) | `[weak self, imageData]` | OK. *(WONTFIX — OCR removed 2026-06-14; this capture site no longer exists.)* |
| `ApplicationImage.swift:61-82` (`DispatchSource` event handler) | `[weak self]` (outer + inner) | OK — but `appURL` is captured strongly; correct (URL is a value type and needed for re-resolve). |
| `AppDelegate.swift:184-197` (`synchronizeMenuIconText`) | `[weak self]` in `Task` | OK. |
| `History.swift:22-36` (`searchQuery.didSet`) | `[self]` (strong) | Acceptable — `History` is a singleton (`static let shared`), so the strong capture does not cause a cycle. Under Swift 6 this closure would need explicit `@MainActor` isolation; see `strong-self-closure-throttler`. |
| `ModifierFlags.swift:10`, `Throttler.swift:22`, `SoftwareUpdater.swift:25`, `FloatingPanel.swift:59` | `[weak self]` | OK. |

**No `Combine` `Cancellable` / `AnyCancellable` / `.sink` / `.assign` sites exist in the codebase** (grep returned only `onReceive` in `ContentView.swift:64,71` and `AppearanceSettingsPane.swift:183`, which are SwiftUI-managed and tied to view lifetime).

The single legitimate concern is the `@unchecked Sendable` on `HistoryItemDecorator` (`HistoryItemDecorator.swift:8`): under Swift 6 this class is mutable + non-isolated, so crossing actor boundaries would be a compile error *unless* `@unchecked Sendable` lies about it. The observation tracking closures re-enter through `DispatchQueue.main.async`, which currently happens to land on main, but is not statically guaranteed.

---

## Settings / Limits

### `defaults-arrays-grow` — User-extensible settings arrays
**Severity:** Low
**Location:** `Maccy/Extensions/Defaults.Keys+Names.swift:35-46`.
**Problem:** `ignoreRegexp: [String]`, `ignoredApps: [String]`, `ignoredPasteboardTypes: Set<String>` are user-extensible with no enforced count cap. `ignoredApps` is read on every pasteboard change (`Clipboard.swift:267-273`) and scanned linearly.
**Impact:** Small. Each entry is a short string; the linear scan dominates over the memory cost. Worth noting that the in-memory copy from `Defaults` (which reads `UserDefaults`) is recreated on every access — `Defaults` does cache, but the pattern is fragile.
**Recommendation:** Enforce a soft cap in the settings UI; switch to a `Set<String>` for `ignoredApps` (it is currently an array, scanned with `.contains`).

### `size-count-only` — `Defaults[.size]` bounds COUNT, not BYTES
**Severity:** Informational (already in baseline)
**Location:** `Maccy/Extensions/Defaults.Keys+Names.swift:66`; `Maccy/Settings/StorageSettingsPane.swift:103-118`.
**Note:** The "Size" setting caps the number of items (1…999). Combined with `maxClipboardContentSize` (default 10 MiB per BLOB, up to 1 GiB) the *byte* footprint is `size × maxClipboardContentSize × avg_blobs_per_item`, which is uncapped by the UI. This is the structural root cause of the worst-case math below. No code fix alone addresses it — it needs either an RSS-aware eviction policy or a byte-budget default.

---

## Worst-case Analysis

Assumptions (all configurable, all realistic):
- `Defaults[.size] = 999` (max; `StorageSettingsPane.swift:69`).
- `Defaults[.maxClipboardContentSize] = 10 MiB` (default; up to 1024 MiB; `Defaults.Keys+Names.swift:24-27`).
- 20% of items are images; avg source image 3 MiB; avg 2 non-image content blobs per item (string + html/rtf), avg 100 KiB each.
- Screen: 27" iMac retina, `visibleFrame` ≈ 2560×1417 logical; at 2× backing store = 5120×2834 pixels.
- Every image item has been scrolled past at least once (so `decodedImage`, `thumbnailImage` exist) and 25% of image items have been previewed (so `previewImage` exists).

Per-image-item memory (worst case):
| Component | Size | Source |
|---|---|---|
| `imageData` on decorator (copy) | 3.0 MiB | `HistoryItemDecorator.swift:50` |
| `imageData` on SwiftData row | 3.0 MiB | `HistoryItem.swift:175-183` (same buffer may CoW-share until split) |
| `decodedImage` (full-res NSImage bitmap) | source W×H×4; 3 MiB JPEG → ~4032×3024 → ~49 MiB | `HistoryItemDecorator.swift:51,177-189` |
| `thumbnailImage` (340×40 bitmap) | ~54 KiB (1×) / ~216 KiB (2×) | `HistoryItemDecorator.swift:14,150-156` |
| `previewImage` (full visibleFrame, 2×) | 5120×2834×4 ≈ **55 MiB** | `HistoryItemDecorator.swift:13,158-165` |
| **Total per image item** | **~52 MiB steady (no preview), ~107 MiB if previewed** | |

Per-text-item memory:
| Component | Size | Source |
|---|---|---|
| `textPreviewCache` (10 000 chars) | ~20 KiB (UTF-8) | `HistoryItemDecorator.swift:52-63`, `HistoryItem.swift:10` |
| `title` on decorator + `title` on item | ~2 × title len | `HistoryItemDecorator.swift:18,81`; `HistoryItem.swift:71` |
| `attributedTitle` (when search highlight active) | ~1 KB | `HistoryItemDecorator.swift:191-216` |
| `applicationImage` ref | shared (not duplicated) | `HistoryItemDecorator.swift:48` |
| **Total per text item** | **~25 KiB** | |

Totals at `size=999`, 20% images (200 image items, 799 text items):
- `imageData` snapshots (decorator side): 200 × 3.0 MiB = **600 MiB**
- `decodedImage` bitmaps (after thumbnail generation): 200 × 49 MiB = **9.6 GiB**
- `previewImage` bitmaps (25% of 200 = 50 items previewed): 50 × 55 MiB = **2.6 GiB**
- Text items: 799 × 25 KiB ≈ **20 MiB**
- `ApplicationImageCache` (assume 50 distinct apps): 50 × ~200 KiB ≈ **10 MiB** + 50 open fds
- `Clipboard.ignoredRegexps`: ~few KiB
- `sessionLog` (one `HistoryItem` ref per paste; assume 5000 pastes in long session): 5000 × avg item size — these are *references* to objects already in `all`, so incremental cost ≈ 0 (the refs are 8 bytes each → ~40 KiB for the dictionary itself)

**Worst-case RSS floor attributable to Maccy's own allocations: ~12.8 GiB** for a 999-item, 20%-image, retina-iMac configuration with the user having browsed + previewed images. Even a more typical 200-item / 10%-image / 1080p-screen scenario (20 image items, 180 text items) works out to ~1.0 GiB of `decodedImage` alone.

These numbers assume the user has actually triggered thumbnail generation for every image. In practice `LazyVStack` ensures thumbnails are only built for items that have appeared on screen — but once built, they are *never freed* (`cleanupImages` only runs on delete/clear/invalidate or `imageMaxHeight` change). A user who scrolls the whole list once will materialize all of them.

---

## Swift 6 Implications

The current concurrency model is "everything is `@MainActor` or marked `@unchecked Sendable`." Under Swift 6 (`SWIFT_STRICT_CONCURRENCY = complete`):
- `HistoryItemDecorator.swift:8` `@unchecked Sendable` on a class with mutable non-isolated `var` properties (`title`, `previewImage`, `thumbnailImage`, `selectionIndex`, `isVisible`, …) would be a compile error waiting to happen the first time someone passes a decorator across actors. The fix (isolate the whole class to `@MainActor`) is mostly already true in practice — only the `@unchecked Sendable` is the lie.
- The proposed `NSCache`-based fixes for `ApplicationImageCache` and `ColorImage` are *Swift-6-friendly* because `NSCache` is `Sendable`-compatible and thread-safe; you can move them off-main without ceremony.
- A background `ModelContext` (recommended in `04-data-pipeline-storage.md`) would let faulting/decoding happen off-main, which directly helps memory by allowing `autoreleasepool` and short-lived contexts that shed their retained graphs on `-dealloc`.
- Adding `applicationDidReceiveMemoryWarning` is a `@MainActor`-isolated entry point — natural under Swift 6 and trivially able to call `History.shared.purgeTransientImages()`.

---

## Recommendations (prioritized)

1. **Drop the `let imageData` mirror on the decorator** (`img-fullres-dup-storage`); read through `item.imageData`. Immediate ~50% cut on the image-byte footprint.
2. **Make `decodedImage` transient**: release it as soon as `thumbnailImage`/`previewImage` are produced, or move to a shared `NSCache` keyed by `item.id` with `totalCostLimit`. Largest single win (see worst-case).
3. **Cap `previewImageSize`** at the actual slide-out rect (`previewWidth × popup.height × scale`), not `visibleFrame`. Use `CGImageSourceCreateThumbnailAtIndex` to downsample at ingest.
4. **Implement `applicationDidReceiveMemoryWarning`** in `AppDelegate` → purge `decodedImage`, `previewImage`, and trim `ApplicationImageCache` / `Clipboard.ignoredRegexps`.
5. **Purge decorator images on scroll-out**: add `.onDisappear` to `HistoryItemView` that calls `item.cleanupImages()` (or a lighter `releaseTransientImages()`), and re-arm `ensureThumbnailImage()` on `.onAppear`. `LazyVStack` already builds views lazily; this completes the symmetric release.
6. **Bound `ApplicationImageCache`**: switch to `NSCache<NSString, ApplicationImage>` with `countLimit = 64`; ensure `ApplicationImage.deinit` cancels its `DispatchSource` (already correct).
7. **Page the history load**: use `FetchDescriptor.fetchLimit` + `sortBy` in the descriptor; realize decorators lazily for visible rows. (Coordinates with `01-concurrency-ui-blocking.md`.)
8. **Cache `ColorImage` swatches** in an `NSCache<NSString, NSImage>`.
9. **Wrap `load()` / `clear()` / `clearAll()` loops in `autoreleasepool`** to bound transient AppKit allocations.
10. **Rebuild `ignoredRegexps`** on `Defaults[.ignoreRegexp]` change rather than only inserting.

---

*End of audit. Every file:line cited was read directly. Snippets are quoted verbatim from the repository at the listed paths.*

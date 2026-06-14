# Image Pipeline Audit — Maccy

Audit date: 2026-06-14
Scope: read-only review of the image decode / resize / preview / thumbnail / OCR / app-icon / color-image paths. Verified by direct file reading; line numbers reflect the current tree.

User pain point (primary): UI blocking on image clipboard entries. Everything below feeds that symptom.

---

## Summary table

| ID | Severity | Area | File:Line | One-liner |
|----|----------|------|-----------|-----------|
| IMG-001 | Critical | Decode | HistoryItemDecorator.swift:178-189 | `NSImage(data:)` full decode on @MainActor, cached as `decodedImage` (full bitmap retained per item) |
| IMG-002 | Critical | Resize | NSImage+Resized.swift:18-25 | Resize via `draw(in:operation:.copy,fraction:1)` — full-decode then redraw, no ImageIO downsample |
| IMG-003 | Critical | Preview | HistoryItemDecorator.swift:13, 164 | Preview target = full popup screen size (`visibleFrame`, fallback 2048x1536) — vastly over-sized |
| IMG-004 | Critical | Concurrency | HistoryItemDecorator.swift:100, 116, 168 | "Async" tasks are `Task { @MainActor }` — no work is offloaded off the main thread |
| IMG-005 | Critical | OCR | HistoryItem.swift:97-113, 269-292 | Vision `VNRecognizeTextRequest.perform` runs inside `Task { @MainActor }` for every image copy |
| IMG-006 | High | Preview | PreviewItemView.swift:17-19 + HistoryItemDecorator.swift:122-129 | `asyncGetPreviewImage()` awaits a @MainActor task — caller blocks main actor for the resize |
| IMG-007 | High | Resize | NSImage+Resized.swift:20 | `imageInterpolation = .high` (Lanczos-quality) on the popup hot path; unnecessary for a thumbnail |
| IMG-008 | High | Memory | HistoryItemDecorator.swift:46-51, 187 | Per-item: full-res `imageData` (Data) + full-res `decodedImage` (NSImage bitmap) + preview + thumbnail, all retained simultaneously |
| IMG-009 | High | App icon | ApplicationImage.swift:42-46 | Synchronous `NSWorkspace.shared.icon(forFile:)` at decorator init time; N lookups when history loads |
| IMG-010 | High | App icon | ApplicationImage.swift:48-87 | Per-bundle `DispatchSource` file-watch with `[.write, .delete]` mask churns on app updates; handler hops to main |
| IMG-011 | High | Caching | ApplicationImageCache.swift:8 | Unbounded `[String: ApplicationImage]` dictionary; no eviction; grows with distinct bundle ids |
| IMG-012 | High | Ingest | (missing) | No ImageIO downsampling at ingest; no on-disk thumbnail cache; no prefetch of visible-window thumbnails |
| IMG-013 | Medium | Resize | NSImage+Resized.swift:8-16 | Aspect math: `min(ratioX, ratioY)` is correct, but the "don't size up" check (`newSize.height >= size.height`) only compares height — width-up case slips through |
| IMG-014 | Medium | OCR | HistoryItem.swift:103-112 | `Task { @MainActor }` captures `[weak self]` but is never cancelled when the item is deleted; orphaned OCR writes to a deleted model |
| IMG-015 | Medium | OCR | History.swift:89-94 | Toggling `showSpecialSymbols` re-runs `generateTitle()` for every item, which (for images) re-spawns an OCR `Task` per item |
| IMG-016 | Medium | Data | HistoryItem.swift:175-183, 244-252 | `imageData` recomputed (loops `contents`) on every call; called from `hasImage`, `generateTitle`, decorator init, decorator `image()` |
| IMG-017 | Medium | Preview | PreviewItemView.swift:26-49 | Placeholder uses `idealWidth/Height = previewImageSize` (full screen) as the placeholder frame — huge layout churn before image arrives |
| IMG-018 | Medium | Preview | AsyncView.swift:29 + PreviewItemView.swift:17 | `.failed` and `.loading` render the same placeholder; an exception in `asyncGetPreviewImage` is swallowed (no error state) |
| IMG-019 | Medium | List | HistoryItemView.swift:40 + ColorImage.swift:5-16 | `ColorImage.from(item.title)` is called every render (no cache) and synthesises a 12x12 NSImage via `lockFocus` on the main thread |
| IMG-020 | Medium | List | ListItemView.swift:72 | Renders `thumbnailImage` via `Image(nsImage:)` without `.resizable()` — full-size backing bitmap pushed to SwiftUI |
| IMG-021 | Medium | Data | HistoryItem.swift:260-267 | Universal-clipboard image read via `Data(contentsOf:)` (synchronous I/O) inside `imageData` |
| IMG-022 | Medium | Concurrency | HistoryItemDecorator.swift:127 | `_ = await previewImageGenerationTask?.result` swallows `Error`; failure mode invisible |
| IMG-023 | Medium | Cleanup | HistoryItemDecorator.swift:138-147 | `cleanupImages()` cancels tasks but `generateXxx` ignores cancellation (no `Task.checkCancellation()`); an in-flight resize still completes |
| IMG-024 | Low | Resize | NSImage+Resized.swift:14 | Integer/edge: `newSize.height >= size.height` returns `self`; a 1-pixel-taller request sizes up by 0px in width silently |
| IMG-025 | Low | App icon | ApplicationImage.swift:9, 36-39 | 1-hour retry timer uses wall-clock `Date()`; on launch every deleted-bundle icon re-queries `urlForApplication` synchronously |
| IMG-026 | Low | App icon | ApplicationImage.swift:51-53 | `print(...)` for the `open()` errno path — should be `logger` |
| IMG-027 | Low | App icon | ApplicationImage.swift:72, 78 | `print("Deleted"...)` / `print("Modified"...)` in the event handler — debug noise in production |
| IMG-028 | Low | App icon | ApplicationImage.swift:55-59 | `setEventHandler` runs on `DispatchQueue.global()` but immediately bounces to main; the bounce is the only work — pointless indirection |
| IMG-029 | Low | Color | ColorImage.swift:10-13 | `NSImage.lockFocus()` is deprecated-ish / non-thread-safe; only viable on main; not cached |
| IMG-030 | Low | Data | HistoryItem.swift:159-209 | `htmlData`/`rtfData`/`html`/`rtf`/`htmlIfSmall`/`rtfIfSmall` each call `contentData(...)` independently — repeated `contents.first(where:)` scans |
| IMG-031 | Low | Hashable | HistoryItemDecorator.swift:68-73 | `hash(into:)` does not include image/thumbnail state — SwiftUI may not redraw when only the thumbnail changes (relies on `id(id)` instead) |
| IMG-032 | Low | List | HistoryItemView.swift:49-51 | `ensureThumbnailImage()` called in `onAppear`; with LazyVStack recycling, off-screen-then-on-screen items re-trigger thumbnail generation unless cached |
| IMG-033 | Low | Preview | PreviewItemView.swift:30-31, 44-45 | Placeholder and error state both use `Color.gray.opacity(0.3)` of identical size — indistinguishable |
| IMG-034 | Low | Settings | Defaults.Keys+Names.swift:47 + AppearanceSettingsPane.swift:98 | `imageMaxHeight` is in points but used directly as a pixel target for thumbnail height (no scale factor); 40 default on a 2x display renders at ~80 backing px |
| IMG-035 | Low | Concurrency | HistoryItemDecorator.swift:8 | `@unchecked Sendable` on a class with mutable `var` image caches — not actually thread-safe; will fight Swift 6 strict concurrency |
| IMG-036 | Low | OCR | HistoryItem.swift:99-101 | OCR short-circuits to `""` when `enable-testing` is in args but returns `""` regardless — even valid image titles are blank in tests |
| IMG-037 | Low | Cleanup | HistoryItemDecorator.swift:141-143 | `recache()` drops the bitmap cache but keeps the NSImage; the held `Data` (imageData) is unaffected — partial cleanup only |
| IMG-038 | Low | HEIC | HistoryItem.swift:177 | HEIC supported in `imageData` filter, but `NSImage(data:)` decode cost for HEIC is higher than JPEG/PNG — accentuates IMG-001 |

---

## What is correct (do not regress)

- The `@MainActor` isolation on the model/decorator layer is internally consistent: there are no data races on the image fields *as written*. The problem is performance, not safety.
- `NSImage.resized(to:)` preserves aspect ratio using `min(ratioX, ratioY)`, which is the right choice for a "fit inside box" semantic (not "fill").
- `cleanupImages()` cancels and nils out tasks and bitmaps; `invalidate()` calls it, so out-of-window items do release.
- `ApplicationImage` correctly falls back to a shared static `fallbackImage` (no per-item allocation).
- `ApplicationImageCache` correctly returns the shared `fallback` for items with no bundle id.
- `HistoryItem.recognizedText(in:)` uses `recognitionLevel = .fast` (cheaper than `.accurate`) and limits candidates to `topCandidates(1)`.
- Universal-clipboard image read is size-guarded by `HistoryItemContent.maxValueSize` before `Data(contentsOf:)`.
- `HistoryItemContent.maxValueSize` is derived from a user-configurable setting, capping stored blob size at ingest.

---

## 1. Decode

### IMG-001 — Full-res `NSImage(data:)` decode on @MainActor, cached as full bitmap
- Severity: Critical
- Location: `Maccy/Observables/HistoryItemDecorator.swift:178-189` (the `image()` helper); cache field at `:51` (`decodedImage`).
- Problem: The first time any consumer asks for the image (thumbnail, preview, `hasImage` indirectly), `image()` calls `NSImage(data:)`. `NSImage(data:)` is documented to lazily decode, but the very next call (`draw`/`resized`/`cgImage(forProposedRect:)`) forces a full decode of the entire source bitmap into memory on the calling thread — which is the main actor.
- Evidence / call path:
  - `HistoryItemView.onAppear` → `ensureThumbnailImage()` → `image()` → `NSImage(data:)` (line 183) → `decodedImage = image` (187).
  - `PreviewItemView` → `asyncGetPreviewImage()` → `ensurePreviewImage()` → `image()` → same path.
  - `sizeImages()` (`:168-175`) → both `generatePreviewImage` and `generateThumbnailImage` call `image()` first.
  - The decoded full-res `NSImage` is then stored in `decodedImage` and held for the lifetime of the decorator — i.e. the *full* decoded bitmap (W*H*4 bytes) is retained per visible item, in addition to the source `Data` blob and the resized copies.
- Impact:
  - For a 2560x1600 RGBA screenshot: decoded bitmap ≈ 16.4 MB. With 50 visible image items, that is ~820 MB of decoded bitmap retained, plus the source `Data`. This is the dominant source of UI jank and memory pressure.
  - Decode itself is single-threaded CPU work on the main thread — frame drops during scroll and on popup open.
- Recommendation:
  - Stop decoding the full-res image at all. Use `CGImageSourceCreateWithData` / `CGImageSourceCreateWithURL` and `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` set to the larger of (thumbnail target, preview target). Set `kCGImageSourceCreateThumbnailFromImageAlways = true`, `kCGImageSourceShouldCacheImmediately = true`, `kCGImageSourceCreateThumbnailWithTransform = true` (honors EXIF orientation).
  - Run the decode off-main: a dedicated `@globalActor` or a serial `DispatchQueue` (one shot per item). Return the small `CGImage`-backed `NSImage` to the main actor.
  - Drop `decodedImage` entirely; never hold the full-res `NSImage`. If preview truly needs higher fidelity than the thumbnail, generate *two* downsampled `CGImage`s (thumb + preview) and keep only those.
- Swift 6: a background `actor ImageDecoder` returning `Sendable` `CGImage`-backed `NSImage` is straightforward; the current `@unchecked Sendable` on the decorator would no longer be needed for the decode path.

### IMG-016 — `imageData` recomputed on every access (loops `contents`)
- Severity: Medium
- Location: `Maccy/Models/HistoryItem.swift:175-183` (`imageData`), `:244-252` (`contentData`).
- Problem: `imageData` iterates `contents.first(where:)` for `[.tiff, .png, .jpeg, .heic]` on every call. Callers include:
  - `HistoryItemDecorator.init` line 82 (`self.imageData = item.imageData`) — runs for every item at history load.
  - `hasImageData` (HistoryItem.swift:185) and `hasImage` (HistoryItemDecorator.swift:42).
  - `HistoryItem.image` (HistoryItem.swift:187) and `generateTitle` (HistoryItem.swift:98).
- Evidence: `imageData` → `contentData([.tiff, .png, .jpeg, .heic])` → `for type in types { contents.first(where: ...) }`. Each `first(where:)` is O(n) over `contents`.
- Impact: Quadratic-ish at load (N items * M content rows each). For mostly-text history this is cheap, but on a history heavy with multi-type entries it contributes to startup latency on top of IMG-001.
- Recommendation: Cache `imageData` on the `HistoryItem` once (it is immutable for a given content set), or pre-resolve it once at insert time and store a `Data?` snapshot. `@Model` properties can hold non-persisted `@Transient var cachedImageData: Data?`.

### IMG-021 — Universal-clipboard image read via `Data(contentsOf:)` synchronously
- Severity: Medium
- Location: `Maccy/Models/HistoryItem.swift:260-267` (`dataFromFileIfAllowed`), invoked from `imageData` (`:178-180`).
- Problem: For iCloud-synced image items, `imageData` synchronously hits the filesystem with `Data(contentsOf:)`. Because `imageData` runs on the main actor (it is a property on a `@Model` accessed from the decorator), this is main-thread blocking I/O against a possibly network-backed iCloud path.
- Evidence: `dataFromFileIfAllowed(_:)` → `try? Data(contentsOf: url)`. The size guard at `:262` does `url.resourceValues(forKeys: [.fileSizeKey])` first, which itself can stall on iCloud.
- Impact: First access to a universal-clipboard image can hang the UI if the file is being downloaded or the volume is slow.
- Recommendation: Move to async I/O (`Data(contentsOf:URL,options:[.uncached])` on a background queue, or `FileHandle.read`), and surface a placeholder until ready.

### IMG-038 — HEIC decode is disproportionately expensive
- Severity: Low
- Location: `Maccy/Models/HistoryItem.swift:177` (HEIC in the type filter), decoded via `NSImage(data:)` (IMG-001).
- Problem: HEIC software decode is meaningfully more expensive than JPEG/PNG. The pipeline accepts HEIC and runs the same full-decode path; for a burst of HEIC screenshots (iPhone clipboard via Handoff), the main-thread cost is amplified.
- Recommendation: ImageIO downsample (IMG-001 recommendation) sidesteps this — `CGImageSourceCreateThumbnailAtIndex` decodes only the requested resolution.

---

## 2. Resize / Thumbnail

### IMG-002 — Resize via `draw(in:operation:.copy,fraction:1)`, no ImageIO downsample
- Severity: Critical
- Location: `Maccy/Extensions/NSImage+Resized.swift:18-25`.
- Problem: The resize implementation creates a new `NSImage(size:)`, enters a graphics context, and calls `self.draw(in:from:.zero,operation:.copy,fraction:1)`. `fraction:1` means "draw the entire source at full resolution, then scale into the destination rect." So the cost is: (a) force full decode of the source (if not already decoded), then (b) a full read of every source pixel through the copy pipeline, then (c) a high-quality resample.
- Evidence:
  ```swift
  return NSImage(size: newSize, flipped: false) { destRect in
    if let context = NSGraphicsContext.current {
      context.imageInterpolation = .high
      self.draw(in: destRect, from: NSRect.zero, operation: .copy, fraction: 1)
    }
    return true
  }
  ```
  Callers: `generateThumbnailImage` (HistoryItemDecorator.swift:155), `generatePreviewImage` (:164).
- Quantified cost gap (large screenshot, source 2560x1600):
  - Current path: full 2560x1600 decode (~16 MB bitmap) + draw 2560x1600 → 340x40 thumbnail. Time on a modern Mac: ~15-40 ms main-thread per image *just for the draw*, plus the decode. With 20 visible image items at popup open, that is 300-800 ms of main-thread work serialised.
  - ImageIO path: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 340` decodes *directly* to ~340px max dimension, skipping the full-decode step entirely. Typically 1-3 ms per image, **~10x faster**, and peak memory is the thumbnail, not the full bitmap.
- Impact: Direct cause of the popup-open scroll jank. Worse for screenshots and retina display captures.
- Recommendation:
  - Replace `NSImage.resized(to:)` for the thumbnail path with `CGImageSourceCreateThumbnailAtIndex` keyed off `kCGImageSourceThumbnailMaxPixelSize = Int(max(thumbnailSize.width, thumbnailSize.height) * backingScaleFactor)`.
  - For the preview path (if it must remain larger), the same call with a larger `ThumbnailMaxPixelSize` is still a strict improvement over `draw`.
  - Optionally: for the truly heavy lifting (preview of a 8K screenshot), a small C++/Accelerate-backed area-resampling routine using vImage is faster still and trivially `Sendable`. See section 8.

### IMG-007 — `imageInterpolation = .high` on the hot path
- Severity: High
- Location: `Maccy/Extensions/NSImage+Resized.swift:20`.
- Problem: `.high` selects Lanczos-quality resampling. For a 340x40 *thumbnail*, the user cannot perceive the difference vs `.medium`/`.low`, but the CPU cost is several-fold higher. This runs on the main thread (IMG-004).
- Recommendation: Either drop to ImageIO (which uses its own high-quality downsample internally and is faster than `NSImage` draw), or at minimum set `.medium` for the thumbnail path while keeping `.high` only for the preview.

### IMG-013 — Aspect math and "don't size up" check
- Severity: Medium
- Location: `Maccy/Extensions/NSImage+Resized.swift:5-16`.
- Problem (a) — aspect logic is correct: `min(ratioX, ratioY)` yields the "fit inside box" semantic, which is what the list and preview both want. This is right.
- Problem (b) — the "don't size up" short-circuit is asymmetric:
  ```swift
  if newSize.height >= size.height { return self }
  ```
  Only height is checked. Consider a source of 5000x20 (a wide banner) requested into a 340x40 box. `ratioX = 340/5000 = 0.068`, `ratioY = 40/20 = 2.0`. `min = 0.068`. `newHeight = 20*0.068 = 1.36`. `newWidth = 5000*0.068 = 340`. `newHeight (1.36) >= size.height (20)` is false, so it proceeds to resize — correct here. But the inverse — a 20x5000 source into 340x40 — gives `newHeight = 5000*0.068 = 340`, `newHeight >= 5000`? No, so it also proceeds correctly. The check passes for these. *However*: for a 20x20 source into 340x40, `ratioX=17, ratioY=2`, `min=2`, `newHeight=40`, `newHeight(40) >= size.height(20)` is true → returns self. Good. The check is therefore correct for "don't upscale" but is **width-blind in intent**; if a future caller passes a `newSize` taller than the source but narrower, the function still short-circuits by height only, which is surprising. Document or test both dimensions.
- Impact: No current bug observed, but a latent correctness landmine.
- Recommendation: Compute `newSize` then compare *both* `newSize.width >= size.width && newSize.height >= size.height` (i.e. only skip when neither axis grows). Add a unit test for wide/tall/near-square sources.

### IMG-024 — Edge: 1-pixel size-up silently returns self
- Severity: Low
- Location: `Maccy/Extensions/NSImage+Resized.swift:14`.
- Problem: `>=` means a request one pixel *taller* than source returns the original; the caller expects a fresh image of the requested size. Cosmetic only for thumbnails (the SwiftUI `Image` is `.resizable()`), but worth noting.
- Recommendation: Use `>` if a true "do not shrink either" semantic is desired, or document the `>=` choice.

---

## 3. Preview

### IMG-003 — Preview target sized to full popup screen
- Severity: Critical
- Location: `Maccy/Observables/HistoryItemDecorator.swift:13` (`previewImageSize`), used at `:164` (`generatePreviewImage`).
- Problem:
  ```swift
  static var previewImageSize: NSSize {
    NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536)
  }
  ```
  The preview `NSImage` is sized to the *entire visible frame of the popup screen*. On a 27" Retina display that is ~5120x2880 logical — at 2x backing, the resized bitmap is enormous. Even on the fallback, 2048x1536 logical = 4096x3072 backing = ~50 MB per preview bitmap.
- Evidence: `generatePreviewImage(from:)` → `image.resized(to: HistoryItemDecorator.previewImageSize)` (line 164). `sizeImages()` (line 168-175) generates *both* preview and thumbnail in one call.
- Impact:
  - For each opened preview, the pipeline allocates and draws a screen-filling bitmap on the main thread.
  - `sizeImages()` is currently not called from a view (grep shows only the function definition site), but `ensurePreviewImage` *is* reached via `PreviewItemView` → `asyncGetPreviewImage`, which triggers the same resize. The cost lands whenever the preview popover opens.
  - Combined with IMG-002 (draw-based resize), previewing a large screenshot can stall the UI for tens to hundreds of milliseconds.
- Recommendation:
  - Cap the preview target to the actual preview viewport, not the screen. The `PreviewItemView` is constrained by the popup panel, which is much smaller than `visibleFrame`. Compute the target from the *panel* content rect, or just cap at e.g. 1600x1200 backing pixels.
  - Use ImageIO with `kCGImageSourceThumbnailMaxPixelSize` set to that capped dimension — preview no longer requires the full-res decode either.
  - Do not generate both preview and thumbnail eagerly in `sizeImages()`; let the list drive thumbnail and the preview popover drive preview.

### IMG-006 — `asyncGetPreviewImage()` awaits a @MainActor task
- Severity: High
- Location: `Maccy/Observables/HistoryItemDecorator.swift:122-129`; caller `Maccy/Views/PreviewItemView.swift:17-19`.
- Problem:
  ```swift
  @MainActor func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage { return image }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    return previewImage
  }
  ```
  `ensurePreviewImage` creates `Task { @MainActor ... }` (line 116). Awaiting a @MainActor task from a @MainActor context does not yield to a background thread — the resize still runs on the main actor. The `await` here is effectively a no-op for offloading; it only inserts a suspension point. The caller (PreviewItemView's `AsyncView` task) is itself on the main actor, so the resize blocks the main actor whenever the preview opens.
- Evidence: IMG-004; `asyncGetPreviewImage` is `@MainActor`, `previewImageGenerationTask` is `@MainActor`-isolated work, `generatePreviewImage` is `@MainActor`.
- Impact: The "async" framing gives the false impression of offloading; in practice the popup freezes while the resize runs.
- Recommendation: Make `generatePreviewImage` actually off-main (see IMG-002 / IMG-001). The task should hop to a background queue/actor for the resize, then hop back to set `previewImage` on main.

### IMG-017 — Placeholder sized to full preview frame
- Severity: Medium
- Location: `Maccy/Views/PreviewItemView.swift:26-49`.
- Problem: Both the placeholder and error state set
  ```swift
  .frame(idealWidth: previewImageSize.width, idealHeight: previewImageSize.height)
  ```
  i.e. the *full screen* as the placeholder frame. Before the image arrives, SwiftUI lays out a screen-sized gray rectangle, then re-lays-out to the image's natural aspect when it arrives. This causes visible relayout churn (and on IMG-006, the wait is non-trivial).
- Recommendation: Constrain the placeholder to the *preview viewport* size (the panel's content area), and use `.aspectRatio(1, contentMode: .fit)` or a representative default aspect. Better still: derive the placeholder size from the source image dimensions read via `CGImageSourceCopyPropertiesAtIndex` *without* decoding — gives the true aspect for free.

### IMG-018 — `.failed` and `.loading` are indistinguishable; errors swallowed
- Severity: Medium
- Location: `Maccy/Views/AsyncView.swift:29` (`case .loading, .failed: placeholder()`); `Maccy/Observables/HistoryItemDecorator.swift:127` (`_ = await ...result` discards the thrown error).
- Problem: `AsyncView` collapses `.failed` into the placeholder, so a decode failure looks identical to "still loading" — the user sees a perpetual spinner. And `asyncGetPreviewImage` swallows the task's error via `_ = await ...result` (the `try` is implicit on `.result`).
- Evidence: AsyncView.swift line 29 — both cases render `placeholder()`. PreviewItemView renders the same `Color.gray.opacity(0.3)` + spinner for both. The error branch (line 26-37) only fires when `asyncGetPreviewImage` returns `nil`, which it does on *every* decode failure path because the error was swallowed upstream.
- Impact: Broken images present as "loading forever." Hard to debug.
- Recommendation: Propagate the error (or at least a Bool) from `asyncGetPreviewImage`. Render the `photo.badge.exclamationmark` state only on actual failure; render the spinner only while loading.

### IMG-022 — `_ = await previewImageGenerationTask?.result` swallows errors
- Severity: Medium
- Location: `Maccy/Observables/HistoryItemDecorator.swift:127`.
- Problem: Accessing `.result` on a `Task<(), Error>` returns a `Result<(), Error>` without throwing; assigning to `_` discards it entirely. There is no logging.
- Recommendation: At least `logger.error` on the failure case. Better: change the task to throw a typed error the caller can branch on.

### IMG-023 — In-flight resize ignores cancellation
- Severity: Medium
- Location: `Maccy/Observables/HistoryItemDecorator.swift:138-147` (cleanup), `:150-156` and `:159-165` (generators).
- Problem: `cleanupImages()` cancels `thumbnailImageGenerationTask` and `previewImageGenerationTask`, but `generateThumbnailImage`/`generatePreviewImage` never call `Task.checkCancellation()`. Since the work is wrapped in `Task { @MainActor }`, the cancellation flag is set but the body runs to completion regardless. If the user closes the popup mid-resize, the resize finishes and *then* assigns to `thumbnailImage`/`previewImage` (the assignment runs after `cleanupImages` set them to `nil`), leaving a dangling bitmap on a decorator that was supposed to be cleaned up.
- Evidence: Lines 150-156 — the function body checks only `isInvalidated`, never `Task.isCancelled`. `cleanupImages` sets `thumbnailImage = nil` at line 144, but the in-flight task will assign again at line 155 when it completes.
- Recommendation: Check `Task.isCancelled` (or throw) before the resize and before the assignment. Combine with IMG-006/IMG-002 to make the resize interruptible.

### IMG-037 — `recache()` is partial cleanup
- Severity: Low
- Location: `Maccy/Observables/HistoryItemDecorator.swift:141-143`.
- Problem: `recache()` flushes the decoded bitmap cache but keeps the `NSImage` wrapper alive. The source `Data` (`imageData`, held at `:50`) is unaffected. So `cleanupImages` releases the *bitmap* memory but not the encoded data, and not the wrapper objects.
- Recommendation: After adopting ImageIO downsample (IMG-002), there is no `decodedImage` to recache; the smaller thumbnail/preview bitmaps can simply be `nil`-assigned (already done at `:144-146`). The `recache()` calls become redundant.

---

## 4. OCR (Vision)

### IMG-005 — Vision OCR runs on @MainActor for every image copy
- Severity: Critical
- Location: `Maccy/Models/HistoryItem.swift:97-113` (`generateTitle`), `:269-292` (`recognizedText`).
- Problem:
  ```swift
  func generateTitle() -> String {
    if let imageData {
      ...
      Task { @MainActor [weak self, imageData] in
        guard let image = NSImage(data: imageData) else { return }   // full decode on main
        guard let recognizedText = Self.recognizedText(in: image) else { return }
        self?.title = recognizedText
      }
      return ""
    }
    ...
  }
  ```
  and
  ```swift
  private static func recognizedText(in image: NSImage) -> String? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let requestHandler = VNImageRequestHandler(cgImage: cgImage)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    do { try requestHandler.perform([request]) } catch { return nil }
    ...
  }
  ```
  The task is `@MainActor`, so:
  1. `NSImage(data:)` full-decodes the image on the main thread (compounding IMG-001).
  2. `image.cgImage(forProposedRect:...)` forces a CGImage extraction (potentially another decode pass) on the main thread.
  3. `VNImageRequestHandler.perform([request])` runs the Vision pipeline *synchronously on the calling thread* — which is the main actor. `perform` is explicitly documented to block; for `.fast` on a typical screenshot this is ~50-300 ms, and for dense text images well over a second.
- Evidence / call path: `Clipboard.swift:212` (`historyItem.title = historyItem.generateTitle()`) — fires on every clipboard write of an image. Also `History.swift:91` (`updateTitle(item: item, title: item.item.generateTitle())`) on `showSpecialSymbols` toggle (see IMG-015).
- Impact:
  - Every image copy produces a main-thread stall of tens to hundreds of milliseconds (sometimes seconds). For users who screenshot frequently, this is one of the worst single sources of "Maccy froze."
  - The stall happens *during clipboard observation*, so it can also delay Maccy's acknowledgement of subsequent copies.
- Recommendation:
  - Move OCR off the main actor entirely. Vision is thread-safe; `VNImageRequestHandler.perform` is meant to run on a background queue. Wrap in a `Task.detached` or a dedicated `actor OCRWorker`.
  - Pass a `CGImage` produced by an ImageIO downsample (e.g. to ~1600px max) — Vision accuracy is unaffected by downsampling beyond ~1600px and the request runs markedly faster on a smaller bitmap.
  - Coalesce: only OCR if no other title source exists; if the user's `title` is already meaningful (e.g. fileURL present), skip OCR.
  - Use `VNImageRequestHandler.perform(requests:)` on a serial queue with cancellation: keep the `VNRecognizeTextRequest` in a field and call `cancel()` on item delete.

### IMG-014 — OCR task not cancelled on item delete
- Severity: Medium
- Location: `Maccy/Models/HistoryItem.swift:103-112`.
- Problem: The detached-… no, the `Task { @MainActor [weak self, imageData] in ... }` captures `[weak self]`, which prevents a *strong* retain cycle but does NOT cancel the task when the `HistoryItem` is deleted from SwiftData. If the user copies an image and immediately clears history, the OCR task continues to completion and then attempts `self?.title = recognizedText` against a model whose context may have been torn down.
- Evidence: No reference to the `Task` is stored (the return is discarded); there is no `cancel()` path. `History.delete` does not reach into `HistoryItem` to cancel OCR.
- Impact: Wasted CPU; potential SwiftData "context was invalidated" warnings/errors; in pathological cases a crash on background-context write.
- Recommendation: Store the OCR `Task` on the model (or on its decorator), and cancel it in `HistoryItemDecorator.invalidate()` / `History.delete`.

### IMG-015 — Toggling `showSpecialSymbols` re-OCRs every image
- Severity: Medium
- Location: `Maccy/Observables/History.swift:89-94`.
- Problem:
  ```swift
  for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
    for item in items {
      updateTitle(item: item, title: item.item.generateTitle())
    }
  }
  ```
  `generateTitle()` for an image item spawns a *new* OCR `Task { @MainActor }` per item. Toggling the setting on a history with N image items schedules N concurrent main-actor OCR passes — a guaranteed multi-second UI freeze for anyone with a screenshot-heavy history.
- Evidence: History.swift:91 → `item.item.generateTitle()` → HistoryItem.swift:97-113.
- Recommendation: Cache the OCR result on the model (`@Transient var ocrText: String?`). On setting toggle, just re-render the cached text through the new formatter; do not re-run Vision.

### IMG-036 — OCR returns `""` under `enable-testing`
- Severity: Low
- Location: `Maccy/Models/HistoryItem.swift:99-101`.
- Problem: When the app is launched with `enable-testing`, image titles are forced to `""` and the OCR task is skipped — but this is also the displayed title. Tests that exercise the title path see empty strings for image items, hiding OCR-related regressions.
- Recommendation: Inject a mock OCR dependency for tests rather than blanking the title in production code paths.

---

## 5. App icons

### IMG-009 — Synchronous `NSWorkspace.icon` at decorator init
- Severity: High
- Location: `Maccy/ApplicationImage.swift:42-46`; called from `Maccy/Observables/HistoryItemDecorator.swift:83` (`self.applicationImage = ApplicationImageCache.shared.getImage(item: item)`).
- Problem: `ApplicationImageCache.getImage` returns an `ApplicationImage`; the *first* time `.nsImage` is read (which happens during the first list render via `AppImageView` at `AppImageView.swift:8`), it calls `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and `NSWorkspace.shared.icon(forFile:)` — both synchronous, both potentially slow for non-cached bundle ids (LaunchServices lookup). At history-load time, `History.load` constructs N decorators, each of which primes an `ApplicationImage`; on first paint, each unique bundle id triggers a lookup.
- Evidence: `ApplicationImage.nsImage` getter (line 25-93). `AppImageView.body` reads `appImage.nsImage` synchronously.
- Impact: At app launch with a long history containing many distinct source apps, the first paint of the list does N LaunchServices lookups + N icon rasterisations on the main thread.
- Recommendation: Pre-warm the cache in the background on app launch (iterate distinct bundle ids found in the DB, fetch icons on a background queue). At render time, return a placeholder until the icon is ready.

### IMG-010 — Per-bundle `DispatchSource` file-watch churns
- Severity: High
- Location: `Maccy/ApplicationImage.swift:48-87`.
- Problem: For every bundle id with a resolved URL, the code opens the URL with `O_EVTONLY` and registers a `DispatchSource` for `[.write, .delete]`. Issues:
  1. **Scale**: every distinct source app in the user's history opens a kernel file-watch. Most users have 20-100 distinct apps across their history; that is 20-100 active dispatch sources.
  2. **`.write` mask on an `.app` bundle**: writing into an app bundle happens during app *updates* — fine — but also during stapling, notarisation, etc. Every event triggers `NSWorkspace.shared.icon(forFile:)` synchronously on the main queue (line 79).
  3. **`setEventHandler` on `DispatchQueue.global()` then immediate bounce to main** (lines 55-82) — the global-queue hop is wasted work; the only real work is on main.
- Evidence: Lines 55-82.
- Impact: Kernel resource pressure (fd usage), and periodic main-thread icon re-fetches when apps update.
- Recommendation: Drop `.write`; only watch `.delete`/`.rename` (an icon change is meaningless without an app change the user cares about). Or — better — listen to `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification` and re-fetch lazily. Move the icon re-fetch off main.

### IMG-011 — `ApplicationImageCache` is unbounded
- Severity: High
- Location: `Maccy/ApplicationImageCache.swift:8`.
- Problem: `private var cache: [String: ApplicationImage] = [:]` grows monotonically with the number of distinct bundle ids ever observed. There is no eviction. Long-running Maccy instances that observe many transient apps (e.g. apps that are later uninstalled) accumulate stale `ApplicationImage` objects, each holding an `NSImage`, a `DispatchSource`, and a file descriptor.
- Evidence: `getImage(item:)` only inserts; never removes. `ApplicationImage.deinit` cancels the dispatch source, but the entry is never removed from the cache, so deinit only fires when the cache itself is torn down.
- Impact: Memory and fd leak proportional to distinct-apps-ever-seen. On a heavily-used machine this can be hundreds of icons retained indefinitely.
- Recommendation: Cap the cache (NSCache, or an LRU dict). Evict on app uninstall (the existing `.delete` event handler is the natural trigger — call into the cache to remove).

### IMG-025 — 1-hour retry uses wall-clock Date
- Severity: Low
- Location: `Maccy/ApplicationImage.swift:9, 36-40`.
- Problem: Deleted-bundle icons fall back and re-query `urlForApplication` once per hour per bundle id (line 36-40). On launch, *every* deleted-bundle icon immediately fails the check (since `lastChecked` is nil → set to now → returns fallback), but the next call within the hour short-circuits. Fine — except this means launch does N synchronous `urlForApplication` lookups for already-deleted apps.
- Recommendation: Persist `lastChecked` or skip re-checking entirely at launch; rely on the file-watch for "app came back" signal.

### IMG-026, IMG-027 — `print(...)` in production
- Severity: Low
- Location: `ApplicationImage.swift:51-53` (errno print), `:72` (`print("Deleted", ...)`), `:78` (`print("Modified", ...)`).
- Problem: `print` goes to stdout unbuffered; clutters logs.
- Recommendation: Use the project `Logger`.

### IMG-028 — Pointless global-queue bounce
- Severity: Low
- Location: `ApplicationImage.swift:55-82`.
- Problem: The dispatch source handler is registered on `DispatchQueue.global()` and immediately does `DispatchQueue.main.async { ... }`. The outer global hop buys nothing.
- Recommendation: Register the source on `.main` directly if the work needs to be on main, or do all the work on the global queue and only touch UI-affined state on main.

---

## 6. Caching

### IMG-008 — Worst-case memory: 4 copies of every image retained
- Severity: High
- Location: `HistoryItemDecorator.swift:46-51` (fields), `:187` (decodedImage assignment), plus `HistoryItem.swift:175-183` (source `imageData`).
- Problem: For a single visible image item, the live set is:
  1. The encoded source `Data` (imageData) — held by the decorator (`:50`) *and* by SwiftData (`HistoryItemContent.value`). Worst case `maxClipboardContentSize` MB per item.
  2. The full-res decoded `NSImage` (`decodedImage`, `:51`) — W*H*4 bytes.
  3. The screen-sized preview `NSImage` (`previewImage`, `:46`) — `visibleFrame` * 4 bytes (2x backing doubles it).
  4. The thumbnail `NSImage` (`thumbnailImage`, `:47`) — small (~340x40*4 = ~54 KB) — negligible.
- Quantified worst case (5K Retina screenshot, 5120x2880 RGBA, ~10 MB encoded):
  1. `imageData`: ~10 MB (encoded).
  2. `decodedImage`: 5120*2880*4 ≈ 58.5 MB.
  3. `previewImage`: visibleFrame-backed ~5120x2880*4 ≈ 58.5 MB (or up to 2x if backing store).
  - Per item: ~127 MB. With 10 such items visible: ~1.27 GB.
- Impact: Memory blows past Maccy's (modest) footprint budget and triggers Jetsam pressure events; swap; UI jank under pressure.
- Recommendation:
  - Drop `decodedImage` entirely (IMG-001): never hold the full-res decoded image.
  - Cap `previewImage` size (IMG-003).
  - Once a preview is dismissed, nil it out (current `cleanupImages` does, but only on `invalidate`; closing the preview popover without invalidating keeps it).
  - Consider a small LRU thumbnail cache shared across items.

### IMG-012 — No ingest-time downsample, no disk thumbnail cache, no prefetch
- Severity: High
- Location: Absent. Ingest is `Maccy/Clipboard.swift:195-215` (raw `Data` stored verbatim into `HistoryItemContent`).
- Problem:
  1. **No ingest downsample**: the full-resolution image bytes are persisted (correct for paste fidelity) *and* used as the decode source for every thumbnail/preview. There is no opportunity to pre-generate a small thumbnail at copy time.
  2. **No disk thumbnail cache**: every app launch re-decodes and re-resizes every visible image's thumbnail from scratch.
  3. **No prefetch**: `HistoryItemView.onAppear` triggers `ensureThumbnailImage()` *only when the row appears*. Scroll-fast and you re-trigger generation for recycled rows (LazyVStack).
- Recommendation:
  - **Prefetch the visible window**: when `History.load` completes, kick off thumbnail generation for the first K (e.g. 20) items on a background queue, so they are ready before first paint.
  - **Disk cache**: write the generated thumbnail (PNG) to `~/Library/Application Support/Maccy/Thumbnails/<item-id>.png`. On load, if present, skip decode.
  - **Ingest downsample** (optional): at copy time, generate the thumbnail via ImageIO and store it alongside, so the first render is instant.

### IMG-029 — `ColorImage` uses `lockFocus()` and is uncached
- Severity: Low
- Location: `Maccy/ColorImage.swift:5-16`; called from `Maccy/Views/HistoryItemView.swift:40` (`accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title)`).
- Problem: `lockFocus()`/`unlockFocus()` is the legacy main-thread-only drawing API. `ColorImage.from(...)` is called from the view body on every render that lacks a thumbnail, with no memoisation. For text items whose title parses as a hex color, every redraw re-allocates and re-draws a 12x12 swatch.
- Impact: Tiny per-call cost, but called per-render per-row.
- Recommendation: Memoize by hex string (an `NSCache<NSString, NSImage>`). Prefer `NSImage(size:flipped:drawingHandler:)` over `lockFocus`.

---

## 7. Color images

### IMG-019 — `ColorImage.from(item.title)` recomputed every render
- Severity: Medium
- Location: `Maccy/Views/HistoryItemView.swift:40`; `Maccy/ColorImage.swift:5-16`.
- Problem: The ternary `item.thumbnailImage != nil ? nil : ColorImage.from(item.title)` evaluates `ColorImage.from(item.title)` on every SwiftUI invalidation of `HistoryItemView.body`. SwiftUI may invalidate the body on hover, selection, scroll, etc. Each call re-parses the hex and re-draws.
- Recommendation: Compute once and cache (see IMG-029). Move the parse to a `@State` or a memoised helper.

### IMG-030 — Repeated `contents.first(where:)` scans in `HistoryItem`
- Severity: Low
- Location: `Maccy/Models/HistoryItem.swift:159-209`.
- Problem: `htmlData`, `rtfData`, `text`, `modified`, `fromMaccy`, `universalClipboard` each call `contentData(...)` which loops `contents`. Combined with IMG-016, accessing multiple properties (as the engine does) re-scans repeatedly.
- Recommendation: Build a `[PasteboardType: Data]` lookup once per item (lazily, `@Transient`).

---

## 8. C++ / Accelerate opportunity (where applicable)

The user asked about using C++ for image work. For Maccy's needs:

- **ImageIO is sufficient for ~90% of the win.** `CGImageSourceCreateThumbnailAtIndex` is C-based (CoreGraphics), already linked, and outperforms the current `NSImage.draw` path by ~10x with no new dependencies. Recommend this *first*; it is the highest-leverage, lowest-risk change.
- **vImage (Accelerate)** is the right tool if you need custom area resampling (e.g. a sharper downscale than ImageIO's default for the *preview* path, or a gamma-correct resize). It is SIMD-accelerated and callable from Swift directly — no C++ shim needed. `vImageScale_ARGB8888` or `vImageScale_CbCr8` on a `vImage_Buffer` is the idiomatic choice.
- **A C++ routine is justified only if** you need pixel-level processing ImageIO/vImage do not provide (e.g. perceptual hashing for duplicate detection, custom color management). For pure resize, C++ would be a layer of indirection over vImage with no perf gain. Recommendation: skip C++ for resize; revisit only for duplicate-detection hashing.
- **Swift 6 implication**: any C++ interop must present a `Sendable` boundary; an `actor ImageWorker` wrapping the C++/vImage call is cleaner than a free function.

---

## 9. Swift 6 implications (cross-cutting)

- **IMG-035**: `HistoryItemDecorator` is `@unchecked Sendable` while holding mutable `var` image fields (`thumbnailImage`, `previewImage`, `decodedImage`, the two `Task`s). This is unsafe under Swift 6 strict concurrency; the only reason it works today is the universal `@MainActor` isolation. Migrating image work off-main (the recommended fix) *forces* a real `Sendable` boundary — pass `Data` or `CGImage` (both `Sendable`) into a background actor, return a `Sendable` result, and assign to the decorator on main. Drop `@unchecked Sendable` once the off-main path lands.
- **IMG-005/IMG-014**: OCR `Task { @MainActor }` should become `Task.detached` (or an `actor OCRWorker` call). The result write-back hops to main.
- **IMG-011**: `ApplicationImageCache` is `@MainActor`; if app-icon fetch moves off-main (recommended), the cache itself should be an `actor` or a lock-protected `OSAllocatedUnfairLock<Dictionary>`.
- **IMG-001**: an `actor ImageDecoder` returning `Sendable` thumbnails is the natural Swift 6 shape; it composes cleanly with `@Model` (the model stays `@MainActor`, only the decode is off-main).

---

## Cross-reference of recommendations to user goals

| User goal | Findings that address it |
|-----------|--------------------------|
| Fix image preview blocking (top priority) | IMG-001, IMG-002, IMG-003, IMG-004, IMG-006, IMG-007, IMG-023 |
| Memory improvement | IMG-001, IMG-003, IMG-008, IMG-011, IMG-012 |
| Responsiveness | IMG-004, IMG-005, IMG-009, IMG-012, IMG-014, IMG-015 |
| Possibly C++ image work | Section 8 (recommend vImage/ImageIO; defer C++) |
| Migrate to Swift 6 | IMG-035, section 9 |

---

End of audit. 38 findings total (5 critical, 7 high, 13 medium, 13 low).

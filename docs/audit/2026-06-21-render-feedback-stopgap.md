# 2026-06-21 — Render-feedback stopgap (P0/P1/P2/P3)

## What happened

The `perf-mixed` benchmark (`MaccyUITests/PerfRenderUITests.testMixedRenderB`)
hung ~400s: XCUITest reported "process main thread busy for 30.0s", unable to
snapshot. A spindump + code audit pinned the root cause to a SwiftUI
**LazyVStack layout-feedback storm** — main thread in
`AG::Subgraph::update` → `LazySubviewPlacements` →
`StyledTextLayoutEngine.sizeThatFits` → `_NSOptimalLineBreaker` (CoreText
text-measurement churn), with ~zero ImageIO samples. image-only and text-only
passed; mixed exploded at the fold edge.

This is **BS-0 stopgap work** (pre-BS-4), not the data-pipeline refactor. It
does not change the `@MainActor`/`mainContext` root cause the roadmap targets
(that's BS-4); it removes render-path feedback loops that independently freeze
the UI.

## The four verified root causes + fixes

### P3 — Duration→ms 1000× underreport (harness bug)
`Duration.components` = `(seconds, attoseconds)` where attoseconds is the
sub-second part (1 atto = 1e-18 s). Milliseconds = `seconds×1000 +
attoseconds/1e15`. The harness divided by `1e18` (→ seconds), so every
sub-second `latencyMs`/`mainBlockMs` was underreported ~1000× (a 60ms render
printed `0.06 ms`). This is why prior runner numbers looked impossibly fast.
**Fixed** (`03f8f67`): `ImageDecodePerformanceTests.milliseconds` and
`PerfRecorder.millis` now divide by `1e15`. **All pre-fix baseline numbers are
invalid; re-capture.**

### P1 — hover-triggered programmatic scrollTo
Popup opens with `isKeyboardNavigating=true`; the first mouse move clears it,
whose `didSet` called `select(id:)` → `select(item:)` → `scroll(to:)`, setting
`scrollTarget` on **every hover** → LazyVStack anchor invalidation → layout
churn (the feedback-loop trigger). **Fixed** (`03f8f67`):
`NavigationManager.isKeyboardNavigating.didSet` now calls
`selectWithoutScrolling(id:)` — hover selects an already-visible cell without
disturbing scroll position. (Keyboard nav still scrolls — correct.)

### P0 — unfixed row geometry (the storm itself)
`ListItemView` used `.frame(minHeight: Popup.itemHeight)` (a floor, not fixed)
and the image branch had **no frame and no `.aspectRatio`**. An async thumbnail
landing grew the row (imageMaxHeight path) → LazyVStack re-measured every row →
CoreText optimal-line-break per invalidation → feedback loop. **Fixed**
(`6bc92d7`): row is `.frame(height: Popup.itemHeight)` (fixed); image branch is
`.frame(height: itemHeight-10).scaledToFit()` (bounded, aspect-preserved).
Row geometry is now invariant to thumbnail state. `perf-mixed` 400s → 23.6s.

**`imageMaxHeight` is dead in production.** `HistoryItemDecorator.thumbnailImageSize`
= `NSSize(340, max(1, imageMaxHeight))`, but `ImageProcessor.thumbnail` collapses
to `maxPixel = max(340, 40) = 340` (`ImageProcessor.swift:40`) — the height
component is ignored, so the setting has no pixel effect through the production
downsample path. Its tooltip ("Set to 16 to look like text items") proves the
intent was compact text-height image rows; P0's fixed-height clamp is the first
mechanism that realises that intent. The setting UI is left in place (removal
is out of scope); it's effectively inert for the list thumbnail.

### P2 — stale preview decode pile-up (BS-3 收尾, IMG-023 gap)
The single serial `ImageProcessor` actor serialized ALL thumbnail+preview
decodes. `previewImageGenerationTask` was cancelled ONLY by
`invalidate()`/`cleanupImages()` (delete/clear/reconcile-removal) — never on
selection change. Navigating off a lead item left its preview decoding to
completion, piling up on the actor → the 1.5s spike (A mixed thumbnail
`latencyMax=1530ms`); mouse-hover the worst real-world trigger (no throttle;
every row-enter fires a selection → `.id` rebuild → `ensurePreviewImage`).
**Fixed** (`3599b2f`): `HistoryItemDecorator.cancelPreviewGeneration()`
(cancel+nil the task, KEEP the cached `previewImage`); `NavigationManager.
leadHistoryItem.didSet` calls `oldValue.cancelPreviewGeneration()` on lead
change. A re-select of a decoded item stays instant (cache hit); a re-select of
a cancelled-uncached item re-kicks (nil'd handle lets `ensurePreviewImage`
through). TDD: `HistoryDecoratorTests` cancellation tests with a
`ControllableImageProcessor` mock (fills the IMG-023 gap — no test asserted
cancellation before).

**Known limitation:** an in-flight `CGImageSourceCreateThumbnailAtIndex` decode
is non-cancellable, so one already-decoding image finishes (result discarded);
full latest-wins preemption (actor priority queue) is a larger deferred change.

## What was investigated and ruled out (not real issues post-P0)

- The 1.37ms `mainBlock` in A preview is `ensurePreviewImage`'s sync kick
  (nil-guards + Task construction + `NSScreen.visibleFrame` read), inflated by
  concurrent decode hop-backs on main — sub-2ms scheduling jitter, NOT a data
  touch. The 1MB `imageData` is never touched on main; the FNV fingerprint runs
  on the actor (off-main); the preview path has no fingerprint at all.
- `.id(item.id)` rebuilds `PreviewItemView`'s metadata/Divider/toolbar per
  selection (cosmetic; one uncached `NSWorkspace.urlForApplication` per rebuild
  — could be cached later). The decode re-kick it triggers is the P2 path.
- Slideout auto-open animates window **width** (+400px) over 250ms — a
  width-churn text-wrap feedback surface distinct from the height one P0 closed.
  Bounded by fixed row heights post-P0; not the hang cause.
- `popup.needsResize`, keyboard `scrollTo`, `synchronizeItemTitle/Pin`,
  `onMouseMove` — all neutralized or sub-threshold post-P0.

## Remaining (deferred, tracked)

- **BS-4.2–4.9** — the `History.load()`/`reconcileWithStore` refactor that
  drives the 0.9s data-pipeline main-block (`load()` maxGap image-200=0.906s)
  down to <16ms. The harness (now honest post-P3) measures it. **Next.**
- **Latest-wins preview preemption** (actor priority queue) — BS-3 limitation.
- **`.id(item.id)` → `.task(id:)` on AsyncView** — avoid rebuilding preview
  metadata; separate cleanup.
- **BS-6** — `History.load()` eagerly materializes ALL items' `imageData`
  (200×1MB≈200MB resident though LazyVStack only shows the fold); blob faulting
  is on-main at load time. Memory track.
- **BS-5** — search→actor, truncation units, highlight. (The text storm here is
  list-layout measurement, NOT the search path — do not conflate.)

## Road-map归位

Per `docs/audit/2026-06-14/roadmap/`: P1/P0/P3 are BS-0 stopgap (pre-BS-4);
P2 is BS-3 image-pipeline收尾 (IMG-023 only wired `invalidate`/`cleanupImages`).
None of this changes the `@MainActor`/`mainContext` root cause BS-4 targets.

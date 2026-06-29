# Clipboard preview interaction redesign (2026-06-26)

> **Off-roadmap feature** (not part of `docs/audit/2026-06-14/roadmap/`).
> User-directed UX redesign; recorded per CLAUDE.md. Orthogonal to the BS-2..8
> concurrency roadmap (touches only the preview subsystem). See memory
> `preview-system-root-causes` and plan `cozy-wishing-donut.md`.

## Why

The preview felt bad: **sticky auto-open** ("once one item triggers preview,
every selection gets previewed"), a fixed **1.5 s** open delay, **open/resize
jank**, no debounce. A 14-agent design workflow (Map → Design → adversarial
Verify → Synthesize) traced the root causes — all 4 fresh redesigns (peek-card,
inline-expand, instant-tracking, docked) were judged unsound; the winner was a
**repaired docked pane** that adopts the repo's own 4.10b doctrine.

## Root causes (code-traced)

1. **Sticky-chase**: `SlideoutContentView` bound directly to
   `navigator.leadHistoryItem`, so every selection swapped preview content.
   `NavigationManager.leadHistoryItem.didSet` re-armed `startAutoOpen` per change.
2. **Storm/jank**: `SlideoutController.togglePreview` opened via `withAnimation` +
   `NSAnimationContext.runAnimationGroup { window.animator().setFrame }` over
   0.25 s — the same per-frame `NSHostingView.layout` + CoreText re-measure
   render-chain storm `FloatingPanel.swift:89-104` abandoned (4.10b).

## Decisions (locked with the user)

- **Trigger = one configurable `previewDelay` knob.** A single delay-driven
  retarget timer whose cancel-on-change IS the debounce at every value:
  `≈0`/`<100 ms` = instant follow-selection; `≥100 ms` = dwell-to-peek. Default
  lowered 1500 → **200 ms**; Settings min opened to **0**. No code fork between
  modes — the delay magnitude produces the behavior.
- **Open feel = instant snap + opacity fade** (4.10b doctrine).
- Priority = **balanced** (no regression to ~102 MB baseline or render-storm
  fixes). Mouse + keyboard both supported.
- **Decouple "previewed item" from lead selection** so the pane stops chasing
  every arrow move.
- Cache work (DecodedImageCache) **demoted out of scope** — re-select is already
  instant via retained `previewImage`, and `History.swift:353-380` already
  preserves decorator identity across reload.

## Changes (3 commits, each CI-green)

1. **`fix(ui): lower previewDelay default to 200, allow 0 in Settings`** — config
   only (`Defaults.Keys+Names`, `AppearanceSettingsPane`, en strings).
2. **`fix(ui): decouple previewed item from lead selection (dwell/follow)`** —
   `SlideoutController.previewedItem` + `scheduleRetarget(lead:)` (replaces
   `startAutoOpen`); `SlideoutContentView` rebinds to `preview.previewedItem`;
   callers updated (`NavigationManager.didSet`, `FloatingPanel`,
   `HistoryListView`); `FloatingPanel.close()` nils `previewedItem`. `.id(item.id)`
   retained (load-bearing for `AsyncView`'s `.task`).
3. **`perf(ui): snap preview open instantly + opacity fade (kill render storm)`**
   — `togglePreview` rewritten to ONE instant `window.setFrame` + synchronous
   state collapse (no animator/NSAnimationContext/withAnimation → no completion
   handler → no stranded `.opening/.closing`). Dead symbols removed
   (`togglePreviewStateWithAnimation`, `animationDuration`,
   `contentAnimationWidth`, `windowAnimationOrigin(-BaseState)`,
   `SlideoutState.toggleWithAnimation/animationDone`). `SlideoutView` fades the
   slideout **content** opacity (scoped inside the VStack so the outer
   width-collapse frame stays un-animated — one layout pass; opacity is
   CoreAnimation, no layout cost).

## Verification

No local toolchain — gate is "macOS 26 ARM CI". Existing tests cover it (no new
tests added; the retarget timer is Task/time-based, flaky to unit-test on the
headless runner): `PreviewRefreshUITests/testPreviewRefreshesAcrossNavigation`
(1 s nav interval ≫ 200 ms dwell → `previewedItem` still swaps per nav, gating
Fix A) and `PerfRenderUITests` (`perfOpenPreview` render-B, gating Fix B's
storm kill). All 10 jobs green across the 3 commits.

## Known follow-ups (not done)

- Mouse-click retarget waits `previewDelay` (click isn't special-cased); a
  "click bypasses dwell" refinement is possible.
- `SlideoutState.opening/.closing` cases are now unreachable (state is always
  `.open/.closed`); left in place (harmless; `isAnimating`/`isOpen` still used).
- Other-locale `PreviewDelay` strings fall back to English until Weblate syncs.

# Configurable max visible items in popup (2026-06-26)

> **Off-roadmap feature** (not part of `docs/audit/2026-06-14/roadmap/`).
> User-directed UI change; recorded here per CLAUDE.md "record any deviation".
> Does not touch the data pipeline / concurrency work — pure UI sizing.

## Why

The popup grew to ~800px (~36 rows) for long histories — too tall for the
user's taste. Request: show ~10 items, scroll for the rest, configurable, and
make the count the sole height control (disable manual height drag).

## Design decision (why cap height, not slice the array)

The list is a `LazyVStack` inside a `ScrollView` (`HistoryListView`). Slicing
the array with `.prefix(N)` would **drop items entirely** — they'd never enter
the list and couldn't be scrolled to. Instead we **cap the window height** at
`maxVisibleItems × itemHeight`; the existing `ScrollView` reveals the rest.
This is exactly "show N, scroll for more".

## Changes

- `Defaults.Keys.maxVisibleItems` (`Int`, default **36**). Default 36 keeps the
  shipped ~800px look: at default, the count cap (36×22=792 / 36×24=864) sits at
  or above `preferredHeight`'s `windowSize.height` (800px) guardrail, so the
  guardrail still binds → byte-identical default behavior. Lowering the count
  (e.g. 10) makes the count cap bind → shorter window.
- `Popup.cappedListHeight(contentHeight:maxVisibleItems:itemHeight:)` — pure,
  unit-tested helper. Applied in `Popup.resize(height:)` (the measured
  scroll-content height → capped before chrome + `preferredHeight`).
  `preferredHeight(for:)` is **unchanged** so the shared slideout/preview path
  is unaffected.
- `FloatingPanel.windowWillResize` — during live drag, pin returned height to
  the current frame (vertical drag becomes a no-op); width stays resizable and
  still drives preview resize. Gated on `inLiveResize` so programmatic
  `setFrame`/`setContentSize` (`Popup.resize → verticallyResize`, `open`) are
  never affected. Persisted size now preserves the stored height (width only
  follows the drag).
- `AppearanceSettingsPane` — new "Max visible items" section (TextField +
  Stepper, 1…50), mirroring the existing Image height / Preview delay rows.
- `en.lproj/AppearanceSettings.strings` — `MaxVisibleItems` +
  `MaxVisibleItemsTooltip` source keys. Other locales fall back to English via
  `Text(_, tableName:)` until Weblate translates (do not hand-edit locale
  strings — see CLAUDE.md).
- `MaccyTests/PopupTests.testCappedListHeightLimitsRowsToMaxVisibleItems`.

## Interaction with manual drag-resize (user decision)

User chose: **disable height drag entirely; only the count controls height.**
So height is no longer user-draggable. Width drag is preserved. The saved
`windowSize.height` (800) now acts purely as a safety guardrail inside
`preferredHeight`; it cannot be changed by dragging anymore.

Note (minor, documented): values of `maxVisibleItems` above ~36 (22pt rows) /
~33 (24pt rows) have no additional visible effect because the 800px guardrail
binds first. The stepper max is 50. Not relevant to the user's target of 10.

## Verification

No local toolchain — gate is the GitHub Actions runner
(`macOS 26 ARM CI`, ~11 min): SwiftLint `--strict` + clean build + unit tests
(incl. the new `PopupTests` case) + UI tests, all grepped for
`warning:`/`error:`/`TEST FAILED`. See commit + linked run.

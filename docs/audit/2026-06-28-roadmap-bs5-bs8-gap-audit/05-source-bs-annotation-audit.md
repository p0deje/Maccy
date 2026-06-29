# Source-code BS-x annotation audit (checklist for cleanup pass)

**Date:** 2026-06-29
**Scope:** every `BS-[0-8]` / `bs[0-9].[0-9]` reference in `Maccy/`, `MaccyTests/`, `MaccyUITests/` (excluding `*.lproj/`).
**Method:** `grep -rniE "BS-[0-8]|bs[0-9]\.[0-9]" Maccy/ MaccyTests/ MaccyUITests/` → 85 hits. Each read in context and judged against the 06-28 4-agent ground truth (this audit's sibling docs + MEMORY.md).
**Verdict legend:** accurate / stale / misleading.

Ground-truth facts load-bearing for this audit (so the cleanup pass is self-contained):
- BS-2 actor ingest is the LIVE prod path (`AppDelegate.swift:73` wires `BackgroundClipboardIngestor`); `MainActorIngestorAdapter` + `History.add`/`findSimilarItem`/`sessionLog` are dead-in-prod.
- BS-5 SearchActor is real and correct, but the "bug-2 fix (Character not UTF-16)" comments are overclaims: legacy `Search.fuzzySearch` (Search.swift:89-94) ALREADY uses grapheme offsets via `String.index(startIndex, offsetBy:)` — SearchActor is byte-for-byte with legacy here. The actual 07-F-010 highlight-misalignment bug is on the APPLY side (`History.swift:858 indexRange`), where no `toGrapheneRange` was ever written — unfixed.
- BS-8 xxh3 + symmetric `dataLikelyEqual` + persistent `fingerprint` column are real. BUT 8.5 backfill is MISSING: the only writes to `HistoryItemContent.fingerprint` are at INSERT (init); pre-migration rows stay `nil` forever, so the engine projection re-hashes them EVERY `contains` build (not "one-time" as the comments say).
- BS-6 `DecodedImageCache.setImage`/`image(for:)` have ZERO callers (only defs + `evict`/`purgeAll` are referenced) → dead code. `.previewHidden` has zero real callers (only the enum case + a switch arm).
- `VisibleWindowLoader` / `fetchWindow` (BS-4.3) exists but is DEAD CODE — `prewarmVisibleWindow` calls `history.load()`, not the loader.
- BS-3 (image pipeline), BS-4.2/4.4a/4.5/4.7 (dedup + incremental reconcile + prewarm), BS-7 (Swift 6 complete mode) are genuinely landed and largely accurate.

---

## BS-2 (off-main ingest actor)

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/Ingest/ClipboardIngestor.swift:35` | BS-2 | "Off-main clipboard ingest actor — the BS-2 replacement for the `History.add` half of the old main-thread path." | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:39` | BS-2.4/2.5 | "`MainActorIngestorAdapter` mirrors the existing `Clipboard` → `History.add` flow byte-for-byte and **stays the runtime path until BS-2.4/2.5 flip the switch**." | **misleading** | The switch IS flipped — `AppDelegate` wires `BackgroundClipboardIngestor` into `Clipboard.shared.ingestor`. Rewrite: "`MainActorIngestorAdapter` mirrors the legacy `Clipboard` → `History.add` flow byte-for-byte. It is **dead-in-prod** (the live ingestor is `BackgroundClipboardIngestor`, wired in `AppDelegate`); retained only so legacy unwired tests keep an `@MainActor` ingestor." |
| `Maccy/Ingest/ClipboardIngestor.swift:57` | BS-1 | "`image` is the `ImageProcessing` from BS-1 (used later for thumbnails / previews in BS-3)" | accurate | keep ("later" is slightly stale since BS-3 landed; optional: s/used later/used, as of BS-3, for/). |
| `Maccy/Ingest/ClipboardIngestor.swift:58` | BS-3 | "this actor calls `HistoryItem.generateTitle()` for text titles" (BS-3 context) | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:75` | BS-2 | "The rare modification-merge case is a deliberate BS-2 limitation; **it could be closed later** by forwarding sessionLog info into the actor's request." | **stale** | BS-2 is finished; this is not a transitional TODO. Rewrite: "The modification-merge case is a permanent gap of the actor path: `sessionLog` is `@MainActor`-only state and the actor (the live ingest path) does not consult it. `History.findSimilarItem`/`isModified` (the only `sessionLog` readers) are dead-in-prod, so this gap is accepted rather than deferred." |
| `Maccy/AppDelegate.swift:64` | BS-2.2b | "Wire the off-main ingest actor (BS-2.2b)" | accurate | keep. |
| `Maccy/AppDelegate.swift:66` | BS-2.3 | "the resulting `StoreEvent` hops back to the main actor (BS-2.3)" | accurate | keep. |
| `Maccy/AppDelegate.swift:71` | BS-3.5/3.8 | "the SAME instance backs the decorators' default processor (BS-3.5/3.8)" | accurate | keep. |
| `Maccy/Clipboard.swift:25` | BS-2.2b | "Set by `AppDelegate` ... to a `BackgroundClipboardIngestor` (BS-2.2b)" | accurate | keep. |
| `Maccy/Clipboard.swift:26` | BS-2.3 | "`onEvent` reconciles the main-context history via `History.consume` (BS-2.3)" | accurate | keep. |
| `Maccy/Clipboard.swift:31` | BS-2.2a | "When `nil` (e.g. legacy tests that haven't wired an ingestor)" | accurate | keep. |
| `Maccy/Clipboard.swift:177` | BS-2.2a | "the actor's `filterContents` (BS-2.2a) is the comprehensive, unit-tested filter" | accurate | keep. |
| `Maccy/Ingest/IngestFilter.swift:12` | BS-2.2b | "the background ingest actor (BS-2.2b) builds one of these on the main thread and hands it across." | accurate | keep. |
| `Maccy/Persistence/Storage+Background.swift:9` | BS-2.2b | "when the ingest actor (BS-2.2b) commits on this background context" | accurate | keep. |
| `Maccy/Persistence/Storage+Background.swift:12` | BS-2.3 | "`History.consume`/`reconcileWithStore` (BS-2.3)" | accurate | keep. |
| `Maccy/Observables/History.swift:290` | BS-2 | "`.removed`/`.cleared` (not emitted by the BS-2 actor today)" | accurate | keep (still true). |
| `Maccy/Observables/History.swift:299` | BS-2 | "The BS-2 actor only emits .added/.merged today" | accurate | keep. |
| `MaccyTests/BackgroundClipboardIngestorTests.swift:7` | BS-2 | "Integration tests for `BackgroundClipboardIngestor`, the BS-2 off-main ingest actor." | accurate | keep. |
| `MaccyTests/BackgroundClipboardIngestorTests.swift:284` | BS-2 | "Off-main ingest gate (the core BS-2 promise)" | accurate | keep. |
| `MaccyTests/ClipboardTests.swift:7` | BS-2.4 | "The old `onNewCopy` hook flow is gone (BS-2.4)" | accurate | keep (historical, still true). |
| `MaccyTests/HistoryConsumeTests.swift:7` | BS-2.2b | "`StoreEvent`s emitted by `BackgroundClipboardIngestor` (BS-2.2b)." | accurate | keep. |
| `MaccyTests/HistoryConsumeTests.swift:12` | BS-2.3 | "merge into the main context once BS-2.3's `automaticallyMergesChangesFromParent` fix lands" | **stale** | BS-2 is done; this reads as a pending fix. Rewrite: "merge into the main context via SwiftData's shared-store propagation (SwiftData has no `automaticallyMergesChangesFromParent`; committed saves are visible to a subsequent main-context fetch)." Drop the "once … lands" framing. |

---

## BS-3 (image pipeline)

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/ImageProcessing/ImageProcessor.swift:5` | BS-3 | "Production `ImageProcessing` conformance for the BS-3 image pipeline." | accurate | keep. |
| `Maccy/ImageProcessing/ImageProcessor.swift:9` | BS-3 | "It composes the two BS-3 primitives:" | accurate | keep. |
| `Maccy/ImageProcessing/ImageProcessor.swift:21` | BS-3.5 | "structured-cancellation work in BS-3.5 cancels the parent task when a render is superseded" | accurate | keep. |
| `Maccy/ImageProcessing/ImageDownsampler.swift:8` | BS-3 | "Used by the BS-3 image pipeline (ThumbnailCache / the ImageProcessor actor)" | accurate | keep. |
| `Maccy/ImageProcessing/ImageDownsampler.swift:42` | BS-3 / 3.3 | "the off-main-decode property of the BS-3 pipeline is satisfied by this call running off the main thread (in the actor, 3.3)" | accurate | keep. |
| `Maccy/ImageProcessing/ThumbnailCache.swift:7` | BS-3 | "Two-tier (memory + disk-LRU) thumbnail cache for the BS-3 image pipeline." | accurate | keep. |
| `Maccy/ImageProcessing/ThumbnailCache.swift:13` | BS-2 | "consistent with the BS-2 `@ModelActor` precedent." | accurate | keep. |
| `Maccy/Extensions/NSImage+Resized.swift:10` | BS-3 | "go through `ImageDownsampler` / `ImageProcessor` (BS-3), which keeps decode off the main thread and caches results." | accurate | keep. |
| `Maccy/Observables/HistoryItemDecorator.swift:99` | BS-3.8 | "AppDelegate (BS-3.8) feeds the SAME instance into the ingestor" | accurate | keep. |
| `Maccy/Observables/HistoryItemDecorator.swift:134` | BS-3.8 | "passes this same instance into the ingestor in BS-3.8 so thumbnails are cached across both paths." | accurate | keep (s/BS-3.8/the ingest wiring/ optional). |
| `Maccy/Observables/HistoryItemDecorator.swift:252` | BS-3 (收尾) | "the BS-3 收尾 of the IMG-023 cancellation gap" | accurate | keep. |
| `Maccy/Perf/PerfRecorder.swift:54` | BS-3 | "this is ~0 when BS-3's off-main decode holds." | accurate | keep. |
| `MaccyTests/HistoryDecoratorTests.swift:67` | BS-3.5 | "Generation now runs off-main (BS-3.5)" | accurate | keep. |
| `MaccyTests/HistoryDecoratorTests.swift:89` | BS-3 (收尾) | "This is the BS-3 收尾:" | accurate | keep. |
| `MaccyTests/ImageProcessorTests.swift:6` | BS-3.3 | "Behavior tests for the BS-3.3 `ImageProcessor` actor" | accurate | keep. |

---

## BS-4 (dedup / incremental reconcile / prewarm)

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/Ingest/ClipboardIngestor.swift:87` | BS-4.2 | "BS-4.2 in-memory dedup index over every committed item's content entries" | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:124` | BS-4.2 | "Dedup against existing items via the BS-4.2 per-entry `SignatureIndex`" | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:184` | BS-4.2 | "BS-4.2: keep the dedup index in sync with the committed transaction." | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:237` | BS-4.2 | "via the BS-4.2 per-entry" | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:269` | BS-4.2 | "(BS-4.2): one O(n) pass, then skipped on subsequent ingests." | accurate | keep. |
| `Maccy/Ingest/ClipboardIngestor.swift:329` | BS-4.2 | "so the caller can keep the BS-4.2 dedup index in sync" | accurate | keep. |
| `Maccy/Ingest/SignatureIndex.swift:6` | BS-4.2 | "Per-entry containment index (BS-4.2)" | accurate | keep. |
| `Maccy/Ingest/SignatureIndex.swift:64` | BS-4.2 | "(BS-4.2). Returns every indexed item sharing at least one entry" | accurate | keep. |
| `Maccy/Observables/History.swift:286` | BS-4.4a | "BS-4.4a: `.added`/`.merged` now reconcile INCREMENTALLY" | accurate | keep. |
| `Maccy/Observables/History.swift:806` | BS-5 | "// MARK: - BS-5 off-main search" | accurate | keep (section is BS-5). |
| `Maccy/Observables/AppState.swift:82` | BS-4.7 | "BS-4.7: pre-warm the history on hotkey-down" | accurate | keep. (Note: this prewarms via `history.load()`, NOT the dead `VisibleWindowLoader`.) |
| `Maccy/Observables/Popup.swift:188` | BS-4.7 | "BS-4.7: warm the history before opening so the data is ready" | accurate | keep. |
| `Maccy/Sorter.swift:46` | BS-4.4a | "For `BinaryInsertion`'s incremental insert (BS-4.4a)" | accurate | keep. |
| `Maccy/Sorter.swift:84` | BS-4.4a | "BS-4.4a's incremental consume uses this to place a new item" | accurate | keep. |
| `Maccy/Views/ContentView.swift:62` | BS-4.7 | "BS-4.7: prewarm (hotkey-down) may have already loaded" | accurate | keep. |
| `Maccy/Persistence/Storage+Background.swift:24` | BS-4.3 | "BS-4.3 primitive: fetches history items on the injected (background) context" | accurate-as-described, but **note** | The primitive exists but is DEAD CODE — never wired into `History.load()` (06-28 ground truth). Comment does not claim it is wired, so keep as-is, but ADD a line: "**Status (2026-06-29): not yet wired into `History.load()`; `prewarmVisibleWindow` calls `load()` directly.**" so future readers don't assume it is the live read path. |
| `MaccyTests/BackgroundClipboardIngestorTests.swift:419` | BS-4.2/4.5 | "MARK: - BS-4.2 per-entry containment + 4.5 fingerprint-symmetry dedup" | accurate | keep. |
| `MaccyTests/BackgroundClipboardIngestorTests.swift:424` | BS-4.2 | "the reason the BS-4.2 per-entry index keys on individual content entries" | accurate | keep. |
| `MaccyTests/BackgroundClipboardIngestorTests.swift:465` | BS-4.5 | "Fingerprint-symmetry dedup (BS-4.5): ... The dedup signature for large content carries a real **FNV** fingerprint" | **stale** | BS-8 swapped FNV→xxh3. Rewrite: "...carries a real xxh3 fingerprint (was FNV before the BS-8 swap)". |
| `MaccyTests/HistoryConsumeTests.swift:125` | BS-4.4a | "MARK: - BS-4.4a incremental insert" | accurate | keep. |
| `MaccyTests/ImageDecodePerformanceTests.swift:5` | pre-BS-4 | "the `G-popup-open` first-frame analog: **pre-BS-4** it does the full fetch+sort+decorate on the main thread" | **stale** | BS-4 landed; "pre-BS-4 it does..." describes a past state. Rewrite: "`G-popup-open` first-frame analog. BS-4 moved fetch+sort+decorate off the cold-open hot path; this benchmark measures the residual main-thread stall." |
| `MaccyTests/ImageDecodePerformanceTests.swift:13` | BS-4 | "the pre-BS-4 baseline is *expected* to exceed it. The `< 16 ms` gate assertion is added **after BS-4 lands** the batched background load." | **stale** | BS-4 has landed. Rewrite: "Baseline measurements report numbers without asserting the 16 ms threshold; the gate assertion is owned by the BS-4.3 `VisibleWindowLoader` wiring step (still pending — the loader is not yet wired into `load()`)." |
| `MaccyTests/ImageDecodePerformanceTests.swift:14` | BS-4 | "is added after BS-4 lands the batched background load." | **stale** | merge into the line above. |
| `MaccyTests/ImageDecodePerformanceTests.swift:146` | BS-4/5 | "BS-4/5 must keep mainBlock small per item." | **stale** | "must keep" reads as a forward-looking constraint on landed work. Rewrite: "BS-4 (off-main decode) and BS-5 (off-main search) keep `mainBlock` small per item." |
| `MaccyTests/SignatureIndexTests.swift:151` | BS-4.2 | "MARK: - Per-entry containment candidates (BS-4.2)" | accurate | keep. |
| `MaccyTests/StorageBackgroundContextTests.swift:14` | BS-4.3 | "MARK: - VisibleWindowLoader (BS-4.3)" | accurate | keep (the test exercises the dead-in-prod primitive; the MARK is correct). |

---

## BS-5 (off-main search)

The off-main actor + generation guard are real and correct. The "bug-2 fix" annotations are the overclaim cluster: they assert SearchActor fixes a UTF-16 offset bug, but legacy `Search` already uses grapheme (`String.index(offsetBy:)`) offsets, so the actor is byte-for-byte here. The real 07-F-010 highlight bug is on the apply side and remains unfixed.

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/Observables/History.swift:130` | BS-5 | "BS-5: off-main search. `searchGeneration` is the single staleness oracle" | accurate | keep. |
| `Maccy/SearchActor.swift:4` | BS-5 | "Off-main search actor (BS-5). Mirrors the four modes ... **byte-for-byte**" | **misleading** | "byte-for-byte" is overclaimed for the offset model (see Search.swift:89-94). The four-mode *matching* semantics are mirrored; the offset model is NOT a divergence/fix. Rewrite: "Off-main search actor (BS-5). Mirrors the four modes of the legacy `@MainActor Search` (`exact`/`fuzzy`/`regexp`/`mixed`) — same matching semantics, now on `Sendable` value types so a throttled keystroke no longer blocks the main thread." |
| `Maccy/SearchActor.swift:17` | bug-2 fix | "Offset model (bug-2 fix): every `Range<Int>` ... is a half-open **Character (grapheme-cluster)** offset ... never `NSRange` / UTF-16, which would mis-highlight on emoji" | **misleading** | Legacy `Search.fuzzySearch` ALSO emits grapheme offsets (via `String.index(startIndex, offsetBy:)`). This is NOT a fix relative to legacy (06-28: "actor fuzzy-range == legacy byte-for-byte"). The remaining 07-F-010 highlight bug is on the APPLY side (`History.swift:858 indexRange`), unfixed. Rewrite: "Offset model: `Range<Int>` values are half-open Character (grapheme-cluster) offsets computed via `String.distance(from:to:)`, matching the legacy `Search` (which uses `String.index(offsetBy:)` — also grapheme-based). NOTE: this does NOT fix the 07-F-010 apply-side highlight misalignment; that fix (a `toGrapheneRange` on the apply path) was never written." |
| `Maccy/SearchActor.swift:20` | bug-2 fix | "`String.distance(from:to:)` — never `NSRange` / UTF-16, which would [mis-highlight]" | **misleading** | fold into the line-17 fix above. |
| `Maccy/SearchActor.swift:99` | bug-2 fix | "Character (grapheme) offsets via distance — NOT NSRange/UTF-16 (bug-2 fix)." | **misleading** | s/bug-2 fix/grapheme offsets, matching legacy Search/ (drop the "fix" claim). |
| `Maccy/SearchActor.swift:130` | bug-2 fix | "half-open Character offsets lower..<(upper+1) (bug-2 fix: Character, not UTF-16)." | **misleading** | s/(bug-2 fix: Character, not UTF-16)/(mirrors Search.swift:89-94, also grapheme)/. |
| `Maccy/SearchActor.swift:131` | bug-2 fix | "(bug-2 fix: Character, not UTF-16)." | **misleading** | drop the "(bug-2 fix...)" parenthetical. |
| `Maccy/SearchActor.swift:159` | bug-2 fix | "Character (grapheme) offsets via distance (bug-2 fix)." | **misleading** | s/(bug-2 fix)/— grapheme offsets/. |
| `Maccy/SearchDTOs.swift:3` | BS-5 | "Sendable corpus projection for off-main search (BS-5)." | accurate | keep. |
| `Maccy/SearchDTOs.swift:18` | BS-5 | "Sendable search result returned by `SearchActor` (BS-5)." | accurate | keep. |
| `Maccy/SearchDTOs.swift:32` | bug-2 fix | "`Range<Int>` of **Character (grapheme-cluster) offsets** into `title` (`lower..<upper`), **NOT `NSRange`/UTF-16 (bug-2 fix)**." | **misleading** | Same as SearchActor.swift:17 — drop "bug-2 fix"; clarify this matches legacy, and the apply-side 07-F-010 is unfixed. |
| `MaccyTests/SearchActorTests.swift:4` | BS-5 | "Behavior tests for `SearchActor` (BS-5). ... plus the two soundness fixes the actor owns: Character (grapheme) offsets (bug 2) and regex empty-match → `0..<0` (bug 5)." | **misleading** | bug 2 is NOT a soundness fix owned by the actor (legacy already does grapheme). Rewrite: "plus the regex empty-match → `0..<0` guard (bug 5) and the Character-offset contract asserted against value types (matches legacy `Search`, which is also grapheme-based)." |
| `MaccyTests/SearchActorTests.swift:59-61` | bug 2 | "Bug 2: offsets are Character (grapheme) counts, NOT UTF-16. ... A correct Character offset model yields `1..<2`; a UTF-16/NSRange model would yield `1..<3`." | **misleading** | The test itself is fine (asserts the grapheme contract), but the "Bug 2" framing implies a regression was fixed. Rewrite header: "Grapheme-offset contract: offsets are Character counts, not UTF-16 (asserts parity with legacy `Search`, which is also grapheme-based via `String.index(offsetBy:)`)." |
| `MaccyTests/TextSearchPerformanceTests.swift:8` | BS-5 | "Calling `Search` directly is exactly the synchronous main-thread work **that BS-5 moves to a background actor**." | **stale** | BS-5 has moved it; this benchmark still measures the LEGACY `Search()` path (06-28: "G-search gate baseline-only measuring legacy Search()"). Rewrite: "This benchmark measures the LEGACY `@MainActor Search` (the path BS-5 superseded with `SearchActor`); it remains a legacy-path baseline, not the off-main path. The off-main gate (over `SearchActor`) was not added." |
| `MaccyTests/TextSearchPerformanceTests.swift:12` | BS-5 | "the synchronous main-thread work that BS-5 moves to a background actor. Baseline-only (no `< 16 ms` assertion yet)." | **stale** | merge into the line-8 fix. |

---

## BS-6 (memory)

`DecodedImageCache.setImage`/`image(for:)` have zero callers (dead). `.previewHidden` has no real callers. The `bs6.1-bs6.3` scaffolding comment claims wiring in C2/C3 — verify C2/C3 landed; the dead setters show the read path was never wired.

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/Observables/MemoryGovernance.swift:3` | bs6.1-bs6.3 | "C1 (master plan, bs6.1-bs6.3): memory-governance scaffolding — pure additions **wired in C2/C3**." | **misleading** | C1 landed, but the cache's `setImage`/`image(for:)` are never called (dead), so C2/C3 wiring is incomplete. Rewrite: "C1 (master plan, bs6.1-bs6.3): memory-governance scaffolding. **Status (2026-06-29): partially wired — `evict`/`purgeAll` are called, but `DecodedImageCache.setImage`/`image(for:)` have ZERO callers (the read path was never connected), so this is effectively dead for the decode-cache tier.**" |
| `Maccy/Observables/HistoryItemDecorator.swift:79` | BS-6 | "BS-6 (`img-fullres-dup-storage`): `History.load()` decorates every item, and eagerly copying each `imageData` blob ... Deferring the read to the first use..." | accurate | keep — the lazy `imageDataCache` IS wired and is a real BS-6 win. |
| `Maccy/Observables/Popup.swift:101` | BS-6.13 | "BS-6.13: the global `.popup` Carbon hotkey consumes its keyDown" | accurate | keep (the hotkey-leak fix is landed & real). |
| `Maccy/Observables/Popup.swift:135` | BS-6.13 | "BS-6.13: the global `.popup` hotkey is registered once in `init` and stays registered..." | accurate | keep. |
| `Maccy/Observables/Popup.swift:193` | BS-6.13 | "BS-6.13: previously `KeyboardShortcuts.disable(.popup)` ... That enable/disable cycle leaked a Carbon `EventHotKeyRef` per open/close." | accurate | keep. |

---

## BS-7 (Swift 6 concurrency)

Mostly accurate (13/17 landed; Swift 6.0 complete mode, zero `@unchecked`/`nonisolated(unsafe)`). No source BS-x annotations were overclaims — the gap is missing test files + redundant per-method `@MainActor`, neither of which surfaces as a stale BS-7 comment in source.

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/Observables/HistoryItemDecorator.swift:252` | (BS-3 收尾, not BS-7) | listed here only to disambiguate — this is a BS-3 comment, not BS-7. | accurate | keep. (No BS-7 source annotations found beyond git-history scope; BS-7 changes are isolation annotations, not prose.) |

*No standalone BS-7 prose annotations exist in `Maccy/`/`MaccyTests/`/`MaccyUITests/`.* The BS-7 work is `@MainActor`/`Sendable` decorators and `SWIFT_VERSION` settings — not comment-embedded BS references to audit. Cleanup pass: nothing to do for BS-7 in source comments.

---

## BS-8 (xxh3 + persistent fingerprint)

The xxh3 swap, symmetric `dataLikelyEqual`, and the `fingerprint` column are real. The misleading cluster is the "one-time re-hash" / backfill framing: 8.5 backfill is MISSING, so pre-migration rows re-hash EVERY `contains` build (not once), and the column never gets populated for them.

| file:line | ref | quote | verdict | suggested fix |
|---|---|---|---|---|
| `Maccy/Models/HistoryItemContent.swift:16` | BS-8 (08-O-007/08-F-001) | "persisted xxh3 fingerprint for large content ... `nil` for small content (no fingerprint) or pre-migration rows (read path falls back to a **one-time** re-hash via `ClipboardDataProcessor.fingerprintIfLarge`)." | **misleading** | There is NO backfill (8.5 missing): pre-migration rows stay `nil` forever and are re-hashed on EVERY `ContentIndex` build, not once. Rewrite: "...`nil` for small content (no fingerprint) or pre-migration rows. **The 8.5 write-back backfill was NOT implemented: pre-migration rows never get their column populated, so the engine projection re-hashes them on every `contains` build (correct, but perpetually in the slow path — not 'one-time').**" |
| `Maccy/Core/ClipboardDataProcessor.swift:27` | BS-8 (08-F-009/08-F-001) | "symmetric — BOTH fingerprints are required (no default params), so `dataLikelyEqual` never re-hashes. ... large content with a nil fingerprint falls back to a full `==` compare (**correct, just slower for old rows**)." | **misleading** | Understates the cost: with no backfill, ALL pre-migration large rows are perpetually slow (re-hashed every build). Rewrite the parenthetical: "(correct, but with no 8.5 backfill these rows are re-hashed on every `ContentIndex` build, not just once — the 'just slower' is unbounded over the row's lifetime)." |
| `Maccy/Engine/HistoryItemEngine.swift:107` | BS-8 (08-F-001) | "prefer the persisted column; fall back to a **one-time** re-hash for pre-migration rows (column nil but content is large)." | **misleading** | Same as HistoryItemContent.swift:16. The `??` re-computes every time `ContentIndexEntry` is constructed (per `contains` build), and nothing persists the result. Rewrite: "prefer the persisted column; fall back to re-hashing when the column is nil (pre-migration rows — these are re-hashed every build until a backfill populates the column; the 8.5 backfill is NOT implemented)." |
| `Maccy/Engine/HistoryItemEngine.swift:115` | BS-8 (08-F-001) | "carry each lhs item's persisted fingerprint so `contains` can pass it to `dataLikelyEqual` instead of re-hashing per comparison." | **misleading** | True only for rows WITH a populated column (post-migration inserts). For pre-migration rows the carried value is the freshly-re-hashed one (re-computed each build). Rewrite: "carry each lhs item's fingerprint so `contains` can pass it to `dataLikelyEqual`. For rows with a populated column (post-8.x inserts) this avoids re-hashing; for pre-migration rows (nil column, no 8.5 backfill) it is re-hashed each build." |
| `Maccy/Processor/ClipboardByteProcessor.cpp:5` | BS-8 (08-O-007) | "BS-8 (08-O-007): vendored xxHash (BSD-2, third_party/xxhash.h) for xxh3_64." | accurate | keep. |
| `Maccy/Processor/ClipboardByteProcessor.cpp:100` | BS-8 (08-O-007) | "BS-8 (08-O-007): xxh3 replaces FNV-1a for the dedup fingerprint" | accurate | keep. |
| `Maccy/Processor/ClipboardByteProcessor.cpp:104` | 8.5 | "the transition must account for this when backfilling old rows (step-8 §8.5)." | accurate-as-warning | keep — this is a correct forward pointer to the (still-missing) 8.5 step; optionally add "**(8.5 not yet implemented)**". |
| `Maccy/Processor/ClipboardByteProcessor.hpp:11` | BS-8 (08-O-007) | "BS-8 (08-O-007): SIMD-friendly hash for the dedup fingerprint, replacing the serial FNV-1a" | accurate | keep. |
| `Maccy/Processor/ClipboardByteProcessor.hpp:12-13` | 8.5 | "`seed` is the fixed migration seed (see step-8 §8.5 — it MUST be constant ...). FNV above is retained only for migration-period diagnostics, not as a fallback key." | accurate | keep. |
| `Maccy/Processor/MaccyTextProcessor.mm:5` | BS-8 (08-O-007) | "BS-8 (08-O-007): fixed migration seed for xxh3. MUST be constant ..." | accurate | keep. |
| `Maccy/Processor/MaccyTextProcessor.mm:24` | BS-8 | "BS-8: xxh3 (was FNV-1a) — SIMD-friendly, ~3-5× throughput." | accurate | keep. |
| `MaccyTests/HistoryItemPerformanceTests.swift:21` | 8.1 (BS-8 baseline) | "8.1 (BS-8 baseline): ... `dataLikelyEqual`'s `lhsFingerprint` defaults to nil, so every lhs blob is RE-HASHED per comparison (08-F-001). ... Baseline is the FNV + no-persistent-column world; **8.8 re-baselines** after the xxh3 swap + persistent column ... No baseline set this step ...; 8.8 sets `measureMetrics` `.baseline`" | **stale** | xxh3 + persistent column have landed; `lhsFingerprint` no longer "defaults to nil" (symmetric API). Rewrite: "Baseline captured PRE-xxh3-swap. The current code is xxh3 + symmetric `dataLikelyEqual` (post-08-F-001) + persistent `fingerprint` column; the 8.8 re-baseline against xxh3 with the persistent column is **NOT yet present** (four 8.8 test files + FNV baseline are missing — see 06-28 gap audit)." |
| `MaccyTests/HistoryItemPerformanceTests.swift:47` | 8.1 (BS-8 baseline) | "8.1 (BS-8 baseline): fingerprint throughput, FNV pre-swap. ... **8.8 re-baselines** against xxh3 and asserts ≥ 3× over this FNV number." | **stale** | merge into the line-21 fix; 8.8 re-baseline is missing. |

---

## Counts summary

| BS | total | accurate | stale | misleading |
|---|---|---|---|---|
| BS-2 | 21 | 18 | 2 | 1 |
| BS-3 | 15 | 15 | 0 | 0 |
| BS-4 | 26 | 21 | 4 | 0 (+1 "note") |
| BS-5 | 14 | 3 | 2 | 9 |
| BS-6 | 5 | 4 | 0 | 1 |
| BS-7 | 0 | 0 | 0 | 0 (no source prose) |
| BS-8 | 13 | 8 | 2 | 3 |
| **TOTAL** | **94 entries** | **69** | **10** | **14** |

(94 entries vs 85 grep hits: a few single hits carry two refs, e.g. the SearchActor offset-model comment spans file:17+20 and the BS-2/BS-3 split in ClipboardIngestor.swift:57-58; counted per (file:line, ref) pair.)

**Hot spots for the cleanup pass (do these first — they are the overclaims a reader would act on):**
1. **BS-5 "bug-2 fix" cluster (9 misleading)** — SearchActor.swift:4/17/20/99/130/131/159, SearchDTOs.swift:32, SearchActorTests.swift:4/59. Drop every "bug-2 fix" claim; the actor matches legacy grapheme offsets; the real 07-F-010 highlight bug (apply side) is unfixed.
2. **BS-8 "one-time re-hash / backfill" cluster (3 misleading + 1 stale)** — HistoryItemContent.swift:16, ClipboardDataProcessor.swift:27, HistoryItemEngine.swift:107/115, HistoryItemPerformanceTests.swift:21/47. The 8.5 write-back backfill is MISSING; pre-migration rows re-hash every build.
3. **BS-2 "stays the runtime path until BS-2.4/2.5" (1 misleading)** — ClipboardIngestor.swift:39. The switch is flipped; the adapter is dead-in-prod.
4. **BS-6 "wired in C2/C3" (1 misleading)** — MemoryGovernance.swift:3. `setImage`/`image(for:)` are dead.
5. **BS-4 perf-test "pre-BS-4 / after BS-4 lands" (4 stale)** — ImageDecodePerformanceTests.swift:5/13/14/146.

# BS-2 wiring UI crash — handoff (2026-06-15)

> ✅ **RESOLVED 2026-06-15** at `66344e6` (CI run `27517644893`, green). The crash was **not a
> concurrency bug**. GPT-5.5 fixed three independent state-consistency/ordering defects:
> (1) `togglePin` never persisted `pin`, so `clear()`'s `delete(model:where: #Predicate { $0.pin == nil })`
> killed the pinned row in the store while the in-memory decorator survived holding a dangling
> `@Model` — BS-2's new `reconcileWithStore` fresh-fetch then faulted the deleted object ("crashed
> in `<external symbol>`"); (2) `reconcileWithStore` rebuilt the list but never re-anchored
> `navigator.selection`; (3) unnecessary `Task { @MainActor }` wrappers deferred side effects past
> the UI-test assertions. Full root-cause analysis + Apple-doc grounding + lessons:
> **`2026-06-15-bs2-retrospective.md`**. The text below is preserved as the original handoff
> state for the audit trail.

The BS-2 ingest→actor pipeline is **built and unit-green**, but wiring it live
(`Clipboard` → actor → `History.consume`) causes an **unsymbolicated UI-test
crash** that this remote, Mac-less environment could not diagnose. This file
captures the state so the next investigator doesn't re-derive it.

## Symptom
- `MaccyUITests.testClear`: `org.p0deje.Maccy crashed in <external symbol>`
  (~23s into the test; first failure is "Maccy did not pop up",
  `MaccyUITests.swift:486`).
- `MaccyUITests.testCopyRTF`: `Asynchronous wait failed` — "bar" never appears
  (timeout, not a crash).
- **All unit tests pass** (including a cross-context probe and an off-main RTF
  regression guard added during the investigation).
- The crash reproduces on every CI run since the wiring landed; pre-wiring UI
  tests were green.

## What's built (BS-2, on `master`, unit-green)
- `Maccy/Ingest/PasteboardSource.swift` — `PasteboardSource` protocol +
  `NSPasteboardSource` + `PasteboardItemSnapshot` (BS-2.1).
- `Maccy/Ingest/IngestFilter.swift` — pure `filterContents` + `IngestConfig`
  (BS-2.2a).
- `Maccy/Ingest/ClipboardIngestor.swift` — `@ModelActor actor
  BackgroundClipboardIngestor` (filter+title on MainActor; dedup+write on the
  model actor; single-transaction commit; emits `StoreEvent`) (BS-2.2b).
- `Maccy/Observables/History.swift` — `consume(_:)` + `reconcileWithStore()`
  (fresh `mainContext.fetch`, reuse decorators by `persistentModelID`,
  invalidate dropped) (BS-2.3).
- `Maccy/Clipboard.swift` — `checkForChangesInPasteboard` dispatches a raw
  `IngestRequest` to `ingestor`; `var ingestor: ClipboardIngestor?` (BS-2.4).
- `Maccy/AppDelegate.swift` — constructs `BackgroundClipboardIngestor(
  modelContainer: Storage.shared.container, …, onEvent: { @MainActor in
  History.shared.consume($0) })` (BS-2.5).

## Ruled OUT (verified, do not re-investigate)
1. **Cross-context visibility**: a fresh `mainContext.fetch` DOES observe the
   background actor's committed save (Core Data shared-store semantics). Proven
   by `BackgroundClipboardIngestorTests.testActorBackgroundSaveIsVisibleToMainContext`
   (passes). `ModelContext` has no `automaticallyMergesChangesFromParent` — that's
   expected; the explicit StoreEvent→consume→fresh-fetch is the canonical pattern.
2. **`NSAttributedString` off-main**: `NSAttributedString(rtf:/html:)` is
   main-thread-affine. The actor now hops to `MainActor` for `filterContents` and
   `title(for:)`. The regression guard
   `testIngestRtfContentDoesNotTrapOffMain` passes.
3. **Actor pattern**: migrated to the canonical `@ModelActor` macro
   (`DefaultSerialModelExecutor` + isolated `modelContext`). Unit tests pass;
   UI still crashes — so the crash is NOT the actor pattern per se.

## What's needed to diagnose
**The symbolicated crash stack.** The CI text log only shows
"crashed in `<external symbol>`" (unsymbolicated). The `.xcresult` is
proprietary binary; extract with `xcrun xcresulttool` on a Mac, OR run the app
under Xcode/Instruments and reproduce. Relevant CI run with the crash + uploaded
`.xcresult` artifact: `27515062440` (use
`gh run download -R GuangDai/Maccy -n macos26-arm-ci-27515062440-1`).

## Prime suspects to examine on a Mac (not yet ruled out)
- The **real-app integration** of the off-main actor, specifically the actor's
  per-copy `await MainActor.run { filterContents + title }` hop under the
  repeating 0.5s pasteboard `Timer` — possible main-actor contention /
  reentrancy, or a Swift concurrency runtime trap in the hop.
- `Clipboard.checkForChangesInPasteboard`'s `Task { await ingestor?.ingest(request) }`
  capturing non-`Sendable` `Clipboard` (`self`) — compiles under Swift 5
  (`SWIFT_STRICT_CONCURRENCY=minimal`) but may race/trap in the real app.
- The `onEvent: { @MainActor event in History.shared.consume(event) }` closure
  stored as `@Sendable (StoreEvent) async -> Void` — verify the `@MainActor`
  isolation survives the existential hop at runtime.
- `History.consume`/`reconcileWithStore` running against the real `History.shared`
  state (loaded items + decorators + `AppState.shared.popup`) — may diverge from
  the unit-test fixture path.
- A main-thread **watchdog** kill from the per-copy main hops (filter+title on
  main for every copy) masquerading as a crash.

## How to run CI
- `origin` = `GuangDai/Maccy` (your fork). Push to `master` triggers
  "macOS 26 ARM CI". Poll with `gh run list/view -R GuangDai/Maccy`
  (runs ~11–12 min; the UI-test step is where it fails).
- The repo is `SWIFT_VERSION=5.0`, `SWIFT_STRICT_CONCURRENCY=minimal`. There is
  **no local Xcode** in the prior environment — all verification was via CI.

## OCR removal (done)
The Vision OCR image-title feature was removed (`ef95792`, code; `3c0ce8c`,
docs). `ImageProcessing` is now `thumbnail`/`preview` only. This is unrelated to
the crash but note it if touching `HistoryItem.generateTitle`/`ImageProcessing`.

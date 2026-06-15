# BS-2.4 UI crash retrospective — the concurrency phantom (2026-06-15)

> **Status:** RESOLVED. CI green at `66344e6` (run `27517644893`). The crash was **not** a
> concurrency bug. This doc records the real root causes, the Apple-doc grounding, the diagnostic
> failure mode of the first investigation, and the lessons that should guide the remaining roadmap
> (BS-2.6/2.7, BS-3+). Companion to `2026-06-15-bs2-ui-crash-handoff.md`.

## TL;DR

The BS-2.4 wiring (`Clipboard` → `BackgroundClipboardIngestor` actor → `StoreEvent` →
`History.consume`/`reconcileWithStore`) caused an **unsymbolicated UI-test crash** in `testClear`
("crashed in `<external symbol>`") and a timeout in `testCopyRTF`. The first investigation (Claude,
no Mac access) spent days on concurrency theories — `Sendable` capture, `MainActor.run` hop
overhead, actor isolation, even a `@ModelActor` migration — and could not converge without a
symbolicated stack.

GPT-5.5 fixed it in **5 small commits** (`341bca2` → `66344e6`). The actual causes were **three
independent state-consistency / ordering defects**, none of which involve thread safety:

1. **`togglePin` never persisted `pin`** → a predicate delete (`delete(model:where:)`) killed the
   pinned row in the store while the in-memory decorator survived holding a dangling `@Model` →
   crash when something re-fetched and walked it.
2. **`reconcileWithStore` rebuilt the list but never re-anchored `navigator.selection`** →
   selection pointed at an evicted decorator → `testCopyRTF` timeout.
3. **Unnecessary `Task { @MainActor }` wrappers around already-synchronous callbacks** → side
   effects landed a runloop turn after the test's assertion → flakes/timeouts.

What BS-2 actually did was **add a fresh-fetch-and-walk path** (`reconcileWithStore`) that
dereferenced state the old synchronous path had cached. That new path surfaced a latent
store/in-memory inconsistency that pre-BS-2 manifested only as **silent pin loss on next launch**,
never as a crash.

A four-agent analysis workflow (3 doc-grounded root-cause analyses + 1 adversarial verifier, all
high-confidence) confirmed `correct_and_complete` and independently surfaced the same completeness
gaps.

---

## The three defects

### Defect 1 — Pin not persisted → predicate delete killed the pinned row (`testClear` crash)

**The mechanism.** `HistoryItemDecorator.togglePin()` set `item.pin` **in-memory only**; the
pre-fix `History.togglePin` (History.swift:610) updated `item.item.pin` and re-sorted, with **no
`save()`**. So when `clear()` (History.swift:395) ran `persistence.deleteUnpinned()`, the
`#Predicate { $0.pin == nil }` inside `delete(model:where:)` was evaluated against the **committed
store state** — where `pin` was still `nil` — and the just-pinned row was deleted from the store.

Meanwhile `clear()` then checks the **in-memory** decorator: `all.forEach { if item.isUnpinned {
cleanup(item) } }`. The in-memory `pin` *was* set, so the decorator survived in `all[]` holding a
**dangling reference** to the store-deleted `@Model`.

```swift
// History.swift — deleteUnpinned (SwiftDataHistoryPersistence): the predicate delete
func deleteUnpinned() throws {
  try Storage.shared.context.transaction {
    try Storage.shared.context.delete(model: HistoryItem.self,
                                       where: #Predicate { $0.pin == nil })  // ← committed store state
    ...
  }
  Storage.shared.context.processPendingChanges()
  try Storage.shared.context.save()
}

// History.swift — clear(): dual source of truth (store predicate vs in-memory decorator pin)
func clear() {
  try persistence.deleteUnpinned()                              // deletes STORE rows where pin==nil
  all.forEach { item in if item.isUnpinned { cleanup(item) } }  // checks IN-MEMORY pin
  all.removeAll(where: \.isUnpinned)                             // in-memory pin
  ...
}
```

**Why it crashed under BS-2 but not before.** Pre-BS-2, nothing re-fetched and walked the dangling
model — `load()` (app restart) just found the pinned row absent from the store (silent data loss),
and `findSimilarItem()`'s fetch never re-touched the stale decorator. BS-2's **new**
`reconcileWithStore()` (History.swift:291) does `Storage.shared.context.fetch(...)` and walks every
fetched `@Model` by `persistentModelID`, reusing decorators — re-touching the deleted object
tripped SwiftData's **fault-on-deleted-object trap** = "crashed in `<external symbol>`".

**The fix** (History.swift:610–621): `togglePin` now does `try persistence.save()` (which calls
`processPendingChanges()` + `save()`) right after toggling, **rolling back the in-memory `pin` on
failure**. `HistoryPersistence` gained `func save() throws`. Regression test:
`HistoryPinPersistenceTests.testClearingUnpinnedAfterPinPersistsPinnedItem`.

#### The decisive SwiftData asymmetry (Apple docs)

A single `ModelContext` holds **two representations** of the same data, and different APIs consult
different ones:

| API | Reads which state? |
|-----|--------------------|
| `FetchDescriptor.fetch` (`includePendingChanges` defaults to **`true`**) | pending in-memory mutations |
| `ModelContext.delete(model:where:)` — "Removes each model satisfying the given predicate **from the persistent storage during the next save operation**" | **committed store state** |
| `ModelContext.save()` — "Writes any pending inserts, changes, and deletes to the persistent storage" | flushes pending → committed |
| `ModelContext.processPendingChanges()` | "Forces the context to process changes to the object graph" (coalesces pending) |
| `ModelContext` overview — "any changes … exist only in memory until the context writes them to the persistent storage or `save()` is invoked" | confirms in-memory edits are invisible to store-level ops until saved |

> Citations: `/documentation/swiftdata/fetchdescriptor/includependingchanges`,
> `/documentation/swiftdata/modelcontext/delete(model:where:includesubclasses:)`,
> `/documentation/swiftdata/modelcontext/save()`,
> `/documentation/swiftdata/modelcontext/processpendingchanges()`, `/documentation/swiftdata/modelcontext`.

**The rule:** before any predicate-based delete/batch op, `save()` any mutation to a field that
predicate reads. `processPendingChanges()` alone is **not** a substitute for `save()` in this role.

---

### Defect 2 — Selection cache not re-anchored after reconcile (`testCopyRTF` timeout)

`reconcileWithStore()` rebuilt `all[]` from a fresh fetch and called `refreshVisibleItems()`, but
**never touched `AppState.shared.navigator.selection`**. `NavigationManager.selection` is a
reference-derived cache in a *separate* `@Observable` object (`NavigationManager`) from the one
being mutated (`History`). Observation propagates property writes, not referential consistency
between two models — so mutating `History.all/items` does **not** invalidate
`NavigationManager.selection`. After a merge/append, the navigator still held a decorator whose
`id` was no longer in `items`; `highlightNext()`/`highlightPrevious()` resolve `leadSelection` →
`history.firstVisibleItem(where: { $0.id == lead })` → miss → the arrow key became a no-op → Enter
never selected "bar" → timeout.

**The fix** (History.swift:319–321 + Popup.swift:75–79): after `refreshVisibleItems()`, when
`searchQuery.isEmpty && !isMultiSelectInProgress`, re-select `unpinnedItems.first ??
pinnedItems.first`; `Popup.open` does the same so an opened list always has a valid lead. Regression
tests: `HistoryConsumeTests.testConsumeAddedSelectsNewestItemWhenNotSearching`,
`PopupTests.testOpenSelectsNewestHistoryItem`.

**Principle:** "rebuild collection" and "re-anchor selection" are **one atomic UI operation**.
Gate the re-anchor so it doesn't fight higher-priority user intents (active search, in-progress
multi-select). (Grounding: `/documentation/observation/observable()`; WWDC21 Session 10022
*Demystify SwiftUI* — a selection held past the lifetime of its backing data is a lifetime
violation.)

---

### Defect 3 — Unnecessary async hops → test-assertion timing (flakes/timeouts)

Four sub-changes in `341bca2` / `66344e6`, none a data race:

1. **`AppDelegate` distributed-notification observers** (`queue:.main`): `Task { @MainActor in … }`
   → `MainActor.assumeIsolated { … }`. The `queue:.main` block is already delivered on the main
   thread (`OperationQueue.main` "executes those operations in the run loop common modes";
   `DistributedNotificationCenter` "always delivered to the main thread"). Wrapping in an
   unstructured `Task` enqueues a **second** deferred hop onto the MainActor's serial executor for a
   *later runloop turn* — so the test's post-notification-then-assert window saw no side effect.
   `assumeIsolated` runs **synchronously inline** and traps if the assumption is violated (a
   self-checking contract). Apple: *"can only be used from synchronous functions, as asynchronous
   functions should instead perform a normal method call to the actor."*
2. **`HistoryItemView.onTapGesture`**: `Task { history.select(item) }` → `history.select(item)`.
   SwiftUI `View` bodies and modifier closures are `@MainActor` by default (WWDC25 Session 266:
   *"SwiftUI provides synchronous callbacks by default"*); the `Task` added an unnecessary
   **suspension point** that deferred selection (and the downstream `popup.close()`/`copy`/`paste`)
   past the assertion.
3. **`Clipboard.checkForChangesInPasteboard`**: `Task { await ingestor?.ingest(request) }` →
   `guard let ingestor else { return }; Task { await ingestor.ingest(request) }`. Early-returns
   avoid a spurious `Task` when `ingestor == nil` (the legacy-test path), and capturing the
   `Sendable` ingestor local is cleaner than optional-chaining off non-`Sendable` `self`.
4. **`BackgroundClipboardIngestor.ingest`**: moved `ingestConfig()` and the `Defaults[.size]` read
   **inside** the single `MainActor.run` block, threading `historyLimit` (an `Int`) into
   `commit(item,deleting:limit:)`. **Snapshot all main-actor/global shared state in ONE hop, pass
   pure `Sendable` values across** — never re-read shared state (`Defaults`, in-memory caches) from
   off-main code; `SWIFT_STRICT_CONCURRENCY=minimal` will never catch the race.

> Citations: `/documentation/swift/mainactor/assumeisolated(_:file:line:)`,
> `/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:)`,
> `/documentation/foundation/operationqueue/main`, `/documentation/foundation/distributednotificationcenter`,
> WWDC25 Session 266 *Explore concurrency in SwiftUI*.

**The sharpest framing:** *"runs on the main thread"* does **not** imply *"synchronously inside this
callback."* A `queue:.main` block is a run-loop operation (deferred); `Task { @MainActor }`
compounds a second deferred hop. This is a **timing/ordering** bug, not a data race — invisible to
minimal strict-concurrency checking and silent at runtime until a test asserts too early.

---

## Why the first (concurrency) investigation failed — the diagnostic lesson

This is the most important section for future work, and it is written honestly.

1. **Anchoring bias.** The crash surfaced *exactly* when BS-2 introduced a background ingest actor
   and a cross-context event handoff, so the investigation locked onto actor isolation / `Sendable` /
   `MainActor.run` overhead. The actual defect is a **single-context, single-thread, synchronous
   data-integrity bug** that reproduces identically on a fully `@MainActor` codebase. The
   concurrency lens was *invisible* to it.
2. **Diagnosed the WHERE, not the WHAT.** The investigation asked "which thread/isolation touched
   this?" instead of "**what** object is being touched, and **in what state**?" The answer — a
   dangling `@Model` reference left by a store/in-memory divergence — had nothing to do with
   threads.
3. **No symbolicated stack.** Without a Mac, the crash was "crashed in `<external symbol>`" —
   indistinguishable from an actor-runtime trap. A single symbolicated frame (`xcrun xcresulttool`
   on the `.xcresult`) would have named the SwiftData fault accessor and collapsed days of
   theorizing. **A symbolicated stack is a prerequisite for crash diagnosis, not an optimization.**
4. **A new re-read path surfaces latent caching bugs.** BS-2 didn't *create* the pin bug — it added
   `reconcileWithStore`, a fresh-fetch-and-walk that dereferences state the old synchronous path
   had cached. **Any refactor that adds a code path re-reading state the old path cached will
   surface every latent inconsistency the caching hid.** Pre-BS-2 this bug was *silent pin loss on
   next launch*, not a crash — verified against baseline `6528bd8` (its `togglePin` also had no
   `save()`, its `clear()` used the identical predicate delete).
5. **The dual source of truth hid the deletion from the eye.** `clear()` has a store predicate
   (`pin == nil`) *and* an in-memory pass (`item.isUnpinned`); they superficially agree, so the
   row vanishing from the store while its decorator survives in `all[]` is invisible until a
   re-fetch faults it.

---

## Completeness gaps & residual risks (for the remaining roadmap)

The fix is `correct_and_complete` for the *reported* failures, but the workflow surfaced latent
patterns to harden during BS-2.6/2.7 and beyond:

- **`mergeDuplicateIfNeeded` (History.swift:327–353)** and **`updateTitle` (History.swift:721–723)**
  mutate `@Model` fields (`pin`, `numberOfCopies`, `title`, `contents`) **without `save()`** — the
  same pattern as pre-fix `togglePin`. Benign today (no predicate filters by those fields), but any
  future predicate delete/read on them reintroduces the class of bug.
- **`BackgroundClipboardIngestor.commit` (ClipboardIngestor.swift:248–272)** has a **second,
  independent** `#Predicate { $0.pin == nil }` delete inside the actor's background-context
  transaction. Correct today (single-transaction; no pending pin mutation on a registered model at
  predicate time), but it's a parallel implementation with **no shared helper** and no test for the
  "actor trims while a pin toggle is mid-save on the main context" interleaving.
- **No unit test exercises the actual crash path** (`togglePin → clear → reconcileWithStore`).
  `HistoryPinPersistenceTests` covers `togglePin → clear → survives` but not the post-clear
  reconcile dereference. A regression that reintroduces a dangling decorator would **pass the unit
  test and crash the UI test**, exactly as the original bug did.
- **`clear()`'s dual source of truth is not removed** — only made consistent for `pin`. Any future
  caller that mutates `item.item.pin` without going through `togglePin` (debug tool, AppleScript
  bridge, an "unpin all") re-opens the divergence.
- **Re-select-on-every-reconcile** snaps selection back to the top if a background copy lands while
  the popup is open and the user has arrowed down. This is **parity with pre-BS-2** (the old
  synchronous `add()` always left the newest item selected), so it is not a new regression — but it
  is observable and untested.
- **`!isMultiSelectInProgress` guard's multi-select branch is dead** today
  (`multiSelectionEnabled` hard-coded `false`); if PasteStack/multi-select is re-enabled, the guard
  must be re-validated against the real state machine.
- **`processPendingChanges()` is documented primarily as an undo-manager coalescing hook**, not as
  a guaranteed flush that a batch-delete consults. The fix relies on the empirical SwiftData/Core
  Data behavior that `processPendingChanges()` + `save()` makes the pin edit visible to the
  predicate; Apple docs only state `delete(model:where:)` matches "the persistent storage". If a
  future SwiftData version batches predicate evaluation differently, this could regress — so the
  unit-level regression test for the full sequence matters.

**Recommended hardening (future step, not in scope now):**
1. Add a unit test asserting `togglePin → clear → reconcileWithStore` does not fault (the real
   crash path).
2. Centralize the "predicate-by-pin delete" behind one helper used by both `deleteUnpinned` and the
   actor's `commit` trim, with a documented invariant.
3. Add an audit comment at every `@Model` mutation site naming whether it `save()`s and why/why-not.

---

## Lessons for continued development

1. **SwiftData has two representations inside one `ModelContext`.** `fetch` honors pending changes
   (`includePendingChanges` defaults `true`); `delete(model:where:)` matches committed store state.
   Before any predicate-based delete/batch op, `save()` the mutation to any field that predicate
   reads. `processPendingChanges()` is not a substitute for `save()` here.
2. **A crash that appears with a new actor/cross-context handoff is not necessarily a concurrency
   bug.** A refactor that adds a fresh-fetch/re-read path will surface every latent
   store/cache inconsistency the old path hid. Diagnose the **WHAT** (object + state) before the
   **WHERE** (thread/isolation). **Get a symbolicated stack first.**
3. **Don't `Task`-wrap already-isolated synchronous callbacks.** SwiftUI `View`/modifier closures
   are `@MainActor` by default; a `queue:.main` notification block already runs on the main thread
   (as a run-loop operation). `Task { @MainActor }` adds a deferred hop even on the same executor.
   Use `MainActor.assumeIsolated` (or call the `@MainActor` method directly) for synchronous inline
   execution. *"Runs on the main thread" ≠ "synchronously inside this callback."*
4. **"Rebuild collection" and "re-anchor selection" are one atomic UI operation.** Any UI-derived
   selection cache held separately from the data model (by object identity/UUID) goes stale the
   instant the model recycles those objects; re-derive it whenever the collection is rebuilt from a
   new fetch, gated against higher-priority user intents (search, multi-select).
5. **Snapshot all main-actor/global shared state in ONE `MainActor.run` hop at an actor boundary,
   then pass pure `Sendable` values across.** Never re-read shared state (`Defaults`, in-memory
   caches) from off-main code; minimal strict concurrency won't catch it.
6. **The deeper invariant — "any `@Model` mutation that participates in a future predicate must be
   saved before that predicate runs" — is not enforced structurally.** `togglePin` is patched;
   `mergeDuplicateIfNeeded`/`updateTitle` are latent. Encode it with a helper + an audit comment +
   a full-sequence regression test, not just a happy-path unit test.

---

## Artifacts

- Fix commits: `341bca2` `3730bf1` `e4604c3` `d416e7e` `66344e6` (all `bs2.4`).
- CI: run `27517644893` (green). Previous red run with the crash: `27515062440`.
- Analysis workflow: 4 agents (3 doc-grounded root-cause analyses + 1 adversarial verifier),
  ~248k tokens, 104 tool calls, all high-confidence `correct_and_complete`.
- Handoff (resolved): `2026-06-15-bs2-ui-crash-handoff.md`.

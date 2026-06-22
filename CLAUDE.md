# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Maccy is a lightweight macOS clipboard manager (AppKit + SwiftUI + SwiftData). It targets macOS Sonoma 14+ (`MACOSX_DEPLOYMENT_TARGET = 14.0`), builds with `SWIFT_VERSION = 5.0` and `SWIFT_STRICT_CONCURRENCY` unset (defaults to minimal). There is a C++/ObjC++ interop layer in `Maccy/Processor/` (UTF-8 prefix validation, FNV-1a fingerprint hashing) bridged via ObjC++.

## CRITICAL: a staged performance roadmap is mid-execution

**Read `AGENTS.md` before changing anything.** The repository is in the middle of a carefully ordered performance/concurrency refactor defined in `docs/audit/2026-06-14/roadmap/`. The audit (`00-overview.md`) traced essentially all UI jank to a single root cause: *the entire data pipeline is `@MainActor`-isolated and uses only `container.mainContext`* — no background context, no actor, no heavy work off the main thread.

- Baseline commit (pre-roadmap): `6528bd8ad18a39f44fd03128f3384b708f580b85`
- Source of truth: `docs/audit/2026-06-14/roadmap/` (big steps BS-0 → BS-8, executed in dependency order)
- High-level summary: `docs/audit/2026-06-14/09-roadmap.md`
- Architecture / data flow / DTO boundaries: `roadmap/A-architecture-target.md`; test facilities: `roadmap/B-test-strategy.md`; complexity & I/O budgets: `roadmap/C-complexity-and-limits.md`
- **Current position: BS-1 (concurrency scaffolding) is implemented; small steps `bs1.1`–`bs1.8` are committed. Next is `bs1.9` (BS-1 verification gate), after which BS-2 (ingest → actor) begins the actual wiring.**

Execution rules (from `AGENTS.md` — follow them):
- Work one small roadmap step at a time. Use TDD for behavior changes (failing test first, then minimal correct change, then run the focused test). Keep edits scoped to the current step and its tests.
- A **big step (BS-x)** is a *compile boundary*: after its last small step, `xcodebuild build` must pass and existing tests must stay green. A **small step** may temporarily fail to compile, but only within its big step.
- Commit after every small step; message must name the roadmap item (`feat(bsX.Y): ...` / `fix(bsX.Y): ...` / `docs(bsX.Y): ...`). Push only after a big step passes its build+test gates.
- Do not change user-visible behavior unless the roadmap requires it. Record any deviation in the audit docs before committing. Prefer existing project patterns over new abstractions.

## Build, lint, test — there is NO local environment

This machine has no Xcode / macOS toolchain. **Do not build, run tests, or run `swiftlint` locally — none of it will work.** All building, linting, and testing happens on the GitHub Actions runner (macOS 26 / arm64). You drive it through `gh`, then poll for the result.

The workflow is `.github/workflows/macos26-arm-ci.yml` (workflow name: **"macOS 26 ARM CI"**). It triggers automatically on push/PR to `master`, and supports `workflow_dispatch` for manual runs on any branch:

```sh
# Trigger a run on the current branch
gh workflow run "macOS 26 ARM CI" --ref "$(git rev-parse --abbrev-ref HEAD)"

# List recent runs (note the run id / database id of the one you care about)
gh run list --workflow "macOS 26 ARM CI" --limit 5

# Check a run's status non-interactively (use this to poll)
gh run view <run-id>
gh run view --workflow "macOS 26 ARM CI"     # most recent run
```

**Polling rule (important):** a CI run takes **~11 minutes** end-to-end. When a run is still in progress, **re-check no more often than every 2 minutes** — never high-frequency poll, and don't use `gh run watch` for tight polling. Get the status once; if it isn't finished, wait at least 2 minutes before the next check.

**Investigating a failed run — do this, in this order (learned the hard way):**

1. **Status first, not the log.** A run is a *matrix* of jobs: `Lint + diagnostics`, then shards (`unit`, `ui-1..5`, `perf-text`/`perf-image`/`perf-mixed`). "Run failed" tells you nothing — find *which* job(s) failed:
   ```sh
   gh run view <run-id> --json jobs -q '.jobs[] | "\(.name): \(.conclusion)"'
   ```
   Two very different signals: `Lint + diagnostics` failed (→ all shards `skipped`; it's a SwiftLint/build error in *your* change, always real) vs. one shard failed while the rest passed (often a contention flake).
2. **Read the failed job's log from the END.** `gh run view --job=<job-id> --log` dumps the whole build; the **head is noise** (checkout, `brew install swiftlint`, `Compiling …`, `RegisterExecutionPolicyException`, framework bottles). The actual failure — the `error:`/`XCTAssert … failed` line, `** TEST FAILED **`, the `Failing tests:` block, or a crash signature — is in the **last few dozen lines**. Tail it (`| tail -n 60`) or grep the tail. **Don't grep the whole log blind** — `RegisterExecutionPolicyException` and `relative standard deviation` lines will drown the signal (and note `grep -E ".*"` patterns containing `**` are invalid regex).
3. **Distinguish flake from real failure before rerunning.** Known runner-contention flakes (logic-verified — don't loop reruns): 3 s async-wait timeouts on `testCopy*`/`testClear`/`testPin` on contended UI shards; perf `measure{}` RSD>10 % on sub-millisecond micro-benchmarks. A *real* failure leaves a concrete `error:`/assertion/crash in the tail (e.g. SwiftData `fatal logic error in DefaultStore … PersistentIdentifier remapped to a temporary identifier during save` — that one aborts the whole test class, so every test in the class shows as failed, including ones that never ran).

**The runner is the gate of truth for the roadmap's verification gates.** A green run is the only acceptable evidence a step passed: the workflow's final step greps every log (`swiftlint.log`, `build.log`, `unit-tests.log`, `ui-tests.log`) for `warning:` / `error:` / `TEST FAILED` and fails the run on any hit — compiler warnings and stray log lines are CI failures, not nitpicks.

What the runner executes (reference only — do not run locally): SwiftLint (`swiftlint lint --quiet --strict --no-cache`), then `xcodebuild` clean build, then unit tests (`-only-testing:MaccyTests`), then UI tests (`-only-testing:MaccyUITests`), all with `-project Maccy.xcodeproj -scheme Maccy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`. To run a narrower test on the runner, push a temporary commit that passes `-only-testing:MaccyTests/<Class>[/<method>]` rather than trying to run it locally.

`enable-testing` (injected by `Maccy.xctestplan`) forces `Storage` to an in-memory SwiftData store and gates several paths (`AppDelegate`, `Notifier`, `HistoryItem`) — so test-run behavior differs from the shipped app.

Release packaging: `scripts/package-app.sh` (Release build → zips `Maccy.app` → emits `.sha256`); driven by `.github/workflows/release.yml` on version tags.

## Architecture

### Current pipeline (the root cause being fixed)
`Storage` (`Maccy/Storage.swift`) is `@MainActor`; `Storage.shared.context` is `container.mainContext` — the only context in the app. The pasteboard poll timer in `Clipboard.swift` fires on the main actor; `History` (`Maccy/Observables/History.swift`) does fetch + `sorter.sort` + decorate-all on `load()` (~`History.swift:193`), a full-table `findSimilarItem()` dedup on every copy (~`:562`), and a whole-table re-sort on every insert (~`:258`/`:299`) — all synchronous on the main thread. `NSImage(data:)` decode, `resized()` via `draw()`, and Vision OCR also run on main. The full bottleneck map is in `00-overview.md`.

### Target isolation model (what BS-2→8 builds toward)
Two domains: **Main** (SwiftUI views + thin `@Observable` view models + lightweight `mainContext` reads of the visible window) and **Background actors** (`ClipboardIngestor` reads the pasteboard, parses rich text, dedups via a signature index, writes a single transaction to a background context, then emits a `StoreEvent`; `ImageProcessor` downsamples/decodes/runs OCR). The domains communicate only via **Sendable value types (DTOs)** — `@Model HistoryItem` never crosses an actor boundary. Detail in `A-architecture-target.md`.

### Scaffolding already landed by BS-1 (present but NOT yet wired)
These new files define the target shape but are **not yet connected** to `Clipboard`/`History` — wiring happens in BS-2. Don't assume they are called anywhere; that is intentional, not dead code:
- `Maccy/Ingest/Dtos.swift` — Sendable DTOs (`ContentDTO`, `ClipboardItemDTO`, `PasteboardSource`, `SignatureDTO`/`ContentSignatureEntry`, `MaccyFingerprint`, `ItemSnapshotDTO`, `StoreEvent`, `IngestRequest`/`IngestPlan`/`IngestResult`) plus projection functions `snapshot(of:)` / `contentDTOs(of:)`.
- `Maccy/Ingest/SignatureIndex.swift` — pure-value in-memory dedup index (`[SignatureDTO: ItemID]`).
- `Maccy/Ingest/ClipboardIngestor.swift` — `protocol ClipboardIngestor` + `MainActorIngestorAdapter` (bridges existing `History.shared.add` byte-for-byte; behavior unchanged until BS-2).
- `Maccy/ImageProcessing/ImageProcessing.swift` — `protocol ImageProcessing` + `PassthroughImageProcessor` (wraps the existing `NSImage(data:)` path; replaced by ImageIO downsampling in BS-3).
- `Maccy/Persistence/Storage+Background.swift` — `Storage.newBackgroundContext()`.

### Test infrastructure
Unit/integration tests in `MaccyTests/`, UI tests in `MaccyUITests/`. Test doubles and fixtures live in `MaccyTests/Support/` (`PasteboardSimulator`, `HistoryBuilder`, `FakeClock`, `IngestorSpy`, `FixtureLoader`, `MainThreadProbe`) — specified in `B-test-strategy.md`. `heavy_text.txt` at the repo root is the large-text fixture (≈31 KB) loaded by `FixtureLoader`. A `MaccyPerformanceTests` target for the performance gates (`B-test-strategy.md §4`) is planned but not yet created.

### Other key pieces
- Dedup fingerprints + UTF-8 validation: C++/ObjC++ in `Maccy/Processor/` (current hash is FNV-1a; BS-8 plans xxh3 + a persistent `fingerprint` column on `HistoryItemContent`).
- Translations: per-language `*.lproj/` directories, managed via BartyCrouch (`.bartycrouch.toml`) and Weblate — do not hand-edit locale strings.
- User-facing defaults: `defaults write org.p0deje.Maccy ...` keys (`ignoreEvents`, `clipboardCheckInterval`, `showFooter`, …) — see README "Advanced".

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Maccy is a lightweight macOS clipboard manager (AppKit + SwiftUI + SwiftData). It targets macOS Sonoma 14+ (`MACOSX_DEPLOYMENT_TARGET = 14.0`) and builds with **Swift 6.0** in **complete** strict-concurrency mode (`SWIFT_STRICT_CONCURRENCY = complete`). A C++/ObjC++ interop layer in `Maccy/Processor/` (UTF-8 prefix validation, **xxh3** dedup fingerprinting via vendored xxHash) is bridged through ObjC++; the legacy FNV-1a hash is retained but superseded.

## Performance/concurrency refactor status

A staged performance roadmap (`docs/audit/2026-06-14/roadmap/`, big steps BS-0 → BS-8) has been **fully committed and is CI-green**, but **none of BS-5/6/7/8 is finished to its own spec**. CI green ≠ spec complete. The authoritative status:

- **Roadmap completion** → `docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md` — BS-5 2/13, BS-6 5/12, BS-7 13/17, BS-8 4/8 (per-step gaps in `01`–`04`).
- **Architecture & root causes** → `docs/audit/architecture-and-root-causes.md` — the single current-architecture reference (data flow, residual issues, finding-id glossary).
- **Memory** → `docs/audit/2026-06-27-memory-floor-and-retention/` — framework floor ~62 MB; 100 MB unreachable (window-open ~110–130 MB is framework cost).
- **Spec-of-record (frozen design intent)** → `docs/audit/2026-06-14/roadmap/` (README + A/B/C + step-0..8); the spec each step is measured against. Small-step checkboxes are intentionally unchecked.
- **Navigation** → `docs/audit/INDEX.md` — read this first before any audit doc.

Landed highlights: off-main ingest via `actor ClipboardIngestor` (+ background context + `StoreEvent`), off-main image decode via `actor ImageProcessor`/`actor ThumbnailCache` (ImageIO downsampling), off-main search via `actor SearchActor`, persistent `HistoryItemContent.fingerprint` column (xxh3), incremental per-copy reconcile (4.4a). Vision OCR has been removed.

Execution rules when resuming roadmap work:
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

### Two-domain isolation model
The data pipeline is split across two domains that communicate **only via Sendable value types (DTOs)** — a `@Model` (`HistoryItem`/`HistoryItemContent`) never crosses an actor boundary:

- **Main** — SwiftUI views + thin `@Observable` view models (`History`, `HistoryItemDecorator`, `AppState`, …) + lightweight `mainContext` reads of the visible window. All `@MainActor`.
- **Background actors** — `ClipboardIngestor` reads the pasteboard, parses rich text, dedups via a per-entry containment `SignatureIndex`, writes a single transaction to a background context, then emits a `StoreEvent`; `ImageProcessor`/`ThumbnailCache` downsample/decode; `SearchActor` runs the 4-mode text match. `History.consume`/`reconcileWithStore` apply the event on main (4.4a: incremental via `model(for:)` + binary insert, full reconcile as fallback).

`Storage` (`Maccy/Storage.swift`) is `@MainActor`; `Storage.shared.context` is `container.mainContext`, and `Storage.newBackgroundContext()` (`Maccy/Persistence/Storage+Background.swift`) is the background context the ingest actor writes to. Detail in `docs/audit/architecture-and-root-causes.md` and the frozen target `docs/audit/2026-06-14/roadmap/A-architecture-target.md`.

### Test infrastructure
Unit/integration tests in `MaccyTests/`, UI tests in `MaccyUITests/`. Test doubles and fixtures live in `MaccyTests/Support/` (`PasteboardSimulator`, `HistoryBuilder`, `FakeClock`, `IngestorSpy`, `FixtureLoader`, `MainThreadProbe`) — specified in `docs/audit/2026-06-14/roadmap/B-test-strategy.md`. Test fixtures (e.g. `heavy_text.txt` ≈31 KB large-text fixture, `guy.jpeg`) live in `MaccyTests/Fixtures/` and are loaded by `FixtureLoader` via `#filePath`-relative paths. A `MaccyPerformanceTests` target for the performance gates (`B-test-strategy.md §4`) is planned but not yet created.

### Other key pieces
- Dedup fingerprints + UTF-8 validation: C++/ObjC++ in `Maccy/Processor/` — **xxh3** is the live hash; the persistent `HistoryItemContent.fingerprint` column (lightweight SwiftData migration) caches it. (Caveat per the 06-28 audit: the lazy write-back backfill for pre-existing rows is not yet implemented — old rows re-hash on read.)
- Translations: per-language `*.lproj/` directories, managed via BartyCrouch (`.bartycrouch.toml`) and Weblate — do not hand-edit locale strings.
- User-facing defaults: `defaults write org.p0deje.Maccy ...` keys (`ignoreEvents`, `clipboardCheckInterval`, `showFooter`, …) — see README "Advanced".

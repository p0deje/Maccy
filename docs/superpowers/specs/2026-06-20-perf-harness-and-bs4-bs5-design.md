# Performance Harness + BS-4 + BS-5 — Design Spec

- **Date:** 2026-06-20
- **Status:** Approved (design); spec pending implementation
- **Author:** session 97591b95
- **Relates to:** `docs/audit/2026-06-14/roadmap/step-4-data-pipeline.md`, `step-5-text-search.md`, `B-test-strategy.md` §4, `C-complexity-and-limits.md`
- **Supersedes:** none (first spec for the `MaccyPerformanceTests` gate vehicle)

## 1. Goal

Deliver the measurement vehicle the roadmap's performance gates require, then use it to prove the wins from BS-4 (data-pipeline acceleration) and BS-5 (search → background actor). Concretely:

1. Build the **`MaccyPerformanceTests`** target (planned in `B §4`, not yet created) with a real-image fixture corpus and a six-scenario benchmark suite.
2. Capture a **pre-BS-4 baseline** on CI.
3. Implement **BS-4** (9 small steps), re-measuring at its `4.9` gate.
4. Implement **BS-5** (13 small steps), re-measuring at its `5.13` gate (`G-search`).

The hard environment constraint (CLAUDE.md): **no local Xcode/macOS toolchain.** Every build/lint/test/measurement runs on the GitHub Actions macOS 26 ARM runner (~11 min/run), which is **headless and GPU-less**. Design choices flow from that.

## 2. Scope & sequencing

Three subsystems, executed in this order:

| # | Subsystem | What | Why this order |
|---|---|---|---|
| **B** | `MaccyPerformanceTests` target + runner-side `ImageFixtureGenerator` | New Xcode target, xctestplan entry, CI wiring | The gate vehicle; without it BS-4/5 wins are unmeasurable |
| **C** | Six-scenario benchmark suite + UI render smoke | `measure{}` benchmarks + a non-blocking UI hover/select smoke | Delivers the explicit benchmark ask; establishes baseline |
| **A** | BS-4 → BS-5 | The roadmap refactor (see §10, §11) | Re-measured against the baseline at each gate |

User directives folded in:
- **N ∈ {20, 50, 100, 200}** — 200 is the actual default cap (`Defaults.Keys+Names.swift:66`: `Key<Int>("historySize", default: 200)`). The roadmap's "history=1000" was hypothetical; real worst case is 200.
- **Fixtures generated entirely on the runner** (user has no local Mac): download real CC0 photos at test-time + crop on-runner; commit only generator code, no binaries.
- **Measurement = decode/decorate path as hard gate + UI hover/select smoke** (non-blocking).
- **5-runner matrix, hard-capped at 5 concurrent macOS** via `max-parallel: 5`.

## 3. Non-goals / deferred

- **Build-once + `.xctestrun` distribution.** Known xcodebuild quirk (`test-without-building` ignores the test plan; `enable-testing` forces the in-memory store via the plan). Risk of silently running against the on-disk store outweighs the saved compile on a public repo (compute is free). Deferred; revisit only with a test asserting `enable-testing` is active under `test-without-building`.
- **Real-image fixtures committed to git.** Runner-time generation only (§5).
- **Metal/MPS HDR pipeline.** Evaluated and declined (BS-3 retrospective); out of scope.
- **BS-6/7/8.** This spec covers BS-4 + BS-5 only.
- **Sharding the unit-test target.** `MaccyTests` is fast; only `MaccyUITests` (36 methods, slow) and the new perf target are sharded.

## 4. Subsystem B — perf tests as classes in `MaccyTests` (DEVIATION from `B §4`)

> **Deviation from `B §4` (recorded):** the roadmap specifies a *separate* `MaccyPerformanceTests` target. We instead put perf tests as **classes inside the existing `MaccyTests` target**, run in a non-blocking CI shard via `-only-testing:`, with the blocking unit shard excluding them via `-skip-testing:`. **Why:** this machine has no local Xcode, so a new target = blind, ~12-point `project.pbxproj` surgery (NativeTarget + 3 build phases + config list + 2 configs + target dependency + proxy + product ref + group + project `targets`/`TargetAttributes`) with no validation until a ~11-min CI run — likely several failed rounds. Extending `MaccyTests` needs only the well-trodden 4-place source-file registration (PBXBuildFile, PBXFileReference, group child, Sources phase), which is reliable blind. There is already precedent: `MaccyTests/HistoryItemPerformanceTests.swift` is an existing `measure{}` perf test. The function `B §4` requires — perf runs non-blocking, separate from the gate — is fully preserved by the shard split. Cost: a stable ~7-entry skip-list in the unit shard + matching only-list in the perf shard (documented in the workflow).

Perf test classes live flat in `MaccyTests/` (matching the existing `HistoryItemPerformanceTests.swift` placement):
- `MaccyTests/ImageFixtureGenerator.swift` — see §5.
- `MaccyTests/PerfHistoryFactory.swift` — wraps `HistoryBuilder` to compose the six scenario histories (items × content type × N) and inject them into an in-memory `History`.
- `MaccyTests/PerformanceTestCase.swift` — shared `XCTestCase` base (in-memory store via `enable-testing`, fixture cache dir, `MainThreadProbe`).
- `MaccyTests/ImageDecodePerformanceTests.swift`, `MaccyTests/TextSearchPerformanceTests.swift` — the scenario benchmarks.
- Reuse `MainThreadProbe` (`MaccyTests/Support/MainThreadProbe.swift`: `@MainActor`, `start()/stop()`, `maxGap: TimeInterval`) and `FixtureLoader` (`heavyTextURL`, `imageData`).
- The existing `MaccyTests/HistoryItemPerformanceTests.swift` stays (it benchmarks the signature path — relevant to BS-4's `bytesHashed` gate).

**First commit = a single trivial green perf class** registered in `MaccyTests`, run in a non-blocking CI step, to confirm the wiring before any benchmark logic is added.

## 5. Fixture corpus — runner-side, real photos, exact size distribution

`ImageFixtureGenerator` (Swift; CoreGraphics + ImageIO) runs at test setup on the macOS runner:

1. **Source photos from the internet** (honoring the "from the internet" intent): `URLSession` downloads a handful of CC0 photos (picsum.photos / Wikimedia Commons) with retries. The runner has internet.
2. **Synthetic fallback**: if download fails (network flake), generate realistic photos via CoreGraphics (gradient + Perlin-ish noise + shapes) so the suite never hard-fails on network. The fallback is clearly logged.
3. **Crop/scale into the size distribution {≈10, 5, 2, 1, 0.5 MB}** by varying (a) source, (b) crop rect, (c) output dimensions, (d) JPEG quality. A **quality/dimension loop** targets the exact byte count per bucket. A **seeded RNG** (`SystemRandomNumberGenerator` seeded by a fixed value, or a `SplitMix64`) makes crop rects deterministic and reproducible run-to-run.
4. **"Many images"** comes from varying crops across sources → a corpus of dozens spanning the size range, per the user's "在不同的剪切，生成大量的图片."
5. **Cache** generated fixtures in a temp dir keyed by a content hash, so repeat runs within one CI job don't regenerate.

Nothing binary is committed — only `ImageFixtureGenerator.swift`. This satisfies both "from the internet" and "全部在 Runner 上, 不要在本地."

Why real photos (not pure synthetic): flat synthetic images compress to tiny bytes and decode trivially, so they don't stress the ImageIO downsample/decode path that BS-3 changed. Real photo data (high-frequency detail) is what makes the decode-cost measurement meaningful.

## 6. Subsystem C — six scenarios × metrics + UI smoke

For each scenario, build a history via `PerfHistoryFactory` and measure four things:
- **Cold load → first frame** — `History.load()` (the `G-popup-open` analog).
- **Per-item decode/decorate** — the "pointer → candidate → render" analog: `HistoryItemDecorator.ensureThumbnailImage` / `ImageProcessor.thumbnail` as items enter the visible window (the path BS-3 changed, BS-4's load exercises). This is measured directly on the decorator/processor, **not** via a UI hover, for the hard gate (stability; see §7).
- **Per-key search** — `G-search` analog (post-BS-5 it's the actor path; pre-BS-5 it measures the current sync search as the baseline).
- **Main-thread occupancy** — `MainThreadProbe.maxGap` throughout each measured region (gate threshold: no gap > 16 ms).

`measure{}` reports total/average/stddev over its iterations; per-item time = total/count, additionally tagged with `OSSignposter` intervals.

| # | Scenario | N | Primary stress |
|---|---|---|---|
| 1 | Single image (≈10 MB source) | 1 | Per-item decode (large) |
| 2 | Many images | {20, 50, 100, 200} | Load + per-item decode throughput |
| 3 | Single long text (`heavy_text.txt` / ≈1 MB) | 1 | Per-item title/search |
| 4 | Many long texts | {20, 50, 100, 200} | Load + per-key search |
| 5 | Images + long text mixed | mixed | Mixed decode + text |
| 6 | Many images + many long texts | {20, 50, 100, 200} | Full pipeline (worst case) |

### UI render smoke (non-blocking)
A `PerformanceSmokeTests` class in `MaccyUITests` drives selection across the popup (arrow-key navigation / hover) and asserts the popup stays responsive (no hang) with a large history loaded. **Sequential, single Maccy instance** — see §7 for why it is not parallelized. This is a *smoke* (end-to-end sanity), not the hard gate; it runs `continue-on-error`.

## 7. CI design — one matrix, hard-capped at 5 macOS, `-only-testing:` as the shard parameter

### Why this shape
- **xcodebuild has no native `--shard`** (verified for Xcode 26; unlike Jest/Playwright). The "test only a certain part" parameter is `-only-testing:Target/Class/method`. Each matrix shard passes a different `-only-testing:` value → each runner tests only its part. The shard→test mapping is maintained by us (hand-tuned by predicted workload after the first measured run, à la Grab's UI-test balancing).
- **Cross-runner sharding removes both earlier constraints**: each runner is a separate VM with its own system clipboard (so Maccy UI tests don't race on the pasteboard) and its own CPU/cache (so `measure{}` timings stay clean — no inter-worker contamination).
- **5 UI shards already = 5 macOS.** With a global 5-cap there is no concurrency headroom for unit/perf to run alongside, so they must share the cap.

### Structure (single workflow, preserves the existing concurrency group)

```text
jobs:
  lint            # macOS swiftlint (brew). Fast (~1 min). Self-scan included.
  test-shards:
    needs: lint            # lint finishes before shards start → peak ≤ 5 macOS
    runs-on: macos-26
    strategy:
      max-parallel: 5      # HARD CAP: ≤ 5 of this matrix concurrent
      fail-fast: false     # one shard failing must not cancel the others
      matrix:
        include:
          - { shard: unit, only: "MaccyTests",                                  block: true  }
          - { shard: ui-1, only: "MaccyUITests/MaccyUITests/<methods…>",        block: true  }
          - { shard: ui-2, only: "MaccyUITests/MaccyUITests/<methods…>",        block: true  }
          - { shard: ui-3, only: "MaccyUITests/MaccyUITests/<methods…>",        block: true  }
          - { shard: ui-4, only: "MaccyUITests/MaccyUITests/<methods…>",        block: true  }
          - { shard: ui-5, only: "MaccyUITests/MaccyUITests/<methods…>",        block: true  }
          - { shard: perf, only: "MaccyPerformanceTests MaccyUITests/PerformanceSmokeTests", block: false }
    continue-on-error: ${{ !matrix.block }}
```

- **`max-parallel: 5`** is the hard guarantee: entries beyond 5 queue, never exceeding 5 concurrent macOS. (`cancel-in-progress: false` on the existing concurrency group means new pushes queue behind a running run, so only one run's shards are active at a time — an additional natural cap.)
- **`fail-fast: false`** so a flaky UI shard doesn't cancel the others; we see every shard's result.
- **Per-runner build+test** (`xcodebuild … test`), not build-once: unambiguously respects the test plan's `enable-testing` (§3 deferral rationale). Compute is free for this public repo.
- **`only` expansion**: a step splits the `only` string on whitespace and emits repeated `-only-testing:` flags.
- **Per-shard self-scan**: each *blocking* shard ends with the existing log scan (same grep + the `HDRImageConverter…falling back to SIMD` exclusion already in the workflow), so "any warning/error/failed in any blocking shard fails the gate." The perf shard (`block: false`) skips the scan and instead uploads its log + `measure{}` output as an artifact for me to read via `gh`.
- **Log aggregation**: each shard writes `ci-logs/<shard>.log`; the existing upload-artifact step (now per-shard) retains them. No cross-job download needed.

### Shard balancing
First run measures each UI test method's duration from a single-runner run; methods are bin-packed into 5 shards to equalize wall-clock (minimize the long pole). The mapping lives in the workflow YAML (or a committed shard-map file) and is iterated as tests evolve.

## 8. Measurement trustworthiness

- **Numbers are comparative, not absolute.** Headless CI (no GPU, shared-VM load) makes absolutes noisy; the gates detect *gross* regressions and BS-4/5 before/after *deltas* (same runner config → contamination is consistent).
- **`measure{}` baselines are NOT enforced as hard failures** initially (perf shard is `continue-on-error`), so a noisy run never blocks the gate. Baselines may be recorded later as advisory.
- Each report includes average + stddev; per-item and `maxGap` are logged via `OSSignposter` and read from the artifact.

## 9. Pre-BS-4 baseline capture

Once B+C land green, a dedicated `workflow_dispatch` run on `master` captures the baseline: the perf shard's measurement log is uploaded as a run artifact, and its key numbers (per-scenario average / per-item / `maxGap`) are transcribed into a committed `docs/audit/2026-06-20-perf-baseline.md` so they are reviewable in-repo. BS-4's `4.9` gate and BS-5's `5.13` gate re-run the same shard and print the delta vs this baseline.

## 10. BS-4 summary (data-pipeline acceleration)

Source of truth: `step-4-data-pipeline.md`. The harness measures the two gates:
- **`G-popup-open`** — history=200 (was 1000), cold popup open → first frame, main thread < 16 ms.
- **`G-copy-text`** — copy `heavy_text.txt`, main thread < 16 ms; `IngestResult.metrics.bytesHashed` down (lhs in-memory cache; not yet persistent → non-zero until BS-8).

Small steps 4.1–4.9 (SignatureIndex maintenance API; `findSimilarItem` via index; batched background `load` + visible-window decorate; binary insert + merge-without-copy; symmetric lhs fingerprint cache; `sessionLog` → `ItemID` + shortcut diff; ingest coalesce + popup prewarm; residual cleanup; tests). Implemented via subagent-driven-development (implementer → spec review → quality review), one small step per CI cycle, committed `feat/fix(bs4.x)`.

## 11. BS-5 summary (search → background actor)

Source of truth: `step-5-text-search.md`. The harness measures:
- **`G-search`** — history=200, per-key search, main thread < 16 ms/key (the actor carries the work post-BS-5; pre-BS-5 baseline is the current sync `O(n)` main-thread search).

Small steps 5.1–5.13 (HighlightRange model; UTF-16↔grapheme conversion; `SearchSnapshot` DTO; `actor SearchEngine`; `Search.swift` thin shell; `searchQuery.didSet` rewiring; highlight path fix; resize out of search path; `showSpecialSymbols` visible-only scope; truncation-unit unification; Fuse reuse; tests). Same execution model as BS-4.

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| pbxproj target surgery unverifiable locally | First perf commit = trivial green test only; confirm wiring before any benchmark |
| Missing `import ImageIO` / SwiftLint `--strict` / `@testable import Maccy` | Apply the `no-local-toolchain-ci-gates` memory checklist before every push |
| `measure{}` noise on headless CI | Comparative deltas, not absolutes; `continue-on-error` perf shard never blocks |
| Network-dependent fixture gen | CoreGraphics synthetic fallback; suite never hard-fails offline |
| UI smoke flakiness (chronic `testCopyImage`) | Smoke is non-blocking; sequential single-instance (no clipboard race); keep it minimal |
| Workflow restructure (matrix + scan) | CI-iterative like everything; `fail-fast: false` to see all shard results |
| BS-4 `load()` refactor is large | Harness-first so each `4.x` sub-step diffs against the baseline |

## 13. Execution model

- **TDD** for every behavior change (failing test → minimal correct change → focused test green).
- **Subagent-driven-development** per small step (implementer → spec reviewer → code-quality reviewer); max 2 concurrent subagents.
- **CI is the only truth.** Self-check the diff against SwiftLint rules + framework imports + `@testable import Maccy` before each push; poll no more often than every 2 min.
- **Commit cadence**: one commit per small step, message names the roadmap item (`feat(bsX.Y)`/`fix(bsX.Y)`/`perf(bsX.Y)`/`docs(bsX.Y)`). Push after each big step passes its build+test gate.
- **Master stays green.** Each push should leave master convergent.

## 14. Resolved decisions (no open questions)

1. Sequencing → harness first, then BS-4, then BS-5.
2. Fixtures → runner-side generation (download + crop), no binaries committed.
3. Render metric → decode/decorate path as hard gate + non-blocking UI smoke.
4. N → {20, 50, 100, 200} (200 = real default cap).
5. Parallelism → 5-runner matrix via `-only-testing:`, `max-parallel: 5` hard cap, per-runner build+test.
6. Perf CI → non-blocking (`continue-on-error`), measurements as artifacts; never blocks the gate.

# Pre-BS-4 performance baseline (captured 2026-06-20)

**Source:** CI run `27876166339` (commit `da31514`), perf shard job `82495933262`,
on the macOS 26 ARM runner (headless, GPU-less). The six-scenario benchmark
suite (`ImageDecodePerformanceTests`, `TextSearchPerformanceTests`) emits
`PERF|...` lines to the perf-shard log; values below are transcribed from there.

**Caveat — numbers are comparative, not absolute.** Headless CI + the
`enable-testing` in-memory SwiftData store (200-item cap, no on-disk I/O) make
these smaller and less main-thread-bound than the shipped app's real cold load.
Treat them as the pre-BS-4 reference for delta comparison, not as real-world
latency.

## Measurements

| Scenario | N | load_avg (s) | search/key (s) | mainThread maxGap (s) |
|---|---|---|---|---|
| 1. single image (≈10MB source) | 1 | **0.0018** | — | 0.0 ⚠ |
| 2. many images | 200 | **0.110** | — | 0.0 ⚠ |
| 3. single long text | 1 | **0.00027** | — | 0.0 ⚠ |
| 4a. many long texts (load) | 200 | **0.0307** | — | 0.0 ⚠ |
| 4b. many long texts (search) | 200 | — | **0.0018** | 0.0 ⚠ |
| 6. mixed images + long texts | 200 | **0.0605** | — | 0.0 ⚠ |

## Known limitation: `mainThread_maxGap_s = 0.0`

`MainThreadProbe` uses `Timer.scheduledTimer`, which does not fire in the async
`@MainActor` benchmark methods' run-loop mode, so every `maxGap` reads `0.0`
(the probe's initial value — the timer never ticked). **The main-thread-occupancy
metric is therefore not captured by this baseline.** The `load_avg` / `searchPerKey_avg`
wall-clock numbers ARE valid. Refining the probe (e.g. a `DispatchSource`-based
sampler or a background-thread `DispatchQueue.main.sync` probe that doesn't
depend on the main run-loop mode) is tooling work to do alongside BS-4 so the
`G-popup-open`/`G-search` `< 16 ms` main-thread gates can actually be measured.

## Notes for BS-4 / BS-5

- Pre-BS-4 `load()` is already fast in this test setup (≤0.11 s for 200 items)
  because the in-memory store has no disk I/O and BS-2/3 already moved some work
  off-main. BS-4's win is primarily **algorithmic** (load `O(n)`→`O(visible)`;
  insert `O(n log n)`→`O(log n)`; dedup `O(n)`→`O(hits)`) — keep `load_avg` from
  regressing and watch the per-item decode cost as the visible-window decorate
  path changes.
- Pre-BS-5 search (synchronous `Search.search` over 200 long texts) averages
  ~1.8 ms/key — already well under 16 ms in this setup. BS-5's win is moving it
  off the main thread (the `< 16 ms/key` *main-thread* gate, measurable once the
  probe is fixed) plus the UTF-16/highlight correctness fixes.
- Scenario 5 (small mixed) is covered by the same `makeMixed` factory at smaller
  N; not run separately in this baseline (add if a finer curve is wanted).
- Fixture generation (200 JPEGs via quality binary-search) dominates each
  cold-cache test's wall time (~70 s for `image-many-200`); it's cached per
  `cacheDir`, so warm runs are fast.

## Reproducing

Re-run the perf shard on any commit and grep the perf-shard log:
```sh
gh run view --job=$(gh run view <run-id> -R GuangDai/Maccy | awk '/shard \(perf\)/{print $NF}' | tr -d '(') \
  -R GuangDai/Maccy --log | grep -oE 'PERF\|[^	]*'
```
Compare the `load_avg`/`searchPerKey_avg` deltas vs this table.

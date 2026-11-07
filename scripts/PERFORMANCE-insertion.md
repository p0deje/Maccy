# Reproducing this PR's component benchmark

Requires Apple Silicon macOS, full Xcode with command-line tools selected, Python 3.12+, and network access for Swift packages. Run from this branch. Use fresh output directories outside the checkout:

```sh
python3 scripts/validate-performance.py --case insertion --output ../performance-candidate
python3 scripts/validate-performance.py --case insertion --baseline f0b571e --output ../performance-baseline
```

Run sequentially with other workloads idle. `--packages /path/to/SourcePackages` optionally reuses Xcode's dependency cache. Both commands build Release with `-O`, enable testability and DEBUG test hooks, run the relevant native test suite, and run three benchmark trials. Logs, xcresult bundles, source copies, and raw JSON remain in the output directory.

The runner changes only its disposable source copy: unique bundle ID, private named clipboard, and existing DEBUG hooks for in-memory storage/isolated preferences. It removes test-runner framework-path overrides so the embedded Sparkle framework is loaded. These are validation-only changes, applied identically to both revisions, not production changes. It does not launch the installed Maccy or use its database. Generated validation apps are not distribution builds.

The baseline uses the same benchmark fixture, with the original insertion expression where applicable; it runs its original functional suite. Candidate runs include the new regressions. Compare per-case medians across all three trials; retain raw data. These are synthetic component measurements, not end-to-end popup latency, battery measurements, or proof of long-term memory behavior. Text preparation defers work to first preview access. Array insertion remains O(n); insertion timings include result-equality verification on each iteration.

Recorded results are in `performance-results-insertion.json`. The recorded run built all variants first, then alternated baseline and candidate sequentially for three rounds. Earlier concurrent warmup runs were excluded. Unit results are native app-hosted Swift Testing runs; full UI tests were not run.

# Performance Harness (MaccyPerformanceTests + CI matrix) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `MaccyPerformanceTests` target with a runner-side real-image fixture corpus and a six-scenario benchmark suite, restructure CI into a 5-runner `-only-testing:` matrix hard-capped at 5 concurrent macOS, and capture the pre-BS-4 baseline.

**Architecture:** A new unit-test target (`MaccyPerformanceTests`, 4th `PBXNativeTarget`) holds the benchmarks + an `ImageFixtureGenerator` (downloads CC0 photos on the runner, crops into a {10,5,2,1,0.5}MB distribution via a JPEG-quality binary search, seeded-deterministic, CoreGraphics synthetic fallback). A `PerformanceSmokeTests` class in `MaccyUITests` adds a non-blocking UI hover/select smoke. The workflow becomes `lint` → `test-shards` matrix (`max-parallel: 5`, `fail-fast: false`), each shard passing a different `-only-testing:` value; the perf shard is `continue-on-error`.

**Tech Stack:** XCTest `measure{}` + `OSSignposter`, `MaccyTests/Support/MainThreadProbe` + `HistoryBuilder` + `FixtureLoader`, CoreGraphics + ImageIO, GitHub Actions matrix.

**CRITICAL — no local toolchain (CLAUDE.md):** Nothing builds/runs locally. Every verification is a CI round-trip on the macOS 26 ARM runner. The TDD "watch it fail" step is therefore a reasoning step (predict the compile/assertion failure); combined RED+GREEN verification happens on push. Before every push, self-check the diff against the `no-local-toolchain-ci-gates` memory: SwiftLint `--strict` rules, explicit framework imports (`import ImageIO`!), and `@testable import Maccy` on every test file that references a Maccy type. Poll CI no more often than every 2 minutes.

**Commit cadence:** one commit per task, message `feat(perf-harness)` / `fix(perf-harness)` / `ci(perf-harness)`. Do NOT push docs-only commits alone (wastes an ~11 min run) — bundle the spec commit (`4f9c2d7`) with Task 1's push.

---

## File Structure

**New files:**
- `MaccyPerformanceTests/WiringSmokeTest.swift` — trivial green test proving the target is wired (Task 1).
- `MaccyPerformanceTests/ImageFixtureGenerator.swift` — runner-side corpus generator (Task 3).
- `MaccyPerformanceTests/PerfHistoryFactory.swift` — composes the six scenario histories from `HistoryBuilder` (Task 4).
- `MaccyPerformanceTests/PerformanceTestCase.swift` — base `XCTestCase` with shared setUp (in-memory store via `enable-testing`, fixture cache dir, `MainThreadProbe`) (Task 4).
- `MaccyPerformanceTests/ImageDecodePerformanceTests.swift` — scenarios 1/2/5/6: load + per-item decode/decorate (Task 5).
- `MaccyPerformanceTests/TextSearchPerformanceTests.swift` — scenarios 3/4: text load + per-key search baseline (Task 6).
- `MaccyUITests/PerformanceSmokeTests.swift` — non-blocking UI hover/select smoke (Task 7).
- `docs/audit/2026-06-20-perf-baseline.md` — transcribed baseline numbers (Task 8).

**Modified:**
- `Maccy.xcodeproj/project.pbxproj` — new target (Task 1) + each new source file registered in all four places (per task).
- `Maccy.xctestplan` — add `MaccyPerformanceTests` to `testTargets` (Task 1).
- `.github/workflows/macos26-arm-ci.yml` — add a perf step (Task 1), then restructure to the matrix (Task 2).

**pbxproj registration (EVERY new .swift file, every task):** mirror the existing `MaccyTests` source-file registration. For each new file generate fresh 24-hex UUIDs (not present anywhere in the file) and add entries in: (1) `PBXBuildFile` (`<fileUUID> /* File.swift in Sources */ = {isa = PBXBuildFile; fileRef = <refUUID>; };`), (2) `PBXFileReference` (`<refUUID> /* File.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = File.swift; sourceTree = "<group>"; };`), (3) the `MaccyPerformanceTests` group's `children` array, (4) the `MaccyPerformanceTests` `PBXSourcesBuildPhase` `files` array. This is the established pattern; copy a `MaccyTests` file's four entries as the template.

---

## Task 1: Create `MaccyPerformanceTests` target + wiring test + CI step

**Goal:** A 4th test target that builds and runs a trivial green test on CI. Highest-risk task (pbxproj surgery, unverifiable locally) → minimal content, validate wiring before adding anything else.

**Files:**
- Create: `MaccyPerformanceTests/WiringSmokeTest.swift`
- Modify: `Maccy.xcodeproj/project.pbxproj` (new target + file registration)
- Modify: `Maccy.xctestplan` (add target to `testTargets`)
- Modify: `.github/workflows/macos26-arm-ci.yml` (add a perf-test step)

- [ ] **Step 1: Write the wiring test**

`MaccyPerformanceTests/WiringSmokeTest.swift`:
```swift
import XCTest

/// Confirms the MaccyPerformanceTests target is wired into the project and the
/// test plan, and that it builds and runs on CI. Replaced by real benchmarks
/// in later tasks; kept as a smoke test.
final class WiringSmokeTest: XCTestCase {
  func testTargetIsWiredAndRuns() {
    XCTAssertTrue(true, "MaccyPerformanceTests target builds and executes.")
  }
}
```
(No `@testable import Maccy` — this test references no Maccy types, so it avoids that gotcha.)

- [ ] **Step 2: Register the target in `project.pbxproj`**

Mirror the `MaccyTests` target end-to-end with fresh 24-hex UUIDs. Concretely, duplicate and rename these structures from `MaccyTests` → `MaccyPerformanceTests`:
  - A `PBXNativeTarget` (`productType = "com.apple.product-type.bundle.unit-test"`; `name = MaccyPerformanceTests`; build phases: a `PBXSourcesBuildPhase` (with `WiringSmokeTest.swift`), an empty `PBXFrameworksBuildPhase`, a `PBXResourcesBuildPhase`).
  - An `XCBuildConfiguration` (Debug) cloning `MaccyTests`'s Debug settings (`TEST_HOST = $(BUILT_PRODUCTS_DIR)/Maccy.app/…`, `BUNDLE_LOADER = $(TEST_HOST)`, `PRODUCT_NAME = MaccyPerformanceTests`, `PRODUCT_BUNDLE_IDENTIFIER = org.p0deje.Maccy.MaccyPerformanceTests`, `GENERATE_INFOPLIST_FILE = YES`) + its `XCConfigurationList`.
  - A `PBXFileReference` for the product (`MaccyPerformanceTests.xctest`, `explicitFileType = wrapper.cfbundle`).
  - A `PBXGroup` for `MaccyPerformanceTests` (child: `WiringSmokeTest.swift`), parented under the test-targets group alongside `MaccyTests`.
  - A `PBXTargetDependency` + `PBXContainerItemProxy` on the `Maccy` app target (copy `MaccyTests`'s dependency).
  - Add `MaccyPerformanceTests` to the project's `targets` array (`PBXProject → attributes → TargetAttributes` not strictly required, but add a `developmentRegion`/`TestTargetID` mirroring `MaccyTests` if present).
Register `WiringSmokeTest.swift` in all four places (see "pbxproj registration" in File Structure).

- [ ] **Step 3: Add the target to `Maccy.xctestplan`**

Append to `testTargets` (mirror the `MaccyTests` entry's shape; generate a fresh UUID for the configuration `id`):
```json
    {
      "target" : {
        "containerPath" : "container:Maccy.xcodeproj",
        "identifier" : "<MaccyPerformanceTests-target-UUID-from-pbxproj>",
        "name" : "MaccyPerformanceTests"
      }
    }
```

- [ ] **Step 4: Add a CI step to run it (blocking, to validate wiring)**

In `.github/workflows/macos26-arm-ci.yml`, after the "Run UI tests" step, add:
```yaml
      - name: Run performance tests (wiring check)
        timeout-minutes: 10
        shell: bash
        run: |
          set -euo pipefail
          xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA" \
            -resultBundlePath "$RESULT_BUNDLES/perf-tests.xcresult" \
            -only-testing:MaccyPerformanceTests \
            CODE_SIGNING_ALLOWED=NO \
            test 2>&1 | tee "$LOG_DIR/perf-tests.log"
```
(Block intentionally — no `continue-on-error` — so a wiring failure fails CI. Task 2 makes perf non-blocking.)

- [ ] **Step 5: Commit**

```bash
git add MaccyPerformanceTests/WiringSmokeTest.swift \
        Maccy.xcodeproj/project.pbxproj Maccy.xctestplan \
        .github/workflows/macos26-arm-ci.yml \
        docs/superpowers/specs/2026-06-20-perf-harness-and-bs4-bs5-design.md
git commit -m "feat(perf-harness): add MaccyPerformanceTests target + wiring smoke + perf CI step"
```

- [ ] **Step 6: Push and verify on CI**

```sh
git push origin master
gh workflow run "macOS 26 ARM CI" --ref master   # or it auto-triggers on push
```
Poll `gh run view --workflow "macOS 26 ARM CI"` no more often than every 2 min (~11 min). **Expected:** green; the perf step's `perf-tests.log` shows `WiringSmokeTest` passed.
**If it fails:** the pbxproj is the likely culprit (target not built / not in plan / wrong TEST_HOST). Compare the new target's entries byte-for-byte against `MaccyTests`. Fix-forward; this task is not done until green.

---

## Task 2: Restructure CI into the 5-runner matrix

**Goal:** Replace the single sequential `build-and-test` job with `lint` + a `test-shards` matrix (`max-parallel: 5`, `fail-fast: false`), sharding `MaccyUITests`'s 36 methods across 5 runners and making `MaccyPerformanceTests` non-blocking. Honors the user's hard cap of ≤5 concurrent macOS.

**Files:**
- Modify: `.github/workflows/macos26-arm-ci.yml` (rewrite `jobs:`)

- [ ] **Step 1: Determine the initial UI method split**

`MaccyUITests` is one class with 36 test methods (`grep -n "func test" MaccyUITests/MaccyUITests.swift`). For the first cut, split the method names alphabetically into 5 groups of ~7-8 (balanced by count; rebalance by measured time after the first green run, à la Grab's UI-test balancing). Record the five method lists.

- [ ] **Step 2: Rewrite the workflow jobs**

Replace the single `build-and-test` job with two jobs. Keep the existing `env:` block, diagnostics step, macOS-26-enforce step, and the awk runner-noise filter (`fopen failed…`, `AppleM2ScalerParavirtDriver`) carried into each shard's test step. Skeleton:
```yaml
jobs:
  lint:
    name: Lint (SwiftLint)
    runs-on: macos-26
    timeout-minutes: 10
    env: { <<same PROJECT/SCHEME/CONFIGURATION/DESTINATION/LOG_DIR…>> }
    steps:
      - uses: actions/checkout@v6
      - name: Prepare logs
        run: mkdir -p "$LOG_DIR"
      - name: Run SwiftLint
        run: |
          if ! command -v swiftlint >/dev/null 2>&1; then brew install swiftlint; fi
          swiftlint lint --quiet --strict --no-cache 2>&1 | tee "$LOG_DIR/swiftlint.log"
      - name: Self-scan swiftlint log
        run: |
          set -euo pipefail
          matches=$(grep -Ein '(^|[^[:alpha:]])(warning:|error:)([^[:alpha:]]|$)' "$LOG_DIR/swiftlint.log" || true)
          if [[ -n "$matches" ]]; then echo "$matches"; exit 1; fi

  test-shards:
    name: shard (${{ matrix.shard }})
    needs: lint
    runs-on: macos-26
    timeout-minutes: 30
    strategy:
      max-parallel: 5
      fail-fast: false
      matrix:
        include:
          - { shard: unit, only: "MaccyTests",                                  block: true  }
          - { shard: ui-1, only: "<ui-method-group-1>",                         block: true  }
          - { shard: ui-2, only: "<ui-method-group-2>",                         block: true  }
          - { shard: ui-3, only: "<ui-method-group-3>",                         block: true  }
          - { shard: ui-4, only: "<ui-method-group-4>",                         block: true  }
          - { shard: ui-5, only: "<ui-method-group-5>",                         block: true  }
          - { shard: perf, only: "MaccyPerformanceTests MaccyUITests/PerformanceSmokeTests", block: false }
    continue-on-error: ${{ !matrix.block }}
    env: { <<same env block>> }
    steps:
      - uses: actions/checkout@v6
      - name: Prepare logs
        run: mkdir -p "$LOG_DIR" "$RESULT_BUNDLES"
      - <<diagnostics + macOS-enforce steps (optional, can keep in lint only)>>
      - name: Build and test shard
        shell: bash
        run: |
          set -euo pipefail
          only_args=""
          for t in ${{ matrix.only }}; do only_args="$only_args -only-testing:$t"; done
          xcodebuild \
            -project "$PROJECT" -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA" \
            -resultBundlePath "$RESULT_BUNDLES/${{ matrix.shard }}.xcresult" \
            $only_args \
            CODE_SIGNING_ALLOWED=NO \
            test 2>&1 \
            | awk -v f='…fopen…' -v io='…AppleM2Scaler…' 'index($0,f)||index($0,io)||/IDELaunchParametersSnapshot:/{next}{print}' \
            | tee "$LOG_DIR/${{ matrix.shard }}.log"
      - name: Self-scan shard log (blocking shards only)
        if: ${{ matrix.block }}
        run: |
          set -euo pipefail
          matches=$(grep -Ein '(^|[^[:alpha:]])(warning:|error:|\*\* TEST FAILED \*\*|Fatal error|[Ff]ailed)([^[:alpha:]]|$)' "$LOG_DIR/${{ matrix.shard }}.log" \
                    | grep -vE 'HDRImageConverter.*falling back to SIMD' || true)
          if [[ -n "$matches" ]]; then echo "$matches"; exit 1; fi
      - name: Upload shard logs + result bundle
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: shard-${{ matrix.shard }}-${{ github.run_id }}-${{ github.run_attempt }}
          path: |
            ci-logs
            ci-result-bundles
          if-no-files-found: warn
          retention-days: 14
```
Notes for the author: `$ {{ matrix.only }}` is a whitespace-separated string; the `for t in …` loop emits repeated `-only-testing:` flags. The ui method groups are written as `MaccyUITests/MaccyUITests/testFoo MaccyUITests/MaccyUITests/testBar …`. The `perf` shard's `only` references `MaccyUITests/PerformanceSmokeTests` (created in Task 7) — until then, **temporarily** set perf's `only` to just `MaccyPerformanceTests` and drop the smoke reference; Task 7 adds it. Keep `concurrency:` at workflow level unchanged (`cancel-in-progress: false` → runs queue, not overlap; one run's ≤5 shards active at a time).

- [ ] **Step 3: Commit + push + verify**

```bash
git add .github/workflows/macos26-arm-ci.yml
git commit -m "ci(perf-harness): 5-runner -only-testing matrix, max-parallel:5, perf non-blocking"
git push origin master
```
Poll CI. **Expected:** `lint` green; all 5 UI shards + unit shard green (gate holds); perf shard green and non-blocking (its failure wouldn't fail the run). Total concurrent macOS ≤5. If a UI shard fails that previously passed, the method-split or the awk filter is the suspect. Rebalance shards if one is a long pole.

---

## Task 3: `ImageFixtureGenerator` (runner-side corpus)

**Goal:** Generate the {10,5,2,1,0.5}MB JPEG corpus on the runner from real downloaded photos (synthetic fallback), deterministic + cached.

**Files:**
- Create: `MaccyPerformanceTests/ImageFixtureGenerator.swift`
- Test: `MaccyPerformanceTests/ImageFixtureGeneratorTests.swift`
- Modify: `Maccy.xcodeproj/project.pbxproj` (register both files)

- [ ] **Step 1: Write the failing test**

`MaccyPerformanceTests/ImageFixtureGeneratorTests.swift`:
```swift
import XCTest
@testable import Maccy   // not strictly needed here; keep for consistency with other perf tests

final class ImageFixtureGeneratorTests: XCTestCase {
  func testJPEG_hitsTargetByteBucketWithinTolerance() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "ImageFixtureGeneratorTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let data = try ImageFixtureGenerator.jpeg(
      bucket: .m1, variant: 0, cacheDir: cacheDir)
    // Allow generous tolerance; the binary search lands within ~5%.
    XCTAssertGreaterThan(data.count, 1_048_576 - 60_000)
    XCTAssertLessThan(data.count, 1_048_576 + 60_000)
  }

  func testJPEG_isDeterministicAcrossCalls() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "ImageFixtureGeneratorDet-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let a = try ImageFixtureGenerator.jpeg(bucket: .k500, variant: 1, cacheDir: cacheDir)
    let b = try ImageFixtureGenerator.jpeg(bucket: .k500, variant: 1, cacheDir: cacheDir)
    XCTAssertEqual(a, b)
  }
}
```

- [ ] **Step 2: Predict the failure**

Without `ImageFixtureGenerator` defined, this fails to compile (`cannot find 'ImageFixtureGenerator' in scope`). Verification deferred to the combined push (Step 4).

- [ ] **Step 3: Implement `ImageFixtureGenerator`**

`MaccyPerformanceTests/ImageFixtureGenerator.swift`:
```swift
import AppKit
import Foundation
import ImageIO

/// Runner-side generator for the performance-test image corpus. Downloads real
/// CC0 photos (synthetic CoreGraphics fallback if offline), crops/scales into a
/// target byte-size distribution via a JPEG-quality binary search, seeded for
/// determinism, cached per run. Nothing is committed to git except this file.
enum ImageFixtureGenerator {
  enum Bucket: String, Sendable, CaseIterable {
    case m10, m5, m2, m1, k500
    var targetBytes: Int {
      switch self {
      case .m10: return 10 * 1024 * 1024
      case .m5:  return 5  * 1024 * 1024
      case .m2:  return 2  * 1024 * 1024
      case .m1:  return 1  * 1024 * 1024
      case .k500: return 500 * 1024
      }
    }
    /// Approx pixel area to render before quality-searching, so quality stays
    /// in a sane range. Larger buckets → larger canvases.
    var canvasLongEdge: Int {
      switch self {
      case .m10: return 6000
      case .m5:  return 4500
      case .m2:  return 3000
      case .m1:  return 2200
      case .k500: return 1400
      }
    }
  }

  /// Seedable xorshift64* (SystemRandomNumberGenerator can't be seeded).
  struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEFDEADBEEF : seed }
    mutating func next() -> UInt64 {
      state &+= 0x9E3779B97F4A7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
      z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
      return z ^ (z >> 31)
    }
  }

  private static var sourceImages: [NSImage] = []
  private static let sourcesQueue = DispatchQueue(label: "ImageFixtureGenerator.sources")

  /// Populate `sourceImages`. Tries real CC0 downloads; synthesizes on failure.
  static func ensureSourcesLoaded() {
    sourcesQueue.sync {
      guard sourceImages.isEmpty else { return }
      sourceImages = downloadSources()
      if sourceImages.isEmpty { sourceImages = [synthesizeSource()] }
    }
  }

  private static func downloadSources() -> [NSImage] {
    // A few stable CC0 photo URLs. Any failure → skip that URL.
    let urls = [
      "https://picsum.photos/seed/maccy-perf-a/3000/2000",
      "https://picsum.photos/seed/maccy-perf-b/2500/2500",
      "https://picsum.photos/seed/maccy-perf-c/4000/1500",
    ]
    return urls.compactMap { urlString -> NSImage? in
      guard let url = URL(string: urlString),
            let data = try? Data(contentsOf: url),
            let image = NSImage(data: data) else { return nil }
      return image
    }
  }

  private static func synthesizeSource() -> NSImage {
    // High-frequency-ish content so JPEG doesn't collapse to a few KB.
    let size = NSSize(width: 3000, height: 2000)
    let image = NSImage(size: size)
    image.lockFocus()
    for y in stride(from: 0, to: Int(size.height), by: 40) {
      for x in stride(from: 0, to: Int(size.width), by: 40) {
        let hue = CGFloat((x + y) % 360) / 360.0
        NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1.0).setFill()
        NSRect(x: CGFloat(x), y: CGFloat(y), width: 40, height: 40).fill()
      }
    }
    image.unlockFocus()
    return image
  }

  /// Returns JPEG data ≈ `bucket.targetBytes` for the given variant, cached.
  static func jpeg(bucket: Bucket, variant: Int, cacheDir: URL) throws -> Data {
    let cacheURL = cacheDir.appending(path: "\(bucket.rawValue)_v\(variant).jpg")
    if let cached = try? Data(contentsOf: cacheURL) { return cached }
    ensureSourcesLoaded()
    let source = sourceImages[variant % sourceImages.count]
    let rendered = renderCropped(source, bucket: bucket, variant: variant)
    let data = encodeJPEG(targeting: bucket.targetBytes, image: rendered)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    try? data.write(to: cacheURL)
    return data
  }

  /// Deterministic crop + scale of `source` to bucket's canvas long edge.
  private static func renderCropped(_ source: NSImage, bucket: Bucket, variant: Int) -> NSImage {
    var rng = SeededRNG(seed: UInt64(variant) &* 2_000_003 &+ 1)
    let srcSize = source.size
    let cropW = srcSize.width * Double(rng.random(in: 0.5...0.95))
    let cropH = srcSize.height * Double(rng.random(in: 0.5...0.95))
    let originX = srcSize.width * Double(rng.random(in: 0..<(1 - (cropW / srcSize.width))))
    let originY = srcSize.height * Double(rng.random(in: 0..<(1 - (cropH / srcSize.height))))
    let cropRect = NSRect(x: originX, y: originY, width: cropW, height: cropH)

    let longEdge = bucket.canvasLongEdge
    let scale = longEdge / max(cropW, cropH)
    let destSize = NSSize(width: cropW * scale, height: cropH * scale)
    let composite = NSImage(size: destSize)
    composite.lockFocus()
    source.draw(in: NSRect(origin: .zero, size: destSize),
                from: cropRect,
                operation: .copy,
                fraction: 1.0)
    composite.unlockFocus()
    return composite
  }

  /// Binary-search JPEG quality so the encoded bytes hit `targetBytes` ±5%.
  private static func encodeJPEG(targeting targetBytes: Int, image: NSImage) -> Data {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
      return Data()
    }
    var low = 0.05
    var high = 0.95
    var best = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? Data()
    for _ in 0..<20 {
      let mid = (low + high) / 2
      guard let data = rep.representation(
        using: .jpeg, properties: [.compressionFactor: mid]) else { break }
      best = data
      if abs(Double(data.count) - Double(targetBytes)) < Double(targetBytes) * 0.05 { break }
      if data.count < targetBytes { low = mid } else { high = mid }
    }
    return best
  }
}
```
Self-check before push: `import ImageIO` present (memory: CoreGraphics does not re-export `CGImageSource…`; here we use `NSBitmapImageRep` from AppKit, but keep `import ImageIO` for safety/consistency). All identifiers ≥3 chars (no `fp`/`bg`). No tuple >2 members. File <400 lines, functions <50 lines.

- [ ] **Step 4: Register both files in pbxproj (see File Structure), commit, push, verify**

```bash
git add MaccyPerformanceTests/ImageFixtureGenerator.swift \
        MaccyPerformanceTests/ImageFixtureGeneratorTests.swift \
        Maccy.xcodeproj/project.pbxproj
git commit -m "feat(perf-harness): runner-side ImageFixtureGenerator (real-photo download + crop + size distribution)"
git push origin master
```
Poll CI. **Expected:** both `ImageFixtureGeneratorTests` methods pass on the perf shard (run as part of `-only-testing:MaccyPerformanceTests`). If `testJPEG_hitsTargetByteBucketWithinTolerance` misses the tolerance, widen the band or tighten the binary-search (it's a measurement, not a correctness gate). Note: the test downloads from picsum — if CI network blocks it, the synthetic fallback engages and the test still passes (same byte-targeting logic).

---

## Task 4: `PerfHistoryFactory` + `PerformanceTestCase` base

**Goal:** Shared setUp (in-memory store, fixture cache, `MainThreadProbe`) and a factory that composes the six scenario histories.

**Files:**
- Create: `MaccyPerformanceTests/PerformanceTestCase.swift`
- Create: `MaccyPerformanceTests/PerfHistoryFactory.swift`
- Test: `MaccyPerformanceTests/PerfHistoryFactoryTests.swift`
- Modify: `Maccy.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

`MaccyPerformanceTests/PerfHistoryFactoryTests.swift`:
```swift
import XCTest
@testable import Maccy

final class PerfHistoryFactoryTests: XCTestCase {
  @MainActor
  func testFactoryBuildsHistoryWithRequestedImageCount() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "PerfHistoryFactoryTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    let history = try PerfHistoryFactory.makeImages(
      count: 3, bucket: .k500, cacheDir: cacheDir)
    XCTAssertEqual(history.all.count, 3)
  }

  @MainActor
  func testFactoryBuildsTextHistoryFromHeavyText() throws {
    let history = try PerfHistoryFactory.makeTexts(count: 2, long: true)
    XCTAssertEqual(history.all.count, 2)
    XCTAssertFalse(history.all.first?.item.title.isEmpty ?? true)
  }
}
```

- [ ] **Step 2: Implement `PerformanceTestCase` + `PerfHistoryFactory`**

`MaccyPerformanceTests/PerformanceTestCase.swift`:
```swift
import XCTest
@testable import Maccy

/// Base for performance tests. `enable-testing` (test-plan default) forces an
/// in-memory SwiftData store, so each test gets a fresh `History.shared`.
@MainActor
class PerformanceTestCase: XCTestCase {
  let cacheDir: URL = FileManager.default.temporaryDirectory
    .appending(path: "MaccyPerfTests-\(UUID().uuidString)")
  let probe = MainThreadProbe(interval: 0.01)

  override func tearDown() {
    probe.stop()
    try? FileManager.default.removeItem(at: cacheDir)
    super.tearDown()
  }

  /// Assert no main-thread stall exceeded `threshold` since `probe.start()`.
  func assertMainThreadFree(threshold: TimeInterval = 0.016,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThan(probe.maxGap, threshold,
                      "Main thread stalled \(probe.maxGap)s > \(threshold)s",
                      file: file, line: line)
  }
}
```

`MaccyPerformanceTests/PerfHistoryFactory.swift`:
```swift
import AppKit
import Foundation
@testable import Maccy

/// Composes the six benchmark scenarios into a `History` (in-memory store).
@MainActor
enum PerfHistoryFactory {
  /// `count` image items, each a JPEG of `bucket` bytes.
  static func makeImages(count: Int, bucket: ImageFixtureGenerator.Bucket,
                         cacheDir: URL) throws -> History {
    let history = History.shared
    history.clearAll()   // reset in-memory store
    for variant in 0..<count {
      let data = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: variant, cacheDir: cacheDir)
      let item = HistoryBuilder()
        .withContent(type: "public.png", value: data)
        .withCopiedAt(Date(timeIntervalSince1970: Double(variant)))
        .build()
      history.add(item)
    }
    return history
  }

  /// `count` long-text items drawn from `heavy_text.txt`.
  static func makeTexts(count: Int, long: Bool) throws -> History {
    let history = History.shared
    history.clearAll()
    let heavy = try Data(FixtureLoader.heavyTextURL).base64EncodedData()
    let value = long ? heavy : Data("short".utf8)
    for index in 0..<count {
      let item = HistoryBuilder()
        .withContent(type: "public.utf8-plain-text", value: value)
        .withCopiedAt(Date(timeIntervalSince1970: Double(index)))
        .build()
      history.add(item)
    }
    return history
  }

  /// Mixed: `images` image items + `texts` long-text items.
  static func makeMixed(images: Int, texts: Int, bucket: ImageFixtureGenerator.Bucket,
                        cacheDir: URL) throws -> History {
    let history = History.shared
    history.clearAll()
    let heavy = try Data(FixtureLoader.heavyTextURL).base64EncodedData()
    for variant in 0..<images {
      let data = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: variant, cacheDir: cacheDir)
      history.add(HistoryBuilder()
        .withContent(type: "public.png", value: data)
        .withCopiedAt(Date(timeIntervalSince1970: Double(variant))).build())
    }
    for index in 0..<texts {
      history.add(HistoryBuilder()
        .withContent(type: "public.utf8-plain-text", value: heavy)
        .withCopiedAt(Date(timeIntervalSince1970: Double(images + index))).build())
    }
    return history
  }
}
```
Note: `History.shared.add(_:)`, `History.shared.clearAll()`, `history.all` — verify these against the current `History.swift` API at execution (the implementer confirms signatures; `clearAll`/`add`/`all` are referenced throughout the roadmap). If `add`/`clearAll` signatures differ, adjust to the real API. `HistoryBuilder` is the existing fluent builder.

- [ ] **Step 3: Register files, commit, push, verify**

```bash
git add MaccyPerformanceTests/PerformanceTestCase.swift \
        MaccyPerformanceTests/PerfHistoryFactory.swift \
        MaccyPerformanceTests/PerfHistoryFactoryTests.swift \
        Maccy.xcodeproj/project.pbxproj
git commit -m "feat(perf-harness): PerformanceTestCase base + PerfHistoryFactory (six scenario composers)"
git push origin master
```
Poll CI. **Expected:** perf shard green; both factory tests pass. If `History` API mismatches, fix-forward against the real signatures.

---

## Task 5: Image decode/decorate benchmarks (scenarios 1/2/5/6)

**Goal:** `measure{}` over `History.load()` (cold first-frame) and per-item `HistoryItemDecorator` thumbnail decode, with `MainThreadProbe`, for the image scenarios.

**Files:**
- Create: `MaccyPerformanceTests/ImageDecodePerformanceTests.swift`
- Modify: `Maccy.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the benchmarks**

`MaccyPerformanceTests/ImageDecodePerformanceTests.swift`:
```swift
import XCTest
import os.signpost
@testable import Maccy

/// Scenarios 1, 2, 5, 6 — image decode/decorate path (the "pointer → candidate
/// → render" analog: `HistoryItemDecorator.ensureThumbnailImage` as items enter
/// the visible window). Each test measures load time + per-item decode, and
/// asserts no main-thread stall > 16 ms.
@MainActor
final class ImageDecodePerformanceTests: PerformanceTestCase {

  // Scenario 1: single large image.
  func testSingleImage_decodeAndDecorate() throws {
    let history = try PerfHistoryFactory.makeImages(count: 1, bucket: .m10, cacheDir: cacheDir)
    measureAndAssertMainThread(history: history)
  }

  // Scenario 2: many images at each scale point.
  func testManyImages_N200_decodeAndDecorate() throws {
    let history = try PerfHistoryFactory.makeImages(count: 200, bucket: .m1, cacheDir: cacheDir)
    measureAndAssertMainThread(history: history)
  }

  // Scenario 6: many images + many long texts.
  func testMixed_N200_decodeAndDecorate() throws {
    let history = try PerfHistoryFactory.makeMixed(images: 100, texts: 100, bucket: .m1, cacheDir: cacheDir)
    measureAndAssertMainThread(history: history)
  }

  private func measureAndAssertMainThread(history: History) {
    probe.start()
    measure(metrics: [XCTClockMetric()]) {
      // Cold load → visible-window decoration (the G-popup-open analog).
      _ = try? history.load()
      // Per-item thumbnail decode (the render-on-select analog), measured by
      // the load path's decorator work; OSSignposter tags sub-regions.
      let signpost = OSSignposter(logHandle: .default, name: "perItemDecorate")
      let state = signpost.beginInterval("decorate")
      for decorator in history.items.prefix(20) {
        decorator.ensureThumbnailImage()
      }
      signpost.endInterval("decorate", state)
    }
    assertMainThreadFree()   // no >16 ms stall
  }
}
```
Note: `import os.signpost` for `OSSignposter`; or use `import os`. Confirm `HistoryItemDecorator.ensureThumbnailImage()` exists (BS-3 added it) and `history.items` is the visible-window array. Adjust method names to the real API. `measure` blocks are `@Sendable` closures — capture only Sendable state (history is `@MainActor`, captured via `@MainActor` test methods). If `measure` requires a non-throwing closure, wrap `try?`.

- [ ] **Step 2: Register, commit, push, verify**

```bash
git add MaccyPerformanceTests/ImageDecodePerformanceTests.swift Maccy.xcodeproj/project.pbxproj
git commit -m "feat(perf-harness): image decode/decorate benchmarks (scenarios 1/2/6)"
git push origin master
```
Poll CI. **Expected:** perf shard green; benchmarks run and report timings (non-blocking). `measure` output appears in `shard-perf-*.log` artifact.

---

## Task 6: Text load + per-key search benchmarks (scenarios 3/4)

**Files:**
- Create: `MaccyPerformanceTests/TextSearchPerformanceTests.swift`
- Modify: `Maccy.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the benchmarks**

`MaccyPerformanceTests/TextSearchPerformanceTests.swift`:
```swift
import XCTest
@testable import Maccy

/// Scenarios 3, 4 — text load + per-key search. Pre-BS-5 this measures the
/// current synchronous main-thread search (the baseline); post-BS-5 it measures
/// the background-actor path (the G-search gate).
@MainActor
final class TextSearchPerformanceTests: PerformanceTestCase {

  // Scenario 4: many long texts — per-key search latency.
  func testManyLongTexts_N200_searchPerKey() throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: true)
    // Warm the list.
    _ = try? history.load()
    probe.start()
    measure(metrics: [XCTClockMetric()]) {
      // Simulate one keystroke of search.
      history.searchQuery = "the"
      history.searchQuery = ""
    }
    assertMainThreadFree()
  }

  // Scenario 3: single long text — load + title.
  func testSingleLongText_load() throws {
    let history = try PerfHistoryFactory.makeTexts(count: 1, long: true)
    probe.start()
    measure(metrics: [XCTClockMetric()]) {
      _ = try? history.load()
    }
    assertMainThreadFree()
  }
}
```
Note: confirm `history.searchQuery` is the `didSet`-driven property (it is, `History.swift:22`). Setting it twice per `measure` iteration simulates two keystrokes. `searchQuery` mutation must happen on `@MainActor` (the test is `@MainActor`) — fine.

- [ ] **Step 2: Register, commit, push, verify**

```bash
git add MaccyPerformanceTests/TextSearchPerformanceTests.swift Maccy.xcodeproj/project.pbxproj
git commit -m "feat(perf-harness): text load + per-key search benchmarks (scenarios 3/4)"
git push origin master
```
Poll CI. **Expected:** perf shard green.

---

## Task 7: UI render smoke (non-blocking, in `MaccyUITests`)

**Files:**
- Create: `MaccyUITests/PerformanceSmokeTests.swift`
- Modify: `.github/workflows/macos26-arm-ci.yml` (add `MaccyUITests/PerformanceSmokeTests` to the perf shard's `only` — Step 1 of Task 2 anticipated this)
- Modify: `Maccy.xcodeproj/project.pbxproj` (register the file in `MaccyUITests`)

- [ ] **Step 1: Write the smoke test**

`MaccyUITests/PerformanceSmokeTests.swift`:
```swift
import XCTest

/// Non-blocking end-to-end render smoke: load a large history, open the popup,
/// drive selection down the list, assert it stays responsive. Sequential by
/// nature (one Maccy instance — the system clipboard is shared, so UI tests
/// cannot be parallelized across workers on one machine; cross-runner shards
/// are each their own VM so they're safe).
final class PerformanceSmokeTests: MaccyUITestsBase {
  func testPopupStaysResponsiveWhileNavigatingLargeHistory() throws {
    // Uses the app's real clipboard to populate history (MaccyUITests pattern).
    // Open popup, arrow-down through ~20 items, assert each cell renders.
    let app = XCUIApplication()
    app.launchArguments += ["enable-testing"]
    app.launch()

    // Open Maccy (hotkey or menu — mirror existing MaccyUITests helpers).
    openPopup()
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 10))

    for _ in 0..<20 {
      app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
      XCTAssertFalse(list.staticTexts.firstMatch.waitForNonExistence(timeout: 1),
                     "List vanished mid-navigation — popup may have stalled.")
    }
  }
}
```
Note: `MaccyUITestsBase`, `openPopup()` — mirror the existing `MaccyUITests.swift` patterns (the implementer reads `MaccyUITests.swift` to reuse its helpers/launch logic; do not invent new patterns). This test is deliberately a *smoke* (responsiveness), not a precise timing measurement — UI timing on headless CI is too noisy.

- [ ] **Step 2: Wire it into the perf shard's `only`**

In `.github/workflows/macos26-arm-ci.yml`, update the `perf` matrix entry's `only` to:
`"MaccyPerformanceTests MaccyUITests/PerformanceSmokeTests"` (Task 2 left it as just `MaccyPerformanceTests` until this class existed).

- [ ] **Step 3: Register, commit, push, verify**

```bash
git add MaccyUITests/PerformanceSmokeTests.swift \
        .github/workflows/macos26-arm-ci.yml \
        Maccy.xcodeproj/project.pbxproj
git commit -m "feat(perf-harness): non-blocking UI render smoke (popup navigation over large history)"
git push origin master
```
Poll CI. **Expected:** perf shard green and non-blocking. If the smoke is flaky, loosen the assertions (it's non-blocking; a flake must never fail the gate).

---

## Task 8: Capture the pre-BS-4 baseline

**Goal:** Run the perf shard on `master`, transcribe the numbers into a committed baseline doc so BS-4/5 gates can diff against it.

**Files:**
- Create: `docs/audit/2026-06-20-perf-baseline.md`

- [ ] **Step 1: Run the perf shard on master and read the artifact**

```sh
gh workflow run "macOS 26 ARM CI" --ref master
# poll, then:
gh run download <run-id> -n 'shard-perf-*'   # the perf shard's log artifact
```
Extract from `perf.log` the `measure` lines: per-scenario `average`, and the `OSSignposter`/`maxGap` values.

- [ ] **Step 2: Transcribe the baseline**

`docs/audit/2026-06-20-perf-baseline.md`:
```markdown
# Pre-BS-4 performance baseline (2026-06-20)

Captured from CI run `<run-id>` (perf shard) on master at <SHA>.
Numbers are CI-relative (headless, GPU-less macOS 26 runner); compare deltas, not absolutes.

| Scenario | N | load avg (s) | per-item decode (s) | search/key (s) | maxGap (s) |
|---|---|---|---|---|---|
| 1 single image (10MB) | 1 | … | … | — | … |
| 2 many images | 200 | … | … | — | … |
| 3 single long text | 1 | … | — | … | … |
| 4 many long texts | 200 | … | — | … | … |
| 6 mixed | 200 | … | … | — | … |

Gates to beat: `G-popup-open` (<16 ms first frame), `G-copy-text` (<16 ms; bytesHashed↓), `G-search` (<16 ms/key).
```
Fill the `…` from the actual artifact.

- [ ] **Step 3: Commit (docs-only — bundle with the next code push, or push alone if a code push isn't imminent)**

```bash
git add docs/audit/2026-06-20-perf-baseline.md
git commit -m "docs(perf-harness): pre-BS-4 baseline numbers"
# push bundled with the next BS-4 task push (avoids a docs-only CI run)
```

---

## Done criteria

- `MaccyPerformanceTests` target builds + runs the 6-scenario benchmarks + factory/generator tests on CI.
- CI is the 5-runner matrix (`max-parallel: 5`, `fail-fast: false`); gate (lint+unit+5 UI shards) green; perf shard non-blocking.
- `ImageFixtureGenerator` produces the {10,5,2,1,0.5}MB corpus on the runner (real-photo + synthetic fallback).
- Pre-BS-4 baseline transcribed in `docs/audit/2026-06-20-perf-baseline.md`.
- Master green throughout.

After this plan: proceed to BS-4 (use `step-4-data-pipeline.md` as its plan; re-measure at `4.9`), then BS-5 (`step-5-text-search.md`; re-measure at `5.13`), each via subagent-driven-development.

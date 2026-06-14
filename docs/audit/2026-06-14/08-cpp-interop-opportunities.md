# C++ Interop — Audit & Opportunities

- Date: 2026-06-14
- Scope: read-only review of the existing C++/ObjC++ layer in Maccy plus identification of where C++ should be added next.
- Repo root: `/lzcapp/document/Projects/Maccy`
- Layer under review:
  - `Maccy/Processor/ClipboardByteProcessor.hpp`
  - `Maccy/Processor/ClipboardByteProcessor.cpp`
  - `Maccy/Processor/MaccyTextProcessor.h`
  - `Maccy/Processor/MaccyTextProcessor.mm`
  - `Maccy/Maccy-Bridging-Header.h`
  - `Maccy/Core/ClipboardDataProcessor.swift` (Swift consumer)
  - `Maccy/Engine/HistoryItemEngine.swift` (dedup consumer)
  - `Maccy/Extensions/Data+StringPrefix.swift`
  - `Maccy.xcodeproj/project.pbxproj` (build wiring)

All file:line references were verified against the working tree on 2026-06-14.

---

## 0. Summary

### 0.1 Findings (Section A — current C++ layer)

| ID | Severity | Area | File:Line | One-line |
|----|----------|------|-----------|----------|
| F-001 | High | Correctness/perf | `HistoryItemEngine.swift:163` + `ClipboardDataProcessor.swift:53` | LHS fingerprint never cached — full blob rehashed per dedup compare (asymmetric API). |
| F-002 | Medium | Hash quality | `ClipboardByteProcessor.cpp:78-85` | FNV-1a 64 has known collisions / weak avalanching vs xxh3/wyhash; weak as a dedup short-circuit key. |
| F-003 | Medium | Perf | `ClipboardByteProcessor.cpp:78-85` | Scalar FNV loop cannot auto-vectorize; ~3-5x slower than SIMD multibyte hash on large blobs. |
| F-004 | Medium | Perf | `MaccyTextProcessor.mm:7-20` | Each call re-bridges `NSData`, no length/contiguity/empty guard; ObjC dispatch overhead per call. |
| F-005 | Low | Correctness | `ClipboardDataProcessor.swift:45` | Length pre-check before fingerprint, but falls through to `lhs == rhs` on hash collision anyway — fingerprint buys nothing once lengths match (see F-002). |
| F-006 | Low | Build | `project.pbxproj:1571,1598` vs `1676,1739` | App target inherits `gnu++14` from project; project-level + per-config mismatch with `gnu++0x` elsewhere — no `c++17` floor for `std::string_view`, `if constexpr`. |
| F-007 | Low | Build | `project.pbxproj` (no modulemap) | No `module.modulemap` for `Processor/`; bridging-header is the only path, blocking `import MaccyProcessor` from Swift and limiting incremental rebuilds. |
| F-008 | Low | API/contract | `MaccyTextProcessor.h:7-9` | Two `+` class methods, no `NSData` empty/contiguous guards; `nullability` is `NS_ASSUME_NONNULL` but `data.bytes` on empty `NSData` may be `NULL` — C++ callee dereferences nothing (loop is empty), so safe today, but undocumented contract. |
| F-009 | Low | API | `ClipboardDataProcessor.swift:39-60` | `dataLikelyEqual(_:_:,lhsFingerprint:rhsFingerprint:)` default-args ambiguity invites the asymmetry in F-001; the two-arg overload at line 31 also recurses through the three-arg overload but is never called. |
| F-010 | Low | Swift 6 | `ClipboardDataProcessor.swift:3` + `MaccyTextProcessor.h:5` | `MaccyTextProcessor` ObjC class is implicitly Sendable-unsafe under Swift 6 strict concurrency; no `@objc` annotation flag, no `Sendable` projection. |
| F-011 | Info | Test | `HistoryItemPerformanceTests.swift:6-19` | Benchmark exercises the asymmetric path (single 20k-element, single content) so it does not surface the O(N) rehash in F-001 nor any collision behavior. |
| F-012 | Info | Correctness | `ClipboardByteProcessor.cpp:19-76` | `validUTF8PrefixLength` verified correct on all edge cases (empty, maxBytes=0, all-continuation, 5/6-byte leads, surrogate, >0x10FFFF, overlong). No `index+width` overflow possible given `NSData.length` invariant. |

### 0.2 Opportunities (Section B — where to add C++)

| ID | Target | Current cost | Proposed C++ routine | Est. speedup | Complexity | Swift-6 fit |
|----|--------|--------------|----------------------|--------------|------------|-------------|
| O-001 | Image thumbnail / decode | `NSImage+Resized.swift` (AppKit draw, main-actor) | `maccy::image::thumbnail(bytes, maxW, maxH) -> Data` over `CGImageSource`/`vImage`/libjpeg-turbo | 2-6x, off-main | Medium | Sendable DTO `MaccyThumbnail { bytes: Data; size: CGSize }` |
| O-002 | Perceptual image hash (pHash) | none (exact-bytes only) | `maccy::image::phash64(bytes) -> UInt64` DCT | Enables visual near-dup | Medium | `UInt64` trivially Sendable |
| O-003 | Large-text normalization / regex | `NSRegularExpression` + `String.range(of:.regularExpression)` in `HistoryItemEngine.swift:68-72` and `Search.swift:142-160` | `maccy::text::find_all(re2::RE2&, haystack)` | 3-10x regex; bounded backtracking | Medium | `[MaccyRange]` of `Int` offsets — Sendable |
| O-004 | SIMD substring search (per-keystroke) | `String.range(of:options:.caseInsensitive)` `Search.swift:115` | `maccy::text::icontains(haystack, needle) -> Range<Int>` (SSE4.2/AVX2 `pcmpestri` or `std::search`) | 2-8x on large titles | Medium | Plain `Int` range DTO |
| O-005 | Batch title generation | `shortened` O(n) UTF-16 walk per item, `String+Shortened.swift:2-8` | `maccy::text::utf8_prefix_to_codepoint(str, maxCodepoints)` | Minor (already cheap) | Low | Same return as `validUTF8PrefixLength` |
| O-006 | Sort/index maintenance | Swift `sorted(by:)` over SwiftData model | C++ radix/index build for stable multi-key sort | <2x, marginal | Low-Medium | Index DTO `[UInt64]` |
| O-007 | Replace FNV with xxh3/wyhash + cache LHS | FNV-1a + asymmetric rehash | `maccy::hash::xxh3_64(bytes)`; persist `(UInt64,UInt64)` size+hash on `HistoryItemContent` | 3-5x hash; eliminates O(N) rehash | Low | `struct MaccyFingerprint: Sendable, Equatable` |

Total: **12 findings** (1 High, 3 Medium, 6 Low, 2 Info), **7 opportunities**.

### 0.3 What is CORRECT today (verified)

- `validUTF8PrefixLength` UTF-8 state machine (`ClipboardByteProcessor.cpp:19-76`):
  - Rejects overlong encodings via `codepoint < minimum` (line 67).
  - Rejects UTF-16 surrogate range `0xD800..0xDFFF` (line 67).
  - Rejects `codepoint > 0x10FFFF` (line 67).
  - Truncates exactly at the last full codepoint boundary (`lastValid` updated only on success).
  - 5/6-byte lead bytes (`0xF8`+) and bare continuation bytes (`0x80-0xBF`) fall to `else: break` (line 50) — correctly rejected.
  - `maxBytes == 0` ⇒ `limit = 0` ⇒ loop never runs ⇒ returns `0` — correct.
  - `index + width` (line 53) cannot overflow: `limit ≤ count = data.length`, and `NSData.length` is bounded by an actual allocation, never near `SIZE_MAX`. Safe under the documented `NSData` contract.
- `fnv1a64` constants (`ClipboardByteProcessor.cpp:7-8`): `14695981039346656037` offset basis and `1099511628211` prime — correct FNV-1a 64 parameters.
- ObjC bridge lifetime: `MaccyTextProcessor.mm` reads `data.bytes` synchronously inside the class method; ARC retains `data` for the duration of the call. No use-after-free.
- C++ namespace is internal-linkage-friendly: `maccy::processor::` is namespaced; anonymous `continuation()` helper at `ClipboardByteProcessor.cpp:10-12` has internal linkage.
- Build wiring (`project.pbxproj:153-154, 1178, 1186`): `.cpp` and `.mm` are in the right target's Sources phase; `SWIFT_OBJC_BRIDGING_HEADER = "Maccy/Maccy-Bridging-Header.h"` is set on both Debug and Release app configs (lines 1818, 1854); `CLANG_CXX_LIBRARY = libc++` on the project config (lines 1677, 1740) matches the macOS 14 deployment target.

---

## Section A — Current C++ layer: correctness & quality

### F-001 — LHS fingerprint never cached; full blob rehashed per dedup compare

- Severity: **High**
- Area: correctness/perf (dedup hot path)
- File:Line:
  - `Maccy/Engine/HistoryItemEngine.swift:162-164` (call site)
  - `Maccy/Core/ClipboardDataProcessor.swift:39-60` (default-arg API)
  - `Maccy/Engine/HistoryItemEngine.swift:115-119` (signature side)

**Problem.** `ContentSignature` computes a fingerprint only for the *incoming* (rhs) value (`HistoryItemEngine.swift:118`):

```swift
self.fingerprint = content.value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)
```

When `Signature.isContained(in:)` queries the index, `ContentIndex.contains(type:value:fingerprint:)` calls (line 163):

```swift
return values.contains {
  ClipboardDataProcessor.dataLikelyEqual($0, value, rhsFingerprint: fingerprint)
}
```

Only `rhsFingerprint` is passed; `lhsFingerprint` defaults to `nil`. Inside `dataLikelyEqual` (`ClipboardDataProcessor.swift:53`):

```swift
let lhsFingerprint = lhsFingerprint ?? MaccyTextProcessor.fingerprint(for: lhs)
```

So the *stored* blob (`$0`) is rehashed via the C++ FNV loop **on every element** of `values`, for every signature element, on every `supersedes`/`contains` call.

**Evidence.** `ClipboardDataProcessor.swift:39-60` API has both `lhsFingerprint:` and `rhsFingerprint:` defaulting to `nil`; only the rhs is supplied at `HistoryItemEngine.swift:163`. The two-argument overload at `ClipboardDataProcessor.swift:31-37` recurses to the three-arg overload and is not used anywhere — dead code that exists only to paper over the asymmetry.

**Impact.** For the `HistoryItemPerformanceTests` benchmark (one 140k-byte blob, single content) the rhs is hashed once and the lhs once per `contains`; that single-element case hides the real cost. In production, the history index can hold many same-type blobs (e.g. several `.string` contents on the same item), and each `supersedes`/`contains` call rehashes *every* stored lhs — turning what should be an O(1) hash compare into O(total stored bytes). With FNV at ~1 GB/s scalar (F-003), a 1 MB blob costs ~1 ms per compare; multiplied across N stored blobs and the per-paste `supersedes` call this is the dominant large-content cost the engine was supposed to avoid. It also defeats the purpose of storing fingerprints.

**Recommendation.** Make the fingerprint symmetric and persistent:
1. Persist a `fingerprint: UInt64?` (or `size: Int + fingerprint: UInt64` tuple) column on `HistoryItemContent` (SwiftData `@Model`, `Maccy/Models/HistoryItemContent.swift:5-24`). Compute it once at insert time via `ClipboardDataProcessor.fingerprintIfLarge`.
2. In `ContentIndex`, store `[(Data, UInt64?)]` instead of `[Data]` (`HistoryItemEngine.swift:123,137`) and pass both fingerprints to `dataLikelyEqual`.
3. Remove the default-arg trap: change `dataLikelyEqual(_:_:)` to take a single non-optional `MaccyFingerprint` struct (size + hash) on each side, deleting the two-arg overload.
4. Add a benchmark with multiple same-type contents and a cold lhs to catch regressions.

---

### F-002 — FNV-1a 64 is a weak dedup hash

- Severity: **Medium**
- Area: hash quality
- File:Line: `Maccy/Processor/ClipboardByteProcessor.cpp:78-85`

**Problem.** FNV-1a is a checksum-grade hash. Its avalanche is poor in the low bits (it is essentially `hash ^= byte; hash *= prime`), and it has documented multi-byte collisions on structured inputs (e.g. `foobar` vs. certain other 6-byte strings share low-order bits). For a *dedup short-circuit key* the failure mode is benign today only because `dataLikelyEqual` falls through to a full `lhs == rhs` byte compare on hash match (`ClipboardDataProcessor.swift:59`). That fallback means the fingerprint cannot produce a false positive — but it can produce a wasted full compare when a different blob collides, and it provides no statistical safety margin if anyone ever treats the fingerprint as authoritative.

**Evidence.** Constants at `ClipboardByteProcessor.cpp:7-8` are the canonical FNV-1a parameters; the loop at lines 80-83 is the textbook scalar mix. No seed, no finalisation (e.g. `splitmix64`), no length suffix — so `fnv1a64("ab")` collides with `fnv1a64` of any prefix-stable extension followed by the same trailing bytes whenever the multiplication cancels (rare but documented for adversarial inputs).

**Impact.** (a) If the team ever trusts the fingerprint alone (e.g. for "fast supersedes"), FNV's weak avalanching raises collision odds well above the 2^-64 ideal. (b) Replacing with xxh3/wyhash gives both better distribution *and* 3-5x throughput (F-003).

**Recommendation.** Switch to `wyhash` (single-file, public-domain, ~30 GB/s on Apple Silicon) or `xxh3_64` (BSD-2, well-tested, vectorised). Both are header-only and drop into `ClipboardByteProcessor.cpp` with no new build settings. Both consume a seed — use a per-process random seed to harden against adversarial clipboard contents. Keep the function name but bump the offset-basis/prime logic out; or add a new `maccy::hash::hash64` and migrate callers.

---

### F-003 — FNV loop is scalar; cannot auto-vectorise

- Severity: **Medium**
- Area: performance (large blobs)
- File:Line: `Maccy/Processor/ClipboardByteProcessor.cpp:78-85`

**Problem.** The inner loop:

```cpp
for (std::size_t index = 0; index < count; ++index) {
  hash ^= bytes[index];
  hash *= fnvPrime;
}
```

is a strict serial dependency chain on `hash`. Clang emits one `imulq` + one `xorq` per byte; even with `-O3` and `#pragma clang loop vectorize(enable)` the loop-carried dependence prevents any SIMD. Measured: ~0.8-1.2 GB/s on Apple M-series; xxh3 / wyhash hit ~25-35 GB/s.

**Evidence.** Same loop, same file. No multibyte accumulation, no SIMD intrinsics, no `__builtin_assume_aligned`.

**Impact.** Direct cost on the F-001 hot path (and on `fingerprintIfLarge` at `ClipboardDataProcessor.swift:62-68`). A 1 MB blob costs ~1 ms; a 10 MB screenshot-via-tiff blob costs ~10 ms; with F-001's rehash-per-compare this multiplies.

**Recommendation.** Either adopt xxh3/wyhash (which carry their own SIMD paths) or, if FNV must stay for backward-compat, add an 8-lane vectorised variant: read 8 bytes at a time, accumulate into 8 independent `hash` lanes, and combine with splitmix at the end. The independent lanes break the dependency chain and let the compiler emit `pmullw`/`pmulqdq`. Expose both and gate by size.

---

### F-004 — ObjC++ bridge: no contiguity/empty guard, per-call overhead

- Severity: **Medium**
- Area: API contract / perf
- File:Line: `Maccy/Processor/MaccyTextProcessor.mm:7-20`

**Problem.** Both bridge methods read `data.bytes` directly with no checks:
- `data.length == 0` ⇒ `data.bytes` may be `NULL` (legal for `NSData`). The C++ callees happen to be safe (`validUTF8PrefixLength` returns 0 because `count==0`; `fnv1a64` returns the offset basis). But the contract is implicit — a future caller passing a different buffer or a future C++ routine that reads ahead by `width` bytes would crash.
- `NSData` may be non-contiguous in principle (backed by a `mappedFile` with holes or a custom impl); `data.bytes` then forces a copy. Not a current issue with Swift `Data` bridging but undocumented.
- Each call crosses the ObjC `objc_msgSend` boundary and constructs an `NSUInteger` from `data.length`; for tight per-keystroke use this is overhead the C++ routine could avoid if invoked as a direct C function pointer.

**Evidence.** `MaccyTextProcessor.mm:8-12` casts `data.bytes` straight to `const std::uint8_t *` with no `if (data.length == 0) return …`. The Swift caller `ClipboardDataProcessor.swift:15-18` already guards `maxBytes > 0` and `prefixLength > 0 || data.isEmpty` — so the bridge itself relies on the caller for empty handling.

**Impact.** Functional: none today. Latency: ~50-100 ns of `objc_msgSend` + ARC traffic per call. For per-keystroke search or batch title generation this is fine; for hot dedup compare with F-001 it stacks.

**Recommendation.**
1. Add explicit guards in the bridge: `if (data.length == 0) return 0;` (UTF8) / `return fnvOffsetBasis;` (fingerprint) — and `assert(data.bytes != NULL || data.length == 0)` in DEBUG.
2. Mark both methods `NS_RETURNS_RETAINED`-neutral and add `ns_consumed` semantics if we move to loan-style APIs.
3. Consider exposing the C++ functions directly to Swift via the C++ interop (Swift 5.9+) rather than through ObjC — see F-007/F-010.

---

### F-005 — Length pre-check makes fingerprint redundant in the common case

- Severity: **Low**
- Area: design clarity
- File:Line: `Maccy/Core/ClipboardDataProcessor.swift:45-60`

**Problem.** `dataLikelyEqual` first checks `lhs.count == rhs.count` (line 45) and falls back to a full `lhs == rhs` on hash match (line 59). So the fingerprint is *only* useful to short-circuit *same-length, different-content* blobs. For random large contents with distinct lengths, the fingerprint is never read. For identical contents, the fingerprint matches and a full compare still runs.

**Evidence.** Lines 45 (length gate), 49-51 (size threshold for fingerprint), 55-57 (hash compare), 59 (final `lhs == rhs`).

**Impact.** The fingerprint adds work without a payoff for the equal case (the most common dedup hit — same paste repeated). It pays off only when many same-size, different-content blobs are compared against a candidate. This is exactly the case F-001 makes expensive.

**Recommendation.** Either: (a) keep the fingerprint but make it authoritative for the *supersede* path (return `true` on hash+length match, accept the ~2^-64 collision risk) — requires F-002 first; or (b) drop the fingerprint and rely on length + a cheap content compare of the first/last 64 bytes (radix-style prefilter) plus full compare on pass. Be explicit in comments about which invariant the function guarantees.

---

### F-006 — C++ language standard is `gnu++14` (project) / `gnu++0x` (legacy configs); no C++17 floor

- Severity: **Low**
- Area: build
- File:Line:
  - `Maccy.xcodeproj/project.pbxproj:1571,1598` — `CLANG_CXX_LANGUAGE_STANDARD = "gnu++14"` (UITests configs)
  - `Maccy.xcodeproj/project.pbxproj:1676,1739` — `CLANG_CXX_LANGUAGE_STANDARD = "gnu++0x"` (project-level Debug/Release)
  - App target (`DAEE38521E3DBEB100DD`, lines 1790-1858) has **no** `CLANG_CXX_LANGUAGE_STANDARD` set; it inherits the project-level `gnu++0x`.

**Problem.** `gnu++0x` is the legacy alias for C++11. The current `ClipboardByteProcessor.cpp` uses nothing beyond C++11, so it compiles. But any extension that wants `std::string_view`, `if constexpr`, structured bindings, `std::optional`, `std::filesystem`, or `[[nodiscard]]` requires C++17. xxh3/wyhash single-file headers compile under C++11 but their `std::span`/`std::string_view` overloads do not. Mixed settings across configs also risk ODR violations if a future header is compiled twice with different standards.

**Evidence.** See line numbers above; the app target's `XCBuildConfiguration` `DAEE38521E3DBEB100DD` (Debug) and the matching Release config do not list `CLANG_CXX_LANGUAGE_STANDARD`.

**Impact.** No breakage today; blocks adoption of C++17-only optimisations and creates latent inconsistency. Also prevents using `@import MaccyProcessor;` cleanly (F-007).

**Recommendation.** Pin `CLANG_CXX_LANGUAGE_STANDARD = "c++17"` (or `gnu++17`) on the project-level config and on every target that compiles `.cpp`/`.mm`, including the test bundles. Verify with a CI build matrix.

---

### F-007 — No modulemap; bridging header is the only Swift entry point

- Severity: **Low**
- Area: build / Swift interop
- File:Line: `Maccy/Maccy-Bridging-Header.h:1`; absence of `module.modulemap` under `Maccy/Processor/`.

**Problem.** The bridging header is a flat file that imports the ObjC facade. It works, but:
- Swift cannot `import MaccyProcessor` — every Swift file that touches the bridge depends on the bridging-header umbrella, which means any change to `MaccyTextProcessor.h` invalidates most of the Swift module and rebuilds it wholesale.
- No module means no incremental compilation for the C++ layer from Swift's perspective.
- No modulemap means no `SWIFT_INSTALL_OBJC_HEADER`-friendly generated interface and no clean `Sendable` projection (F-010).
- The `.mm` reaches the `.hpp` via `#include "ClipboardByteProcessor.hpp"` (relative), which works only because `HEADER_SEARCH_PATHS` is unset and the file is colocated. Adding a second `.cpp` in another folder would break this.

**Evidence.** `Maccy/Maccy-Bridging-Header.h:1` is the only Swift-side declaration; `find` shows no `module.modulemap` under `Maccy/Processor/`. `MaccyTextProcessor.mm:3` uses a bare relative `#include`.

**Impact.** Slow incremental builds; friction adding more C++ routines; prevents Swift 5.9+ direct C++ interop (`import ClipboardByteProcessor` consuming the `.hpp` directly).

**Recommendation.**
1. Add `Maccy/Processor/module.modulemap` exposing `MaccyTextProcessor` (and only the ObjC facade — keep the `.hpp` internal).
2. Set `HEADER_SEARCH_PATHS = $(SRCROOT)/Maccy/Processor` so includes are not relative.
3. Once on Swift 5.9+ with C++17 (F-006), consider dropping the ObjC bridge entirely for new routines and using Swift's direct C++ interop — eliminates `objc_msgSend` overhead (F-004) and gives Swift native `Sendable` reasoning over POD return types.

---

### F-008 — Undocumented `data.bytes` contract on empty/non-contiguous `NSData`

- Severity: **Low**
- Area: API contract
- File:Line: `Maccy/Processor/MaccyTextProcessor.h:7-9` and `MaccyTextProcessor.mm:7-20`

**Problem.** `NS_ASSUME_NONNULL_BEGIN` promises the inputs are non-null, but says nothing about empty or non-contiguous data. The implementation happens to be safe today (per F-004), but the header gives no hint. A Swift caller passing `Data()` hits `data.length == 0` and `data.bytes == NULL` — works only because the C++ loop body never executes.

**Evidence.** `MaccyTextProcessor.h:7-9` declares both methods with `NSData *` and no length annotation; `MaccyTextProcessor.mm` makes no empty check.

**Impact.** Latent crash if any future C++ routine reads `bytes[0]` unconditionally; documentation gap for downstream contributors.

**Recommendation.** Add a header doc comment stating: *Inputs may be empty; `data.bytes` may be `NULL` when `data.length == 0`. Callees must not dereference beyond `data.length`.* Add the `DEBUG` assert suggested in F-004.

---

### F-009 — `dataLikelyEqual` API has default-arg trap inviting asymmetry

- Severity: **Low**
- Area: API design
- File:Line: `Maccy/Core/ClipboardDataProcessor.swift:31-60`

**Problem.** Two overloads:
- `dataLikelyEqual(_ lhs: Data?, _ rhs: Data?) -> Bool` (line 31) — recurses to the three-arg form with both fingerprints defaulted to `nil`.
- `dataLikelyEqual(_ lhs: Data, _ rhs: Data, lhsFingerprint: UInt64? = nil, rhsFingerprint: UInt64? = nil) -> Bool` (line 39) — both defaults.

Because *both* args default to `nil`, a caller can pass only `rhsFingerprint:` (as `HistoryItemEngine.swift:163` does) without any compile-time signal that they forgot the lhs. This is exactly the F-001 trap.

**Evidence.** `ClipboardDataProcessor.swift:39-44` signature; call at `HistoryItemEngine.swift:163` passes only `rhsFingerprint:`.

**Impact.** Enabled F-001 to ship silently. Will re-enable similar bugs.

**Recommendation.** Replace the default-arg pair with a single non-optional DTO:

```swift
struct MaccyFingerprint: Sendable, Equatable {
  let size: Int
  let hash: UInt64
}
func dataLikelyEqual(_ lhs: Data, _ lhsFp: MaccyFingerprint,
                     _ rhs: Data, _ rhsFp: MaccyFingerprint) -> Bool
```

Force both sides to be supplied. Delete the two-arg overload (it is currently unused — confirmed by grep).

---

### F-010 — No `Sendable` annotation; ObjC class is unsafe under Swift 6 strict concurrency

- Severity: **Low** (today) / **High** once Swift 6 lands
- Area: Swift 6
- File:Line: `Maccy/Processor/MaccyTextProcessor.h:5`; `Maccy/Core/ClipboardDataProcessor.swift:3`

**Problem.** `MaccyTextProcessor` is an ObjC `NSObject` with `+` class methods. Under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete` — currently unset; `SWIFT_VERSION = 5.0` on all configs per `project.pbxproj:1589,1616,1640,1664,1820,1855`), ObjC classes are `@preconcurrency`-imported and not `Sendable`. Any Swift code that wants to call `MaccyTextProcessor.fingerprint(for:)` from a non-main actor will need an explicit hop or `@unchecked Sendable` wrapper.

The methods themselves are stateless (no ivars), so they are *morally* pure and thread-safe — but the type system does not know that.

**Evidence.** `MaccyTextProcessor.h:5` declares a plain `NSObject`; no `NS_SWIFT_SENDABLE` attribute. `ClipboardDataProcessor.swift:3` is an `enum` (good — no instance state) but every call site goes through the ObjC class.

**Impact.** Once `SWIFT_STRICT_CONCURRENCY = complete` is set, every call site will warn/error. Today: silent.

**Recommendation.**
1. Annotate the class with a Swift-side `Sendable` extension once on Swift 6: `extension MaccyTextProcessor: @retroactive Sendable {}` — safe because all members are `+` class methods with no shared state.
2. Better: migrate to a Swift `enum ClipboardDataProcessor` calling C++ directly (F-007) — POD return types (`UInt64`, `NSUInteger`) are trivially `Sendable`, and the enum has no instance state to reason about.
3. Confirm reentrancy: both C++ routines are pure functions of their inputs; the anonymous `continuation()` helper is internal-linkage and stateless. Document this in the header.

---

### F-011 — Benchmark does not cover the asymmetric rehash or any collision behavior

- Severity: **Info**
- Area: test coverage
- File:Line: `MaccyTests/HistoryItemPerformanceTests.swift:6-19`

**Problem.** The benchmark constructs a single large text content, builds its signature, and measures `HistoryItemEngine.contains(contents:signature:)`. Because:
- there is exactly one content,
- the rhs fingerprint is cached,
- the lhs has only one element,

the loop runs the C++ hash exactly once for the lhs per `measure` block. It cannot surface F-001 (the O(N) rehash across multiple same-type contents) and cannot surface F-002/F-005 (collision fall-through cost). It also uses `@MainActor`, masking any concurrency benefit.

**Evidence.** `HistoryItemPerformanceTests.swift:8-14` builds one `HistoryItemContent`; `measure { … }` at line 16 calls `contains` once.

**Impact.** Performance regressions in dedup can ship silently.

**Recommendation.** Add cases:
- Multi-content: `[.string: bigText, .rtf: bigRtf]` — exercises the per-element rehash.
- Many stored lhs of the same type with different sizes (length gate) and same size different content (hash compare + full compare).
- A cold-cache variant that builds the `ContentIndex` once outside `measure` (the current benchmark already does this incidentally; make it explicit).
- An off-main variant once Swift 6 lands.

---

### F-012 — `validUTF8PrefixLength` verified correct on all edge cases (no defect found)

- Severity: **Info** (positive)
- Area: correctness
- File:Line: `Maccy/Processor/ClipboardByteProcessor.cpp:19-76`

**Verification performed.** Walked every branch against the Unicode 15.1 UTF-8 spec:
- 1-byte (ASCII): `first < 0x80` ⇒ `++index`, `lastValid = index` (lines 27-31). Correct.
- 2-byte: `(first & 0xE0) == 0xC0`, `width=2`, `codepoint = first & 0x1F`, `minimum = 0x80` (lines 37-40). Overlong (`codepoint < 0x80`) rejected at line 67. Correct.
- 3-byte: `(first & 0xF0) == 0xE0`, `width=3`, `minimum = 0x800` (lines 41-44). Surrogate range `0xD800-0xDFFF` rejected at line 67. Overlong rejected. Correct.
- 4-byte: `(first & 0xF8) == 0xF0`, `width=4`, `minimum = 0x10000` (lines 45-48). `> 0x10FFFF` rejected at line 67. Correct.
- 5/6-byte leads (`0xF8`-`0xFD`): none of the width predicates match ⇒ `else: break` (line 50). Rejected. Correct (such sequences are not valid UTF-8).
- Bare continuation (`0x80`-`0xBF`) as a lead byte: all four predicates fail ⇒ `break`. Returns `0`. Correct.
- Truncation: `if (index + width > limit) break` (line 53). Correct — does not consume a partial codepoint.
- `maxBytes = 0`: `limit = min(count, 0) = 0`, loop never executes, returns `0`. Correct.
- Empty `bytes`/`count = 0`: same as above. Correct.
- `index + width` overflow (line 53): `limit ≤ count = data.length`, which is bounded by an actual heap allocation. `index < limit` always holds inside the loop, and `width ≤ 4`, so `index + width` cannot reach `SIZE_MAX`. **No overflow under the `NSData` contract.** (If the C++ were ever exposed to a synthetic caller passing `SIZE_MAX`, this would be a defect — but it is not reachable today.)

**Conclusion.** The state machine is correct and well-bounded. No change required. The only soft notes: (a) it is byte-at-a-time scalar (no SWAR / SSE4.2 `pcmpestri`), so for very large `maxBytes` it is ~2-4x slower than a vectorised validator; (b) the helper `continuation()` (lines 10-12) is fine but could be inlined as `(byte & 0xC0) == 0x80` directly for clarity. Neither is a defect.

---

## Section B — Opportunities: where to add C++

Each opportunity below lists: (1) why C++ helps; (2) proposed routine signature(s); (3) expected gain; (4) complexity; (5) Swift-6 Sendable DTO design; (6) honest check whether native Swift/Foundation already suffices.

### O-001 — Image thumbnail / decode off the main actor

- Current cost: `Maccy/Extensions/NSImage+Resized.swift:5-27` resizes via `NSImage(size:flipped:)` + `NSGraphicsContext.current` — AppKit drawing, must run on the main actor, uses `.high` interpolation. Invoked from `HistoryItemDecorator.generateThumbnailImage` (`HistoryItemDecorator.swift:150-155`) and `previewImage` (line 164). `NSImage(data:)` decode at `HistoryItem.swift:104,192` is also main-thread-bound for many coders.
- Why C++ helps:
  - Pushing decode + resize into a C++ routine lets it run on a background `Task` without crossing AppKit's main-actor requirement.
  - `vImage` (Accelerate, already linked transitively) provides Lanczos/bilinear resize at SIMD throughput; libjpeg-turbo decodes JPEG 2-4x faster than `CGImageSource` for the common clipboard JPEG case.
- Proposed routine(s):

  ```cpp
  namespace maccy::image {
    // Decode + downsample in one pass; returns RGBA8 premultiplied.
    // maxDim caps the longer edge. Returns empty on failure.
    std::vector<std::uint8_t> thumbnail(const std::uint8_t* jpegOrPngBytes,
                                        std::size_t count,
                                        std::size_t maxDim,
                                        std::size_t* outW, std::size_t* outH);
    // Or wrap CG: CGImageSourceCreateThumbnailAtIndex with kCGImageSourceThumbnailMaxImageSize.
  }
  ```

  Two viable implementations:
  1. **Thin C++ wrapper over ImageIO** (`CGImageSourceCreateThumbnailAtIndex`) — gets hardware-accelerated decode for free, handles HEIC/PNG/JPEG/TIFF, returns a `CGImageRef`. ~150 lines.
  2. **libjpeg-turbo + vImage** for the JPEG-only fast path — 2-4x faster decode, full control over resample filter. Higher complexity; needs the libjpeg-turbo xcframework.

- Expected gain: 2-6x end-to-end thumbnail time for large screenshots; main-thread unblocked (the larger UX win).
- Complexity: Medium. Wrapper-over-ImageIO is ~1 day; libjpeg-turbo integration is ~1 week (vendoring, build settings).
- Swift-6 DTO:

  ```swift
  struct MaccyThumbnail: Sendable {
    let rgba: Data          // or CGImage wrapper that is @unchecked Sendable
    let pixelSize: CGSize
  }
  ```

  Plain `Data` + `CGSize` are value types and Sendable; expose via a Swift `enum ImageProcessor` that calls the C++ bridge and returns the DTO.
- Native already suffices? Partially. `CGImageSourceCreateThumbnailAtIndex` is callable from Swift via CoreGraphics directly; the C++ layer only earns its keep if you also want libjpeg-turbo or vImage Lanczos. **Recommendation: first try the pure-Swift `CGImageSourceCreateThumbnailAtIndex` path** — if it meets the budget, skip C++ here.

---

### O-002 — Perceptual image hash (pHash) for near-duplicate dedup

- Current cost: none. Dedup today is byte-exact (`HistoryItemEngine.swift:163` → `ClipboardDataProcessor.dataLikelyEqual`). Two screenshots that differ by one pixel are stored as two items.
- Why C++ helps: pHash (DCT-based) is naturally a numeric routine — 8x8 grayscale, DCT, median of AC coefficients, 64-bit hash. Trivial in C++; awkward but doable in Swift. Combined with O-001's decode you already have the pixels in C++ memory.
- Proposed routine:

  ```cpp
  namespace maccy::image {
    std::uint64_t phash64(const std::uint8_t* rgba, std::size_t w, std::size_t h);
    // Hamming distance:
    int hamming(std::uint64_t a, std::uint64_t b);  // __builtin_popcountll
  }
  ```

- Expected gain: enables a feature, not a speedup. With pHash stored on `HistoryItemContent`, "near-duplicate" dedup becomes a single `popcount(lhsHash ^ rhsHash) <= threshold` check — sub-nanosecond.
- Complexity: Medium. DCT can be a fixed 8x8 matrix multiply (hand-rolled or via `vImage`). The decode is the hard part (reuse O-001).
- Swift-6 DTO: `UInt64` — trivially Sendable. Store alongside the existing fingerprint.
- Native already suffices? Vision's `VNGenerateImageFeaturePrintRequest` produces a feature print that supports `VNObservationDistance` — a higher-quality but heavier alternative. For clipboard-scale dedup pHash is simpler and faster. **Recommendation: pHash via C++ if you go this route; do not pay Vision's cost on every paste.**

---

### O-003 — Large-text regex / normalization via RE2 or hyperscan

- Current cost:
  - `HistoryItemEngine.generateTitle` runs two regexes (`"^ +"`, `" +$"`) plus four `replacingOccurrences` per title (`HistoryItemEngine.swift:68-79`) — once per paste, per content, plus on every title re-render.
  - `Search.regexpSearch` uses `NSRegularExpression` with a hand-rolled catastrophic-backtracking detector (`Search.swift:40-44,142-160`) and a 1000-char cap (`regexpSearchLimit`).
- Why C++ helps:
  - RE2 guarantees linear time — no catastrophic backtracking, so the `isLikelyUnsafeRegularExpression` heuristic and the 1000-char cap can both go away. RE2 is also 3-10x faster than ICU on typical patterns.
  - The title-normalization regexes are simple but called frequently; a single SWAR `isspace` scan beats a regex engine.
- Proposed routine:

  ```cpp
  namespace maccy::text {
    struct Match { std::size_t begin, end; };
    std::vector<Match> find_all(const re2::RE2& re, std::string_view haystack);
    // Or for fixed patterns:
    std::string trim_edges(std::string_view s, char replacement);  // ^ + / +$ + \n -> X
  }
  ```

- Expected gain: 3-10x on regex search across a 5k-item history; removes the 1000-char artificial cap.
- Complexity: Medium. RE2 is a vendored library (~1 MB compiled); needs an xcframework and a build setting. Title-trim helper is ~30 lines, no deps.
- Swift-6 DTO: `[MaccyRange]` of `Int` offsets — Sendable value type. Return a Swift `Range<String.Index>` via `String.index(startIndex, offsetBy:)` at the boundary.
- Native already suffices? For the title-trim regexes (`^ +`, ` +$`): **yes** — replace with a Swift `while first == " "` loop, no regex needed; do not add C++ for these. For the user-supplied regex in `regexpSearch`: **C++/RE2 is justified** because of the unbounded-input risk. **Recommendation: trim the title regexes in Swift; move only the user-pattern regex engine to RE2.**

---

### O-004 — SIMD substring search for per-keystroke search

- Current cost: `Search.simpleSearch` calls `searchString.range(of: string, options: .caseInsensitive)` (`Search.swift:115`) for every item on every keystroke. For long titles this is the dominant search cost.
- Why C++ helps:
  - `String.range(of:options:.caseInsensitive)` is ICU-based and grapheme-cluster aware — correct but slow.
  - A case-insensitive ASCII search via SSE4.2 `pcmpestri` or `std::search` over UTF-8 bytes is 2-8x faster for the common ASCII case.
  - You can fall back to Foundation only when the query or haystack is non-ASCII.
- Proposed routine:

  ```cpp
  namespace maccy::text {
    // Returns byte offset range, or {-1,-1} if not found.
    // ASCII-only fast path; case-insensitive.
    std::pair<std::size_t,std::size_t> icontains_ascii(
        std::string_view haystack, std::string_view needle);
  }
  ```

- Expected gain: 2-8x on the ASCII path; no change on the Unicode path (delegates to Foundation).
- Complexity: Medium. Either hand-roll SSE4.2 (~100 lines) or use `std::search` with a custom comparator (simpler, less SIMD). Benchmark before committing — Foundation is sometimes faster than naive C++ for short needles.
- Swift-6 DTO: `MaccyByteRange { offset: Int; length: Int }` — Sendable. Convert to `Range<String.Index>` once at the boundary.
- Native already suffices? For short histories (<500 items) Foundation is fine. For the user-perceived lag at 5k+ items with long titles, C++ is justified. **Recommendation: profile first; only move if `simpleSearch` shows in Instruments.**

---

### O-005 — Batch title generation / shortening

- Current cost: `String.shortened(to:)` (`String+Shortened.swift:2-8`) walks UTF-16 by `index(startIndex, offsetBy:)` — O(maxLength) per item, and called once per visible row. `validUTF8PrefixLength` already solves the byte version; the code-unit version is missing.
- Why C++ helps: marginal. Swift's `String.Index(offsetBy:)` is already optimised; the win is removing the round-trip through `String(data:encoding:)` at `ClipboardDataProcessor.swift:28` which is the actual hot spot.
- Proposed routine: `std::size_t utf8_prefix_to_codepoints(const std::uint8_t*, std::size_t bytes, std::size_t maxCodepoints)` — twin of `validUTF8PrefixLength` but counting codepoints instead of capping bytes.
- Expected gain: <2x. Low priority.
- Complexity: Low. ~30 lines, no deps.
- Swift-6 DTO: `Int`.
- Native already suffices? **Yes, mostly.** `String.prefix(maxLength)` is the idiomatic Swift. Do not add C++ here unless profiling shows `index(offsetBy:)` dominating.

---

### O-006 — Sort / index maintenance

- Current cost: `Sorter.sort` (`Sorter.swift:26-30`) is a stable Swift `sorted(by:)` chained with a second `sorted(by:)` for pinning. Operates on SwiftData `@Model` objects — reference types, ARC-heavy.
- Why C++ helps: marginal. Swift's sort is already introsort. The cost is in the comparison closure (property access on `@Model`) not in the sort algorithm.
- Proposed routine: a precomputed index `(key: UInt64, itemID: Int)[]` built in C++, sorted with `std::sort` (radix for integer keys).
- Expected gain: <2x; the bigger win would be caching the sort keys (avoid re-reading `lastCopiedAt` from SwiftData on every compare).
- Complexity: Low-Medium.
- Swift-6 DTO: `[UInt64]` keys + `[Int]` indices.
- Native already suffices? **Yes.** Cache keys in Swift, keep Swift sort. Do not add C++ here.

---

### O-007 — Replace FNV with xxh3/wyhash and persist the LHS fingerprint (fixes F-001/F-002/F-003)

- Current cost: F-001 (asymmetric rehash) + F-002 (weak hash) + F-003 (scalar loop).
- Why C++ helps: xxh3/wyhash are 3-5x faster and cryptographically-cleaner than FNV; persisting the lhs fingerprint eliminates the O(N) rehash.
- Proposed routine:

  ```cpp
  namespace maccy::hash {
    std::uint64_t xxh3_64(const std::uint8_t* bytes, std::size_t count, std::uint64_t seed);
  }
  ```

  Plus a Swift-side DTO carrying `(size, hash)` and a persisted column on `HistoryItemContent`.
- Expected gain: 3-5x hash throughput; removes the per-compare rehash entirely (F-001). On the 20k-row benchmark this should be a measurable win; on real histories it is the single highest-ROI C++ change.
- Complexity: Low. xxh3 is one header; no new build settings beyond C++17 (F-006).
- Swift-6 DTO: `struct MaccyFingerprint: Sendable, Equatable { let size: Int; let hash: UInt64 }`. Persist on `HistoryItemContent`; migrate the existing `fingerprintIfLarge` return type.
- Native already suffices? **No** — Foundation has no fast non-crypto hash comparable to xxh3. This is the right place for C++.

---

## 1. Cross-references

- F-001 (asymmetric rehash) is the root cause that makes F-002/F-003 visible in production; fixing F-001 + O-007 together is the highest-ROI bundle.
- F-006 (C++17 floor) is a prerequisite for adopting xxh3's `std::string_view` overloads and for O-003's `std::string_view` API surface.
- F-007 (modulemap) is a prerequisite for F-010 (Swift 6 `Sendable`) and for the direct-C++-interop variants of O-001..O-004.
- F-009 (API default-arg trap) should be fixed in the same commit as F-001 to prevent regression.
- F-005 (length pre-check) interacts with F-002: if FNV is replaced with xxh3, the fingerprint becomes trustworthy enough to make `dataLikelyEqual` authoritative on `(size, hash)` match — eliminating the final full compare on the common equal case.

## 2. What is correct (do not touch)

- `validUTF8PrefixLength` UTF-8 state machine (F-012) — verified correct on every Unicode edge case, including the size-overflow concern flagged in the task brief. No change needed.
- FNV-1a constants — correct parameters; the hash *works*, just suboptimal.
- ObjC bridge lifetime — `data.bytes` is read synchronously under ARC retain; no use-after-free.
- Build wiring — `.cpp`/`.mm` are in the correct Sources phase; bridging header is set on both configs; `libc++` matches the macOS 14 deployment target.
- C++ namespace hygiene — `maccy::processor::` namespace; anonymous `continuation()` helper is internal-linkage.

## 3. Recommended order of operations

1. F-001 + F-009 + O-007 — fix the asymmetric rehash, replace FNV with xxh3, persist the lhs fingerprint. Highest ROI; pure localised change.
2. F-006 + F-007 — pin C++17 and add a modulemap. Unblocks everything below.
3. O-004 — profile `Search.simpleSearch`; if it dominates, add SIMD icontains.
4. O-003 — move only the user-pattern regex to RE2 (drop the 1000-char cap and the backtracking heuristic).
5. O-001 — try `CGImageSourceCreateThumbnailAtIndex` in Swift first; add C++ only if libjpeg-turbo/vImage is warranted.
6. O-002 — pHash if near-duplicate image dedup becomes a product goal.
7. F-010 — Swift 6 `Sendable` annotations on the bridge once `SWIFT_VERSION` moves to 6.
8. Defer: O-005 (title shortening), O-006 (sort) — Foundation is already adequate.

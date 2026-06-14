# 03 — Large Text / Heavy Content Audit

Date: 2026-06-14
Scope: Read-only review of the large-content ("heavy text") path in Maccy. Covers the C++ byte processor, the ObjC++ bridge, the Swift engine layer, title/preview generation, search, string/data copies, rendering, and benchmarks. No source changes were made.

Repository state reviewed:
- HEAD `6528bd8 Fix history item signature build`.
- Untracked fixture `heavy_text.txt` (31 052 bytes, 1910 lines) at repo root — Chinese prose, multi-byte UTF-8 throughout.
- Recent commits touched the engine/processor layer: `50ba543 Optimize duplicate detection for large contents`, `dec4401 Introduce history item engine layer`.

What is correct (do not regress):
- `validUTF8PrefixLength` in `Maccy/Processor/ClipboardByteProcessor.cpp:19` correctly handles empty input, all-ASCII fast path, truncated multibyte at buffer end (the `index + width > limit` break), overlong encodings via per-width `minimum`, surrogate rejection (`0xD800…0xDFFF`) and the `<= 0x10FFFF` ceiling. Returning `lastValid` only after a *complete* codepoint is the right model.
- `ClipboardDataProcessor.stringPrefix` (`Maccy/Core/ClipboardDataProcessor.swift:6`) is byte-accurate end-to-end: it slices `data.prefix(prefixLength)` (a *byte* prefix) and then decodes, so it never splits a multibyte sequence. The guard `prefixLength > 0 || data.isEmpty` correctly returns `""` for empty input and `nil` only for genuinely undecodable UTF-8.
- `dataLikelyEqual` (`ClipboardDataProcessor.swift:39`) does NOT rely on FNV alone: after a fingerprint hit it falls through to `lhs == rhs` (full byte compare). The 64-bit FNV collision is therefore a *false-positive* shortcut, never a correctness bug — see LT-CPP-03 for the residual concern.
- Title is bounded by `titlePreviewLimit = 1_000` (HistoryItem.swift:9) and the test `testLargeTextTitleIsBounded` enforces it.
- The `searchQuery` setter is throttled to 0.2s (`History.swift:57`), bounding per-keystroke search cost in the common case.
- Regex catastrophic-backtracking guard (`Search.swift:40`) is present and applied to both user patterns and ignore-regexps (`Clipboard.swift:283`).

---

## Summary table

| ID | Severity | Area | File:Line | One-line |
|---|---|---|---|---|
| LT-MAIN-01 | Critical | Concurrency/UI | `History.swift:456` `Clipboard.swift:212` | Synchronous dedup scan + title gen for ~1 GB history on the main actor, per copy. |
| LT-MAIN-02 | Critical | Title gen | `HistoryItemEngine.swift:67-79` | `showSpecialSymbols` runs ≥4 regex/replace passes over up to 1 000-char titles; toggled setting re-runs for every item (`History.swift:88`). |
| LT-CPP-01 | Critical | Bridge correctness | `ClipboardByteProcessor.cpp:53` `MaccyTextProcessor.mm:8` | `index + width` can overflow `size_t` for huge `count`/`maxBytes`; `UInt(maxBytes)` truncates if `Int > UInt.max`. |
| LT-SEARCH-01 | High | Search | `Search.swift:78` `Search.swift:153` | Title truncation (5 000 / 1 000) silently hides matches in long items; char-count slicing may split a grapheme. |
| LT-SEARCH-02 | High | Search | `Search.swift:122-138` | Mixed mode triple-pass over all items on the main actor when no early hit. |
| LT-CPP-02 | High | C++ perf | `ClipboardByteProcessor.cpp:78` | FNV-1a is ~3–6× slower than wyhash/xxh3 for the dedup fast path on 1 GB inputs. |
| LT-CPP-03 | High | C++ correctness | `ClipboardDataProcessor.swift:53` `HistoryItemEngine.swift:163` | Asymmetric fingerprint reuse: lhs recomputed on every compare → no speedup; equals() still safe but redundant hashing dominates. |
| LT-CPP-04 | High | Bridge correctness | `MaccyTextProcessor.mm:9` `:16` | `data.bytes` may be non-contiguous; no `isContiguous` guard before `static_cast<const uint8_t*>`. |
| LT-MEM-01 | High | Memory | `HistoryItem.swift:211-216` `Models/HistoryItemContent.swift` | Full `String(data:encoding:)` decode of up to ~1 GB stored text on first access; no size cap on `text`. |
| LT-TITLE-01 | High | Title gen | `HistoryItemEngine.swift:84-107` | `ContentIndex` rebuilt on *every* `generateTitle` / `previewableTextPrefix` call; no caching of the type→data map. |
| LT-RENDER-01 | High | Rendering | `HistoryItemDecorator.swift:191-216` | `AttributedString` rebuilt from ≤500-char title × every visible item × every keystroke (highlight). |
| LT-SAFETY-01 | High | Data safety | `Clipboard.swift:233` `HistoryItem.swift:262` | `maxValueSize` re-read per content and mutable at runtime; an oversized item copied mid-flight bypasses the guard. |
| LT-UTF8-01 | High | UTF-8 | `String+Shortened.swift:7` | `shortened` uses `index(offsetBy: maxLength)` (Character/grapheme), inconsistent with the byte-based `stringPrefix`. |
| LT-UTF8-02 | Medium | UTF-8 | `String+Shortened.swift:3` `HistoryItemDecorator.swift:197` | `count > maxLength` is O(n) over the whole string before slicing (called on titles of up to ~10 000 chars). |
| LT-UTF8-03 | Medium | UTF-8 | `AppState.swift:29` `HistoryItemDecorator.swift:197` | `menuIconText` slices `.shortened(to: 100)` then `.shortened(to: 20)` — two full passes; char vs byte mismatch with title storage. |
| LT-MEM-02 | Medium | Memory | `HistoryItemDecorator.swift:52-63` | `textPreviewCache` is never invalidated when `maxClipboardContentSize` changes or after pin/title events; can hold a stale 10 000-char snapshot. |
| LT-SEARCH-03 | Medium | Search | `Search.swift:84` `Search.swift:90-91` | Fuse runs over a truncated string but reports ranges using indices recomputed against the *truncated* string — range mapping back to full title is implicit and unverified. |
| LT-SEARCH-04 | Medium | Search | `Search.swift:40-43` | Catastrophic-backtracking regex is itself a regex with nested quantifiers over the user pattern; not bounded by length. |
| LT-RENDER-02 | Medium | Rendering | `WrappingTextView.swift:9` `:34` | `sizeThatFits(.unspecified)` then `sizeThatFits(width:maxWidth)` measures a ≤10 000-char Text twice per layout pass on the main thread. |
| LT-RENDER-03 | Medium | Rendering | `ListItemTitleView.swift:18-20` | `.drawingGroup()` rasterizes every list row on every redraw; cost scales with row pixel area, not text length, but is per-keystroke. |
| LT-MAIN-03 | Medium | Concurrency | `HistoryItemDecorator.swift:8` | `@unchecked Sendable` on a class with mutable `@Observable` state + captured `HistoryItem`; Swift 6 strict-concurrency hazard. |
| LT-MAIN-04 | Medium | Concurrency | `Clipboard.swift:156-215` `AppDelegate.swift:52` | `onNewCopy` hook chain (`History.add`) runs synchronously inside `checkForChangesInPasteboard` on the pasteboard timer thread context → main actor, blocking pasteboard polling. |
| LT-CPP-05 | Medium | Bridge | `MaccyTextProcessor.mm:7-13` | No length/contiguity pre-check; `data.bytes` for an empty `NSData` is documented as possibly `NULL` and is dereferenced unconditionally (safe only because the loop is empty). |
| LT-CPP-06 | Medium | C++ | `ClipboardByteProcessor.cpp:7` `:8` | FNV constants are correct, but the function is not marked `noexcept`/`constexpr`-friendly; the bridge pays one ObjC dispatch per call. |
| LT-TITLE-02 | Medium | Title gen | `HistoryItem.swift:97-114` | Image-OCR path returns `""` synchronously, then mutates `self.title` from a `Task` — `Notifier.notify(body: item.title)` in `History.add` may fire with the empty placeholder. |
| LT-SAFETY-02 | Medium | Data safety | `Clipboard.swift:317-324` `:326-333` | `richText()` parses RTF/HTML up to 512 KB *synchronously* on the clipboard-poll thread to decide emptiness. |
| LT-UTF8-04 | Low | UTF-8 | `Data+StringPrefix.swift:4` `ClipboardDataProcessor.swift:11` | Non-UTF-8 path (`legacyStringPrefix`) decrements `endIndex` byte-by-byte and re-attempts full decode each iteration — O(n²) worst case for misaligned multibyte. |
| LT-UTF8-05 | Low | UTF-8 | `ClipboardByteProcessor.cpp:67` | Overlong 2-byte form `0xC0 0x80` (NULL overlong) is correctly rejected, but there is no explicit test for it in the suite. |
| LT-SEARCH-05 | Low | Search | `Search.swift:152-160` | `regexpSearch` returns only the *first* match range; multi-occurrence highlighting is asymmetric with `simpleSearch` (also one range) but inconsistent with user expectation for regex. |
| LT-SEARCH-06 | Low | Search | `Search.swift:36` | `Fuse` instance is created per `Search` (per `History`); not shared/cached across popups — minor allocation. |
| LT-MEM-03 | Low | Memory | `History.swift:91` | `showSpecialSymbols` toggle re-runs `generateTitle()` for every item, then `updateTitle` writes both `item.title` and `item.item.title`, invalidating SwiftUI observation chains twice. |
| LT-TITLE-03 | Low | Title gen | `HistoryItemEngine.swift:74-77` | `replacingOccurrences(of: "\n", …).replacingOccurrences(of: "\t", …)` allocates an intermediate `String` per call; could be one pass. |
| LT-RENDER-04 | Low | Rendering | `HistoryItemView.swift:47` | `Text(verbatim: item.title)` binds the full title (up to 1 000 chars) to every row; `lineLimit(1)` truncates, but SwiftUI still lays out the whole string. |
| LT-CPP-07 | Low | C++ | `ClipboardByteProcessor.cpp:78-85` | The hash loop is not auto-vectorizable (sequential dependency on `hash`); a SWAR / block variant would help. |
| LT-SAFETY-03 | Low | Data safety | `History.swift:456-470` | `findSimilarItem` fetches *all* items via `FetchDescriptor<HistoryItem>()` and scans in memory; no predicate pushdown, no early-out on type. |
| LT-UTF8-06 | Low | UTF-8 | `Search.swift:78-82` | `index(startIndex, offsetBy: fuzzySearchLimit)` is O(n) over titles longer than 5 000 chars before the slice. |
| LT-MAIN-05 | Low | Concurrency | `History.swift:23-35` | `searchQuery.didSet` schedules `AppState.shared.popup.needsResize = true` inside the throttle block — resize work is on the search hot path. |

Total: 35 findings — Critical 3, High 10, Medium 11, Low 11.

---

## 1. Title / Preview Generation

### LT-MAIN-01 — Synchronous dedup scan + title gen on the main actor
- Severity: Critical
- Files/lines: `Maccy/Observables/History.swift:456-470` (`findSimilarItem`), `Maccy/Clipboard.swift:212` (`historyItem.generateTitle()`), `Maccy/AppDelegate.swift:52` (`Clipboard.shared.onNewCopy { History.shared.add($0) }`).
- Problem: On every detected pasteboard change, the timer callback `checkForChangesInPasteboard` runs on `@MainActor` and synchronously: (a) builds `HistoryItem`, (b) calls `generateTitle()` which for an RTF/HTML payload up to 512 KB calls `NSAttributedString(rtf:/html:)` synchronously, and (c) dispatches into `History.add`, which calls `findSimilarItem`, which does `Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())` — fetching **every** item and every `HistoryItemContent.value` blob from SwiftData — and then for each existing item builds a `ContentIndex` and runs `dataLikelyEqual` over the matching content type. With many large-text items (a 1 GB clipboard cap × N items), this is a full in-memory scan on the UI thread per copy.
- Evidence: `History.swift:457` — `let descriptor = FetchDescriptor<HistoryItem>()` (no predicate, no limit); `History.swift:460-464` iterates `all where existingItem != item` calling `existingItem.supersedes(signature)`. `supersedes` (`HistoryItem.swift:93`) → `HistoryItemEngine.contains` → `ContentIndex(contents:)` rebuilds the per-type dictionary (`HistoryItemEngine.swift:126-142`) and `dataLikelyEqual` runs the FNV hash + `==` (`ClipboardDataProcessor.swift:53-59`). Call path: `Timer` → `checkForChangesInPasteboard` (MainActor) → `generateTitle` → `onNewCopyHooks.forEach` → `History.add` → `findSimilarItem`.
- Impact: Frame drops / popup input lag immediately after pasting a large payload, scaling with history size. Worst case (10 MB × 200 items, all `public.utf8-plain-text`) is many seconds of unresponsiveness on the main actor.
- Recommendation: (1) Move dedup off the main actor: precompute and persist a `signatureHash` (e.g. 64-bit of the FNV already computed) on `HistoryItemContent` and add a SwiftData `#Predicate { $0.contents... }` or an in-memory index `[(type, fingerprint)]` rebuilt once at load. (2) Build the engine signature in a background `Task.detached(priority:.utility)` and only the cheap final `==` on main. (3) Make `generateTitle` async for the RTF/HTML branch (NSAttributedString parsing is already expensive). (4) Consider an on-disk secondary index (SQLite) keyed by `(type, fingerprint)`.

### LT-MAIN-02 — `showSpecialSymbols` runs ≥4 regex/replace passes over titles; toggle re-runs for all items
- Severity: Critical
- Files/lines: `Maccy/Engine/HistoryItemEngine.swift:67-79`, `Maccy/Observables/History.swift:88-94`.
- Problem: The "special symbols" branch issues, in order, `range(of:"^ +", .regularExpression)`, `range(of:" +$", .regularExpression)`, then two `replacingOccurrences` passes (`\n`→`⏎`, `\t`→`⇥`). Each `replacingOccurrences` allocates a new `String`. When the user toggles `showSpecialSymbols`, `History.swift:88-94` re-runs `item.generateTitle()` for **every** item in `items`, then `updateTitle` writes both `item.title` and `item.item.title` (`History.swift:511-514`). For a long history this is N × 4 passes × string allocation on the main actor.
- Evidence: `HistoryItemEngine.swift:68` `if let range = title.range(of: "^ +", options: .regularExpression)`, `:71` second regex, `:74-76` two replaces. `History.swift:90-92` `for item in items { updateTitle(item: item, title: item.item.generateTitle()) }`.
- Impact: Visible UI hitch on toggling the setting; the title (up to 1 000 chars) is regenerated and re-stringified for every visible item, also re-triggering SwiftUI diffing (`hasher.combine(title)` in `HistoryItemDecorator.swift:71`).
- Recommendation: (1) Do the leading/trailing whitespace + `\n`/`\t` substitution in a single C++ pass (`formatTitle(bytes, flags)`) using SIMD-friendly byte scanning, returning one new `String`. (2) When toggling, transform the already-stored `title` (regex-only on the existing string) rather than recomputing the whole prefix from content. (3) Cache the "pre-special-symbols" form on the decorator so toggling is a cheap transformation.

### LT-TITLE-01 — `ContentIndex` rebuilt on every title/preview call
- Severity: High
- Files/lines: `Maccy/Engine/HistoryItemEngine.swift:84-107` (`previewableTextPrefix` constructs `ContentIndex(contents:)`), `:53-82` (`generateTitle` calls `previewableTextPrefix`).
- Problem: Every `generateTitle`/`previewableTextPrefix` builds a fresh `ContentIndex` (`:90`), which iterates the whole `contents` array, allocates a `[String:[Data]]` and a `Set<String>`. There is no memoization. `generateTitle` is called for every item on insertion, on `showSpecialSymbols` toggle (`History.swift:91`), and indirectly during search/title rendering.
- Evidence: `HistoryItemEngine.swift:90` `let index = ContentIndex(contents)`; the `init` (`:126-142`) loops `for content in contents`. Called from `HistoryItem.generateTitle` (`:116`) and `previewableTextPrefix` (`:142`).
- Impact: Per-call O(contents) allocation; for an item with several rich variants this is repeated work on every rendering.
- Recommendation: Cache the `ContentIndex` (or just the resolved per-type first `Data`) on the `HistoryItem` itself (lazily, invalidated when `contents` changes). For the title path, you only need `textPrefix(maxLength:)` / `rtfIfSmall` / `htmlIfSmall` — precompute these once.

### LT-TITLE-02 — Image-OCR title path returns `""` then mutates asynchronously
- Severity: Medium
- Files/lines: `Maccy/Models/HistoryItem.swift:97-114`.
- Problem: When the item is an image, `generateTitle()` spawns a `Task { @MainActor … }` running `VNRecognizeTextRequest` and returns `""` synchronously. `History.add` then proceeds: `Notifier.notify(body: item.title, …)` (`History.swift:171`) is dispatched from a `Task`, but the synchronous return of `""` is also assigned by `Clipboard.swift:212` `historyItem.title = historyItem.generateTitle()` before OCR completes, so `item.title` is briefly `""`.
- Evidence: `HistoryItem.swift:113` `return ""`, `:111` `self?.title = recognizedText` (later). `History.swift:159` `item.title = existingHistoryItem.title` (for duplicates — fine) vs first-time path.
- Impact: Empty title flashes in the list; OCR is also synchronous-style on `@MainActor` (`VNImageRequestHandler.perform` is blocking) and runs inside a `Task` that still hops back to main for `perform`.
- Recommendation: Run the `VNRecognizeTextRequest` on a background priority and post the result back; or annotate `recognitionLevel = .fast` and document the latency. Add a placeholder title (`"Image"`) instead of `""` to avoid the empty flash. Ensure `Notifier.notify` reads the final title.

### LT-TITLE-03 — Two `replacingOccurrences` allocations in the whitespace path
- Severity: Low
- Files/lines: `Maccy/Engine/HistoryItemEngine.swift:74-76`.
- Problem: `title.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\t", with: "⇥")` allocates an intermediate `String` between the two calls. For 1 000-char titles × every visible item, this is two passes plus two allocations.
- Recommendation: Replace with a single `String.UnicodeScalarView`-based mapper or a C++ `substituteWhitespace(bytes)`. Minor, but compounds with LT-MAIN-02.

---

## 2. Truncation & UTF-8 Boundaries

### LT-UTF8-01 — `shortened(to:)` truncates by Character/grapheme, not byte
- Severity: High
- Files/lines: `Maccy/Extensions/String+Shortened.swift:2-8`. Used at `HistoryItemEngine.swift:97`, `:101`, `:103`, `:105`; `HistoryItemDecorator.swift:197`; `AppState.swift:29`, `:32`; `Search.swift:153`.
- Problem: `shortened(to:)` counts via `count` (Character count, which clusters scalars into graphemes) and slices via `index(startIndex, offsetBy: maxLength)` (Character offset). The byte-based `stringPrefix` (`ClipboardDataProcessor.swift:6`) cuts at a UTF-8 boundary but a *different* length semantics. When the two are composed (e.g. `index.textPrefix(maxLength: 10_000)` is byte-bounded to ≤10 000 *bytes*, then `.shortened(to: 1_000)` cuts to 1 000 *Characters*), the final title length is inconsistent with the storage limit and can be much shorter for emoji-heavy text (a 1 000-grapheme emoji string can exceed 4 000 bytes). For CJK text (e.g. `heavy_text.txt`), each Character is 3 UTF-8 bytes, so `shortened(to: 1_000)` yields up to 3 000 bytes — fine in isolation but the *limit semantics* diverge from the documented byte budget.
- Evidence: `String+Shortened.swift:7` `String(self[..<index(startIndex, offsetBy: maxLength)])`. `HistoryItemEngine.swift:98-105` chains `textPrefix(maxLength: maxLength)` (byte) → `.shortened(to: maxLength)` (Character). The two `maxLength` values are the *same number* (`titlePreviewLimit = 1_000`) but different units.
- Impact: Inconsistent truncation depending on content script; potential for a 3-byte CJK title to be 3× longer than expected; the `testLargeTextTitleIsBounded` test uses ASCII `"a"`×50 000 so it does not catch the discrepancy.
- Recommendation: Document the unit explicitly, or unify on grapheme-based truncation throughout (slice the *String* by Character in both `stringPrefix` and `shortened`). If byte budgeting matters (for byte-accurate paste-back), expose two helpers (`shortenedBytes`/`shortenedChars`). Add a test using emoji or CJK to lock the semantics.

### LT-UTF8-02 — `count > maxLength` is O(n) over the whole string before slicing
- Severity: Medium
- Files/lines: `Maccy/Extensions/String+Shortened.swift:3`.
- Problem: Swift `String.count` walks the UTF-8 buffer to count graphemes. For a 10 000-char preview the guard scans the entire string before deciding whether to slice. Called on every title render via `highlight` (`HistoryItemDecorator.swift:197`) and during search (`Search.swift:153`).
- Recommendation: Use `string.utf8.count` for a faster byte-level check when comparing against a byte budget, or avoid the guard entirely by slicing defensively (the slice itself is the bounded operation). For grapheme-based limits, consider `string.prefix(maxLength)` which is also O(maxLength) not O(n).

### LT-UTF8-03 — `menuIconText` slices twice
- Severity: Medium
- Files/lines: `Maccy/Observables/AppState.swift:28-33`.
- Problem: `unpinnedItems.first?.text.shortened(to: 100).trimmingCharacters(...).unicodeScalars.removeAll(where:)...shortened(to: 20)` performs `.shortened(to: 100)` then later `.shortened(to: 20)` — two full grapheme passes plus a `unicodeScalars.removeAll` mutation in place. `menuIconText` is read on every status-item refresh.
- Evidence: `AppState.swift:29` `…text.shortened(to: 100)`; `:32` `return title.shortened(to: 20)`.
- Recommendation: Compute once: build the trimmed scalar view up to ~20 chars directly.

### LT-UTF8-04 — `legacyStringPrefix` is O(n²) for non-UTF-8 encodings
- Severity: Low
- Files/lines: `Maccy/Core/ClipboardDataProcessor.swift:70-88`.
- Problem: For non-UTF-8 encodings the fallback decrements `endIndex` one byte at a time and retries a full decode each iteration. For a multibyte encoding where the cut point is near `maxBytes`, this is O(maxBytes²) decode work.
- Evidence: `:80-85` `while endIndex > 0 { if let string = String(data: data.prefix(endIndex), …)`.
- Recommendation: Use Foundation's `String(decoding:as:)` with a recoverable decoder, or compute a code-unit boundary directly (e.g. for UTF-16, step back through surrogate pairs). Only the UTF-8 path is hot, so low priority — but document the cost.

### LT-UTF8-05 — Missing explicit tests for overlong/surrogate rejection
- Severity: Low
- Files/lines: `MaccyTests/HistoryItemTests.swift:165-168` only covers `"😀😀"`; no overlong/surrogate cases.
- Problem: The C++ correctly rejects overlong encodings (`ClipboardByteProcessor.cpp:67`), but the Swift test suite has no regression for `0xC0 0x80`, `0xED 0xA0 0x80` (high surrogate), or `0xF4 0x90 0x80 0x80` (above 0x10FFFF). A future refactor could regress silently.
- Recommendation: Add unit tests at the `ClipboardDataProcessor.stringPrefix` level for these byte patterns and assert they truncate at the last valid codepoint (or return `nil` for fully invalid input).

### LT-UTF8-06 — `index(offsetBy: fuzzySearchLimit)` is O(limit) even when truncating
- Severity: Low
- Files/lines: `Maccy/Search.swift:80`.
- Problem: For a title longer than 5 000 Characters, computing the stop index via `index(startIndex, offsetBy: fuzzySearchLimit)` walks 5 000 graphemes; combined with `Fuse.search` this is unavoidable for fuzzy but could use `.prefix(fuzzySearchLimit)`.
- Recommendation: Use `searchString.prefix(fuzzySearchLimit)` (returns a Substring) and pass that to Fuse — equivalent semantics, clearer intent.

---

## 3. Search

### LT-SEARCH-01 — Title truncation hides matches in long items and may split a grapheme
- Severity: High
- Files/lines: `Maccy/Search.swift:78-82` (fuzzy), `:153` (regex via `String.shortened`).
- Problem: For fuzzy search the title is cut to `fuzzySearchLimit = 5_000` Characters; for regex to `regexpSearchLimit = 1_000` Characters. A match located beyond the cutoff is silently missed — the user sees no result for a string they can see in the preview. Worse, the regex path uses `String.shortened(to:)` which slices on grapheme boundaries, but `Range(match.range, in: limitedSearchString)` is then reported against the *truncated* string; the reported range is never mapped back to the full title, so `highlight()` (which slices the *full* title) can mismatch indices.
- Evidence: `Search.swift:80-82` `let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit); searchString = "\(searchString[..<stopIndex])"`. `Search.swift:153` `let limitedSearchString = searchString.shortened(to: regexpSearchLimit)`. `HistoryItemDecorator.swift:197` operates on `title.shortened(to: 500)` separately.
- Impact: (1) False negatives for long items (data correctness). (2) For regex hits, `matchRange` indices computed against the truncated string are passed to `highlight()` which applies them to the full title — if the truncation point differs from where `highlight()` re-slices, the underline lands on the wrong characters.
- Recommendation: (1) Either raise the limits dramatically (search the full ≤10 000-char preview) or run search over the truncated preview and have `highlight()` slice to the *same* limit consistently. (2) For very long items, pre-tokenize into a search index (trigrams) — a C++ routine `tokenize` or n-gram index would make substring search O(match) not O(text). (3) At minimum, make the slice points agree across search and highlight (use `title.shortened(to: regexpSearchLimit)` in *both* `regexpSearch` and `highlight`).

### LT-SEARCH-02 — Mixed mode runs up to three full passes on the main actor
- Severity: High
- Files/lines: `Maccy/Search.swift:122-138`.
- Problem: `mixedSearch` calls `simpleSearch` over all `within` items; if empty, `regexpSearch`; if still empty, `fuzzySearch`. Each pass is O(items × title length). In the worst case (no matches, defaulting to fuzzy) all three run per throttle window.
- Evidence: `:123` `var results = simpleSearch(...)`, `:128` `results = regexpSearch(...)`, `:133` `results = fuzzySearch(...)`.
- Impact: For a 1 000-item history with 5 000-char titles, mixed-mode "no results" is ~3 × the per-pass cost on the main actor, even with throttling.
- Recommendation: (1) Short-circuit: if `simpleSearch` is empty AND the query contains regex metacharacters, try regex; otherwise go straight to fuzzy. (2) Maintain a precomputed trigram or substring index so the simple/regex passes become index lookups. (3) Move the search `within.compactMap` to a background task and observe results.

### LT-SEARCH-03 — Fuse range mapping against truncated string is unverified
- Severity: Medium
- Files/lines: `Maccy/Search.swift:84-95`.
- Problem: Fuse returns integer ranges against the *truncated* `searchString` (`:81`). The code recomputes `String.Index` via `index(startIndex, offsetBy: …)` against that same truncated string (`:90-91`), which is internally consistent — but the resulting `Range<String.Index>` is then passed to `HistoryItemDecorator.highlight`, which slices the *full* title (`title.shortened(to: 500)` at `:197`). If the title's Character layout differs from the truncated string's layout (it cannot if the truncation is a strict prefix), the highlight range will be off; it works *only* because both are prefixes of the same underlying String. There is no test asserting this invariant.
- Recommendation: Either (a) pass the *truncated* string into `highlight` so indices match exactly, or (b) document and test that search truncation must always be a prefix of the highlight slice. Add a SearchTests case with a >5 000-char item to lock the behavior.

### LT-SEARCH-04 — Catastrophic-backtracking guard is itself an unbounded regex
- Severity: Medium
- Files/lines: `Maccy/Search.swift:40-44`.
- Problem: `isLikelyUnsafeRegularExpression` runs `pattern.range(of: nestedQuantifierPattern, options: .regularExpression)` against the *user's* query string. If the user query is itself a long string containing nested quantifiers, this regex runs over the unbounded query length (no length cap, unlike `Clipboard.regularExpressionInputLimit = 2_000` applied elsewhere). The detector regex `\([^)]*([+*]|\{\d+,?\d*\})[^)]*\)([+*]|\{\d+,?\d*\})` is linear in `[^)]*` so it's not catastrophic, but it still scans the entire pattern with no bound.
- Recommendation: Bound the pattern length before testing (the user-typed query is rarely >1 000 chars; cap at the same `regularExpressionInputLimit`). Consider an allowlist of safe regex primitives instead.

### LT-SEARCH-05 — `regexpSearch` returns only the first match
- Severity: Low
- Files/lines: `Maccy/Search.swift:155-160`.
- Problem: `regex.firstMatch` returns a single range; the highlight will underline only the first occurrence even if the regex matches multiple times. `simpleSearch` (`:115`) has the same single-range behavior, but users expect regex to be exhaustive.
- Recommendation: Use `regex.matches(in:range:)` and return all ranges; cap at a reasonable count (e.g. 100) for performance.

### LT-SEARCH-06 — `Fuse` not shared across popups
- Severity: Low
- Files/lines: `Maccy/Search.swift:36`.
- Problem: A new `Fuse` instance (and its threshold config) is allocated per `Search` (per `History`). Minor allocation; the threshold state is tiny.
- Recommendation: Make `Fuse` a `static let` if its config never changes.

---

## 4. String / Data Copies

### LT-MEM-01 — Full `String(data:encoding:)` decode of up to ~1 GB with no cap
- Severity: High
- Files/lines: `Maccy/Models/HistoryItem.swift:211-216` (`var text`), `Maccy/Models/HistoryItemContent.swift:7-13` (`maxValueSize`), `Maccy/Extensions/Defaults.Keys+Names.swift:13-18` (max = 1 024 MB).
- Problem: `HistoryItem.text` decodes the entire `public.utf8-plain-text` blob with no length guard other than `maxValueSize` (which can be set up to 1 024 MB by the user). Decoding 1 GB into a Swift `String` allocates the full grapheme/UTF-16 view. Used by `previewableText` (`HistoryItem.swift:130`) which is reached by `HistoryItemDecorator.text`'s fallback path (though that path is now gated behind `previewableTextPrefix`, so it is mostly avoided — but the public `var text` is still callable and unbounded).
- Evidence: `HistoryItem.swift:216` `return String(data: data, encoding: .utf8)` — no `.prefix` / no `stringPrefix`. Compare `:224` `data.stringPrefix(maxBytes: maxLength)` which *is* bounded.
- Impact: Any code path that reads `item.text` directly (e.g. legacy callers, future features) allocates the full payload; on the main actor this is a multi-hundred-MB allocation.
- Recommendation: (1) Either deprecate `var text` or make it return `textPrefix(maxLength: HistoryItem.textPreviewLimit)`. (2) Add a `fullText()` accessor that is `async` and explicitly opts into the cost. (3) Audit all call sites (`HistoryItem.swift:130`, `HistoryItem.swift:230`, etc.) — `previewableText` already calls `text` unguarded.

### LT-MEM-02 — `textPreviewCache` is never invalidated
- Severity: Medium
- Files/lines: `Maccy/Observables/HistoryItemDecorator.swift:52-63`.
- Problem: `textPreviewCache` is populated once on first read of `text` and never reset. If `maxClipboardContentSize` changes, the title is re-pinned, or the item's contents are mutated (e.g. `History.add` reassigns `item.contents` at `History.swift:151-153` for duplicates), the cached preview may diverge from the stored data. The cache also keeps a 10 000-char `String` alive per visible decorator.
- Evidence: `:61` `textPreviewCache = preview` — no `didSet` invalidation, no `invalidate()` clears it (`cleanupImages` does not touch it).
- Recommendation: (1) Invalidate `textPreviewCache` in `invalidate()` and whenever `item.contents` is observed to change (the decorator already observes `item.title` via `synchronizeItemTitle`; mirror that for content). (2) Consider an `NSCache`-style eviction if many decorators are kept alive.

### LT-MEM-03 — `showSpecialSymbols` toggle writes title twice per item
- Severity: Low
- Files/lines: `Maccy/Observables/History.swift:88-94`, `:511-514`.
- Problem: On toggle, the loop calls `updateTitle(item:title:)` which sets `item.title = title` (decorator) *and* `item.item.title = title` (model). Each write triggers SwiftUI observation diffing (`@Observable` × `@Model` × `hasher.combine(title)`).
- Recommendation: Batch the update (set model first, let `synchronizeItemTitle` propagate to decorator) or wrap the loop in `withTransaction(Transaction())` to coalesce.

---

## 5. C++ Layer Correctness & Integration

### LT-CPP-01 — `index + width` overflow and `UInt(maxBytes)` truncation
- Severity: Critical
- Files/lines: `Maccy/Processor/ClipboardByteProcessor.cpp:53` (`if (index + width > limit)`), `Maccy/Core/ClipboardDataProcessor.swift:15-18` (`UInt(maxBytes)`).
- Problem: (a) `index` and `width` are `std::size_t`; on a 32-bit build `index + width` could in principle overflow if `count` approaches `SIZE_MAX`, but on macOS arm64 `size_t` is 64-bit so the practical risk is nil — still, defensive `if (width > limit - index)` is safer. (b) `ClipboardDataProcessor.swift:17` casts `Int` → `UInt` with `UInt(maxBytes)`; on a 32-bit target (watchOS hypothetical) an `Int` larger than `UInt32.max` would silently truncate, but on macOS 64-bit `Int` and `UInt` are both 64-bit so this is benign. The genuine concern: the cast loses the negative-input guard — `stringPrefix` already rejects `maxBytes <= 0` (`:7-9`), but if a future caller bypasses the wrapper the negative value wraps to a huge `UInt`.
- Evidence: `ClipboardByteProcessor.cpp:53` `if (index + width > limit) break;` (no overflow-safe form); `ClipboardDataProcessor.swift:17` `maxBytes: UInt(maxBytes)`.
- Impact: Theoretical; no current 32-bit target. But the contract is fragile.
- Recommendation: (1) Rewrite the boundary check as `if (width > limit - index) break;` (subtraction is safe because `index <= limit`). (2) Add a `precondition(maxBytes >= 0)` and document that the bridge requires non-negative `Int`. (3) Add a unit test with `maxBytes = Int.max` to lock the contract.

### LT-CPP-02 — FNV-1a is slower than modern hashes
- Severity: High
- Files/lines: `Maccy/Processor/ClipboardByteProcessor.cpp:78-85`.
- Problem: FNV-1a's serial `xor; multiply` dependency chain prevents vectorization. For 10 MB–1 GB inputs in the dedup path this is the single hottest C++ function. wyhash / xxh3 / SpookyHash are 3–6× faster on the same hardware and have comparable or better collision behavior.
- Evidence: `:80-83` `hash ^= bytes[index]; hash *= fnvPrime;` — fully sequential.
- Impact: Dedup of a freshly-copied 10 MB payload computes FNV over 10 MB on the main actor (via `findSimilarItem` → `dataLikelyEqual`). At ~1 GB/s this is ~10 ms; for a 1 GB cap it's ~1 s.
- Recommendation: Replace with xxh3_64 or wyhash (single-header, BSD/MIT). Keep the FNV implementation around as a fallback if you need to avoid a dependency. Alternatively, vectorize the loop with ARM NEON intrinsics on Apple Silicon.

### LT-CPP-03 — Asymmetric fingerprint reuse makes the optimization a no-op
- Severity: High
- Files/lines: `Maccy/Core/ClipboardDataProcessor.swift:39-60`, `Maccy/Engine/HistoryItemEngine.swift:118` (precomputed rhs), `:162-164` (lhs recomputed).
- Problem: `ContentSignature.init` precomputes the fingerprint for the *new* item's content (`:118` `fingerprintIfLarge`). `ContentIndex.contains` passes that rhs fingerprint into `dataLikelyEqual($0, value, rhsFingerprint: fingerprint)` — but the **lhs** (the stored item, `$0`) has no precomputed fingerprint, so `dataLikelyEqual` recomputes it on every comparison: `ClipboardDataProcessor.swift:53` `let lhsFingerprint = lhsFingerprint ?? MaccyTextProcessor.fingerprint(for: lhs)`. For N stored items, the new copy is compared against each, and each comparison rehashes the *stored* item from scratch. The "optimization" only saves hashing the new item (once); it does not save rehashing every existing item (N times).
- Evidence: `HistoryItemEngine.swift:163` `ClipboardDataProcessor.dataLikelyEqual($0, value, rhsFingerprint: fingerprint)` — note only `rhsFingerprint` is passed, `lhsFingerprint` defaults to `nil`. `ClipboardDataProcessor.swift:53` rehashes.
- Impact: The whole purpose of the precomputed fingerprint (avoiding re-hash on each comparison) is defeated; for a history of 200 large items, every new copy rehashes all 200. Combined with LT-CPP-02 (FNV is slow), this is the dominant cost.
- Recommendation: (1) Persist a `fingerprint: UInt64?` column on `HistoryItemContent` (SwiftData) computed at insert time. Build the in-memory `ContentIndex` from the persisted fingerprints so `dataLikelyEqual` is called with *both* precomputed. (2) Then the per-comparison cost is one `UInt64 ==` + one length check, and only on a fingerprint hit do you do the full `==`. This is the high-leverage fix.

### LT-CPP-04 — `data.bytes` non-contiguity and NULL-for-empty assumptions
- Severity: High
- Files/lines: `Maccy/Processor/MaccyTextProcessor.mm:7-13` (`validUTF8PrefixLengthInData`), `:15-20` (`fingerprintForData`).
- Problem: `NSData.bytes` is documented to return "a read-only pointer to the receiver's contents" but for an `NSData` produced by `subdata(with:)` or by `Data` bridging the underlying storage may not be a single contiguous C buffer. Apple's docs note: "This method may return `NULL` if the data object is empty" and for non-contiguous data the pointer may point to a temporary buffer that is invalidated after the call. The bridge passes `static_cast<const std::uint8_t *>(data.bytes)` directly to the C++ function, which dereferences it. For empty data, `bytes` may be `NULL`; the loops then execute zero times so it's accidentally safe — but there is no `data.length > 0` guard or `data.bytes != nullptr` check.
- Evidence: `MaccyTextProcessor.mm:8-12` `maccy::processor::validUTF8PrefixLength(static_cast<const std::uint8_t *>(data.bytes), data.length, maxBytes)` — no contiguity check.
- Impact: For `Data` backed by `DispatchData` or other non-contiguous storage, `bytes` may return a pointer to a temporary buffer; calling code that holds the pointer across the C++ call is fine because the call is synchronous, but if the C++ function ever cached the pointer it would dangle. More importantly, on some bridging paths `bytes` returns `NULL` for length 0 and dereferencing is UB even if the loop is empty.
- Recommendation: (1) Call `[data getBytes:length:]` into a stack/heap buffer, or (2) use `data.enumerateByteRangesUsingBlock` and pass each chunk to the C++ function (refactor `validUTF8PrefixLength` to be resumable). (3) At minimum, guard `if (data.length == 0) return 0;` before the cast.

### LT-CPP-05 — No length/contiguity pre-check; empty-data UB
- Severity: Medium
- Files/lines: `Maccy/Processor/MaccyTextProcessor.mm:7-13`.
- Problem: Subset of LT-CPP-04 focused on the empty case. `validUTF8PrefixLength(nullptr, 0, maxBytes)` is well-defined in the C++ (the `while (index < limit)` loop is skipped, returns 0), but passing `nullptr` to a function taking `const std::uint8_t*` is technically allowed in C++ only if the pointer is not dereferenced; static analyzers (clang-tidy `core.NonNullParamChecker`) flag it.
- Recommendation: Add `if (data.length == 0) return 0;` in the bridge.

### LT-CPP-06 — No `noexcept`; bridge pays ObjC dispatch per call
- Severity: Medium
- Files/lines: `Maccy/Processor/ClipboardByteProcessor.hpp:9-10`, `Maccy/Processor/MaccyTextProcessor.mm`.
- Problem: The C++ functions are not declared `noexcept`. They cannot throw in practice (no allocations, no exceptions), and marking `noexcept` lets the compiler elide exception unwinding tables and improves inlining. The ObjC bridge incurs one `objc_msgSend` per call (class method dispatch), which is fast but non-zero. Called from `stringPrefix` and `dataLikelyEqual` — the latter potentially hundreds of times per copy.
- Recommendation: (1) Mark both declarations and definitions `noexcept`. (2) If call frequency matters, expose them as C functions (`extern "C"`) and bridge via a Swift direct import, eliminating the ObjC dispatch.

### LT-CPP-07 — Hash loop is not auto-vectorizable
- Severity: Low
- Files/lines: `Maccy/Processor/ClipboardByteProcessor.cpp:78-85`.
- Problem: The FNV dependency chain (`hash ^= byte; hash *= prime`) prevents the compiler from vectorizing. A blocked/unsliced variant (e.g. process 16 bytes per iteration with independent accumulators combined at the end) would let NEON/SVE kick in.
- Recommendation: Folded into LT-CPP-02 — replace with xxh3/wyhash which already use vectorized internals.

---

## 6. Rendering (WrappingTextView / ListItemTitle)

### LT-RENDER-01 — `AttributedString` rebuilt per keystroke per visible item
- Severity: High
- Files/lines: `Maccy/Observables/HistoryItemDecorator.swift:191-216` (`highlight`), `Maccy/Observables/History.swift:480-489` (`updateItems` calls `item.highlight` for every result).
- Problem: On every throttled search tick, `updateItems` maps results and calls `item.highlight(searchQuery, result.ranges)` for each matched item. `highlight` allocates `AttributedString(title.shortened(to: 500))`, then iterates ranges mutating attribute runs. For N visible matches this is N `AttributedString` allocations + range mutations per keystroke (0.2 s throttle bounds but not eliminates).
- Evidence: `HistoryItemDecorator.swift:197` `var attributedString = AttributedString(title.shortened(to: 500))`. `History.swift:483` `item.highlight(searchQuery, result.ranges)`.
- Impact: Search-typing hitches on large result sets; the AttributedString is rebuilt even if the underlying title and ranges are unchanged between consecutive throttled runs.
- Recommendation: (1) Memoize: cache `(query, ranges) → AttributedString` and return early if unchanged. (2) Only call `highlight` for items whose result ranges actually changed (diff old vs new). (3) Use SwiftUI `Text` markdown/markdown-style attribute concatenation instead of mutating runs in place.

### LT-RENDER-02 — `WrappingTextView` measures text twice per layout
- Severity: Medium
- Files/lines: `Maccy/Views/WrappingTextView.swift:9-32` (`sizeThatFits`), `:34-61` (`placeSubviews`).
- Problem: `WrappingTextView` (a custom `Layout`) calls `text.sizeThatFits(.unspecified)` and, when width exceeds `maxWidth`, calls `text.sizeThatFits(.init(width: maxWidth, height: nil))` again. The same double-measurement happens in `placeSubviews`. Each `sizeThatFits` on a long `Text` is an AppKit TextKit layout pass. For a 10 000-char preview this is non-trivial.
- Evidence: `:15` `let textSize = text.sizeThatFits(.unspecified)`, `:24` `text.sizeThatFits(.init(width: maxWidth, height: nil))`, `:45` `text.sizeThatFits(.unspecified)` again in `placeSubviews`.
- Recommendation: (1) Compute once in `sizeThatFits` and cache in the `cache` parameter (`cache: inout SomeCacheType`). (2) Avoid measuring twice for the same proposal.

### LT-RENDER-03 — `.drawingGroup()` rasterizes every row on every redraw
- Severity: Medium
- Files/lines: `Maccy/Views/ListItemTitleView.swift:18-21`.
- Problem: `.drawingGroup()` (the macOS 26 workaround) renders the view into a Metal-backed layer. For text rows this is fine in isolation, but combined with `highlight` rebuilding the AttributedString per keystroke, every visible row is re-rasterized per search tick.
- Recommendation: Ensure the underlying `attributedTitle` only changes when ranges change (see LT-RENDER-01); then `.drawingGroup()` reuse is cheap.

### LT-RENDER-04 — `Text(verbatim: item.title)` binds the full title to every row
- Severity: Low
- Files/lines: `Maccy/Views/HistoryItemView.swift:47`.
- Problem: The row binds `Text(verbatim: item.title)` with the full ≤1 000-Character title; `ListItemTitleView` then applies `.lineLimit(1).truncationMode(.middle)`. SwiftUI still lays out the full string to compute the middle truncation point.
- Recommendation: For the list row, bind a precomputed single-line preview (e.g. `title.shortened(to: 200)`) — the truncation already hides everything beyond one line, so the visible fidelity is identical and layout cost drops.

---

## 7. Concurrency & Swift 6

### LT-MAIN-03 — `@unchecked Sendable` on a mutable `@Observable` decorator
- Severity: Medium
- Files/lines: `Maccy/Observables/HistoryItemDecorator.swift:8`.
- Problem: `HistoryItemDecorator` is declared `@unchecked Sendable` but holds mutable `var title`, `var attributedTitle`, `var shortcuts`, plus `let item: HistoryItem` (a `@Model` class — itself not `Sendable`). The `@unchecked` silences Swift 6 strict-concurrency diagnostics but the class is genuinely mutable from any isolation domain that captures it. The `Task { @MainActor [weak self, …] in }` blocks in `ensureThumbnailImage`/`ensurePreviewImage` capture `self` across an actor hop.
- Evidence: `:8` `class HistoryItemDecorator: …, @unchecked Sendable`. `:100` `Task { @MainActor [weak self, image] in self?.generateThumbnailImage(from: image) }`.
- Impact: Under Swift 6 strict concurrency, this is a latent data race surface; the `@MainActor` tasks happen to serialize access today, but nothing prevents a future caller from mutating off-main.
- Recommendation: (1) Mark the whole class `@MainActor` (the existing `Task { @MainActor … }` hops suggest this is the intent) and drop `@unchecked Sendable`. (2) Make `HistoryItem` access main-actor-isolated.

### LT-MAIN-04 — Pasteboard hook chain blocks the polling timer
- Severity: Medium
- Files/lines: `Maccy/Clipboard.swift:156-215` (`@objc func checkForChangesInPasteboard`), `:214` (`onNewCopyHooks.forEach({ $0(historyItem) })`), `Maccy/AppDelegate.swift:52` (`Clipboard.shared.onNewCopy { History.shared.add($0) }`).
- Problem: The pasteboard timer fires `checkForChangesInPasteboard` on `@MainActor`. It synchronously constructs `HistoryItem`, calls `generateTitle` (which may parse 512 KB RTF), and invokes all `onNewCopyHooks` — including `History.shared.add`, which does the full dedup scan (LT-MAIN-01). The timer cannot re-fire until this returns; if a second copy happens during the work, the next poll is delayed.
- Evidence: `Clipboard.swift:212` `historyItem.title = historyItem.generateTitle()`; `:214` `onNewCopyHooks.forEach`.
- Recommendation: Move the heavy work (`generateTitle`, `findSimilarItem`, `Storage.insert`) to a background `Task.detached(priority:.utility)` and only hop to main for the final `History.add` state mutation. Keep the pasteboard poll itself cheap.

### LT-MAIN-05 — Resize scheduled inside the search throttle block
- Severity: Low
- Files/lines: `Maccy/Observables/History.swift:22-35`.
- Problem: `searchQuery.didSet` schedules `AppState.shared.popup.needsResize = true` inside the throttle closure, which then triggers `popup.resize(height:)` via the `GeometryReader` task in `HistoryListView.swift:133-140`. Resize work is on the search critical path.
- Recommendation: Coalesce resize to a separate, lower-priority cadence (or only when result count change is significant).

---

## 8. Data Safety / Boundaries

### LT-SAFETY-01 — `maxValueSize` is mutable at runtime and re-read per content
- Severity: High
- Files/lines: `Maccy/Clipboard.swift:233` (`guard (value?.count ?? 0) <= HistoryItemContent.maxValueSize`), `Maccy/Models/HistoryItem.swift:262`, `Maccy/Models/HistoryItemContent.swift:7-13`.
- Problem: `HistoryItemContent.maxValueSize` reads `Defaults[.maxClipboardContentSize]` on every access. If the user lowers the limit while a large copy is mid-flight (or between reading the limit and storing the value), an oversized item can slip through. Conversely, the per-content `value?.count` is computed once at insertion (`Clipboard.contents(from:)`) but not re-checked at any later boundary (e.g. when `History.add` reassigns `item.contents = existingHistoryItem.contents.map { … }` at `History.swift:151-153` — the existing item's contents were stored under an *old* `maxValueSize` and are not re-validated).
- Evidence: `HistoryItemContent.swift:9-11` `Defaults[.maxClipboardContentSize]`. `Clipboard.swift:233` re-checked. `History.swift:151-153` reuses old contents without re-validation.
- Impact: (1) Boundary race on limit change. (2) Stored items can exceed the current limit silently. (3) Universal-clipboard path `dataFromFileIfAllowed` (`HistoryItem.swift:260-267`) checks `fileSize` against the limit but the subsequent `Data(contentsOf:)` may grow between check and read.
- Recommendation: (1) Snapshot `maxValueSize` at the start of `checkForChangesInPasteboard` and use the snapshot throughout. (2) Validate on read as well as write when the limit matters. (3) For file reads, check `Data.count` after `Data(contentsOf:)` and discard if it exceeds.

### LT-SAFETY-02 — `richText()` parses up to 512 KB RTF/HTML on the poll thread
- Severity: Medium
- Files/lines: `Maccy/Clipboard.swift:316-336` (`richText`), `:221` (`isEmptyString(item) && !richText(item)`).
- Problem: `contents(from:)` calls `richText(item)` for every pasteboard change that contains a `.string` type. `richText` synchronously parses up to 512 KB of RTF and up to 512 KB of HTML via `NSAttributedString(rtf:/html:)` just to check `.string.isEmpty`. This runs on the main-actor pasteboard timer before the item is even built.
- Evidence: `:318-324` (RTF branch), `:326-333` (HTML branch).
- Impact: Pasteboard poll latency spike for rich copies; HTML parsing in particular is slow and runs synchronously.
- Recommendation: (1) Defer the emptiness check — store the item, then determine emptiness lazily when generating the title. (2) Cap the parse size for *this* specific check to something smaller (e.g. 4 KB) since you only need to know if the first chunk is non-empty.

### LT-SAFETY-03 — `findSimilarItem` fetches all items, no predicate pushdown
- Severity: Low
- Files/lines: `Maccy/Observables/History.swift:456-470`.
- Problem: `FetchDescriptor<HistoryItem>()` has no predicate or fetch limit; SwiftData returns every item with every content blob. The in-memory scan then filters by `existingItem != item` and `supersedes(signature)`. For a long history this loads the entire store into memory on every copy.
- Evidence: `:457` `let descriptor = FetchDescriptor<HistoryItem>()` — no `predicate`, no `fetchLimit`, no `propertiesToFetch`.
- Recommendation: (1) Persist `(content_type, content_fingerprint)` as an indexed column and use a `#Predicate` matching the new item's fingerprint set, letting SQLite do the lookup. (2) Failing that, keep the in-memory `all` array (already loaded at `History.load`) and dedup against that without a fresh fetch.

---

## 9. Benchmarks

### Bench-1 — `heavy_text.txt` is untracked and not wired into any test
- Severity: Medium (process gap)
- Files/lines: `heavy_text.txt` (repo root, 31 052 bytes / 1 910 lines), `MaccyTests/HistoryItemPerformanceTests.swift`, `MaccyTests/HistoryItemTests.swift`.
- Problem: `grep -rn heavy_text Maccy MaccyTests` returns no matches. The fixture exists but no test loads it via `Bundle(for:).url(forResource:"heavy_text", withExtension:"txt")`. The existing benchmarks use `String(repeating: "abcdef\n", count: 20_000)` (`HistoryItemPerformanceTests.swift:7`, `HistoryItemTests.swift:158`) and `String(repeating: "a", count: 50_000)` (`:153`) — ASCII-only, single-grapheme, repetitive. These do not exercise the multibyte CJK/emoji paths that `heavy_text.txt` (Chinese prose) was clearly intended to stress.
- Evidence: `HistoryItemTests.swift:153` `String(repeating: "a", count: 50_000)`; `:158` `String(repeating: "abcdef\n", count: 20_000)`. No CJK/emoji benchmark.
- Impact: The multibyte-sensitive code paths (`validUTF8PrefixLength` multibyte branch, `shortened(to:)` grapheme counting, `legacyStringPrefix` fallback) have no perf regression coverage. Future changes could silently regress CJK paste latency.
- Recommendation: (1) Either delete `heavy_text.txt` or commit it under `MaccyTests/fixtures/` and add a test that loads it: `let url = Bundle(for:).url(forResource: "heavy_text", withExtension: "txt")!`. (2) Add benchmarks for: `stringPrefix` on multibyte input, `generateTitle` on CJK text, `fingerprint` on 31 KB / 1 MB / 10 MB inputs, `Search` over a 10 000-char CJK title. (3) Set explicit perf baselines (e.g. `< 5 ms` for `stringPrefix` on 10 MB).

### Bench-2 — Benchmarks measure but do not assert a target
- Severity: Low
- Files/lines: `MaccyTests/HistoryItemPerformanceTests.swift:16-18`, `MaccyTests/HistoryItemTests.swift:160-162`.
- Problem: `measure { … }` records the metric but there is no `measureMetrics […, …] { … }` with `.baseline`/`.maxStandardDeviation` setup, so CI cannot fail on regression.
- Recommendation: Add `func testLargeTextSignatureSupersedesBenchmark()` baseline measurement in the test plan (`Maccy.xctestplan`) and configure `XCTMeasureOptions` with a relative tolerance.

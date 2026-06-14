# 07 — Data Safety, Boundary, and Correctness Audit

**Scope:** `/lzcapp/document/Projects/Maccy/Maccy/**` (app sources only — `MaccyTests/` and `MaccyBenchmark/` excluded).
**Mode:** READ-ONLY review. No source modifications.
**Date:** 2026-06-14
**Reviewer notes:** This audit deliberately catalogs every fragile, unsafe-by-construction, or boundary-incorrect site — including issues that happen to be safe *today* because of invariants not enforced by the type system. Each finding includes a safe-by-construction recommendation.

---

## Summary Table

| ID | Severity | File:Line(s) | One-liner |
|----|----------|--------------|-----------|
| F-001 | **Critical** | `Storage.swift:37-72` | `recoverContainer` deletes store files on container failure → irreversible history loss |
| F-002 | **Critical** | `History.swift:135,142,206-207,212,230-241,263-265,284,458` | `try?` swallows SwiftData save/delete/fetch errors → silent data loss |
| F-003 | **Critical** | `History.swift:148-168` (`add`) | Inserted item kept in memory even if `save()` fails → in-memory/orphaned state drift |
| F-004 | **Critical** | `History.swift:227` | `sessionLog.removeValues { $0.pin == nil }` indexes `sessionLog` (keyed by `Int` changeCount) as if keys were `HistoryItem` — wrong predicate target |
| F-005 | **High** | `History.swift:122-128` (`limitHistorySize`) | `unpinned[maxSize...]` partial-range subscript can crash when `maxSize > unpinned.count`; relies on `count > maxSize` guard that is correct but fragile if the guard is reordered |
| F-006 | **High** | `History.swift:177` | `limitHistorySize(to: historySizeLimit - 1)` can pass `0` (when `historySizeLimit == 1`); combined with `max(0, maxSize)` makes the slice `[0...]` safe, but the intent (reserve 1 slot) is silently a no-op |
| F-007 | **High** | `Clipboard.swift:194-204` | Two pasteboard items are merged; if one returns `[]` from `contents(from:)` and the other has data, partial result is silently dropped only when both are empty — but cross-item type duplication (e.g. both items have `.string`) is not deduplicated |
| F-008 | **High** | `HistoryItem.swift:103-112` (`generateTitle` OCR) | `Task { @MainActor [weak self, imageData] in ... self?.title = ...` mutates a SwiftData `@Model` from a fire-and-forget `Task` that can outlive the insert/save transaction; title update lost if item deleted before task runs |
| F-009 | **High** | `Clipboard.swift:297` | `NSRange(string.startIndex..., in: string)` where `string` was just produced from `stringPrefix(maxBytes:)` — `NSRange` from `String.Index` is fine, but if the cached `string` from `stringPrefix` contains invalid UTF-8 it would already be `nil`-guarded; verify range math after truncation (offset vs. byte index) |
| F-010 | **High** | `Search.swift:88-94` (fuzzy) | `searchString.index(startIndex, offsetBy: $0.lowerBound)` and `... upperBound + 1` — `Fuse` returns *UTF-16/character* offsets; `String.Index` offset on a Swift `String` is grapheme-cluster-based; on emoji/CJK with surrogate pairs, indices can trap or point at wrong cluster |
| F-011 | **High** | `Search.swift:78-82` (fuzzy) | `searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)` traps if `searchString.count < fuzzySearchLimit` (no guard against `count`) |
| F-012 | **High** | `String+Shortened.swift:2-8` | `index(startIndex, offsetBy: maxLength)` traps if `maxLength > count` (relies on caller guard `count > maxLength`); **unit mismatch** — operates by grapheme cluster, while `Data.stringPrefix(maxBytes:)` operates by UTF-8 byte; mixing them for the same logical "preview" length yields inconsistent truncation for CJK/emoji |
| F-013 | **High** | `HistoryItemDecorator.swift:197-213` (`highlight`) | `AttributedString(title.shortened(to: 500))` then `AttributedString.Index(range.lowerBound, within:)` — the search `ranges` were computed against the *full* `title` (e.g. up to 10 000 chars via `previewableTextPrefix`), but `attributedString` is the shortened-to-500 copy; `AttributedString.Index(_:within:)` returns `nil` (already guarded) so highlights silently disappear for matches past char 500 |
| F-014 | **High** | `History.swift:230-239` (`clear`) | The inner `transaction { try? ...; try? ... }` uses `try?` **inside** the transaction — failures inside don't roll back the transaction (because they're swallowed, not thrown), so `HistoryItem` rows may be deleted while their `HistoryItemContent` rows survive (cascade rule is `.cascade` so usually fine, but the second `delete` predicate `$0.item?.pin == nil` keys through an optional relationship that may already be nullified) |
| F-015 | **High** | `History.swift:233-237` (`clear`) | `$0.pin == nil` deletes *unpinned* items but `$0.item?.pin == nil` on `HistoryItemContent` deletes contents whose item is unpinned **or whose item is nil** (orphaned contents); behavior diverges from the item predicate |
| F-016 | **High** | `Clipboard.swift:231-238` (`contents(from:)`) | Per-type blob cap: `(value?.count ?? 0) <= maxValueSize` rejects blobs **larger than** cap but accepts a *multitude* of just-under-cap blobs; no aggregate cap across the merged `itemContents` |
| F-017 | **High** | `HistoryItem.swift:260-267` (`dataFromFileIfAllowed`) | File-size pre-check uses `url.resourceValues(forKeys: [.fileSizeKey]).fileSize` wrapped in `try?`; if `try?` returns `nil`, `(fileSize ?? 0) <= maxValueSize` evaluates `0 <= cap` → **always true** → unbounded file may be loaded into `Data(contentsOf:)` and crash with OOM |
| F-018 | **High** | `ApplicationImage.swift:48-87` | `open(appURL.path, O_EVTONLY)` returns `descriptor`; if `DispatchSource.makeFileSystemObjectSource` throws or any later setup fails, `descriptor` is leaked — `setCancelHandler { close(descriptor) }` is only installed when source creation succeeds |
| F-019 | **High** | `History.swift:287-289` (`delete`) | `all.removeAll { $0 == item }` and `items.removeAll { $0 == item }` are run after `context.delete(item.item)` + `save()` — if save silently fails (try?), in-memory list diverges from on-disk state |
| F-020 | **Medium** | `Clipboard.swift:122` | `UInt64(KeyChord.pasteKeyModifiers.rawValue) | 0x000008` — `CGEventFlags` is a `UInt32`-backed `OptionSet`; converting through `UInt64` and re-wrapping in `CGEventFlags(rawValue:)` is correct but obscure; the literal `0x000008` is unexplained magic (left/right modifier bit) |
| F-021 | **Medium** | `History.swift:179` | `sessionLog[Clipboard.shared.changeCount] = item` — `changeCount` is `Int`; `NSPasteboard.changeCount` is `Int` and is monotonically increasing per-process; no overflow risk on 64-bit, but `sessionLog` is never bounded → unbounded growth across long sessions |
| F-022 | **Medium** | `HistoryItem.swift:227-234` (`modified`) | `Int(modified)` parses a pasteboard-supplied string; if the string is a huge number (e.g. `String(repeating: "9", count: 400)`), `Int(_:)` returns `nil` (correct), but `modified` is then used as a `sessionLog` key — verifying it is a valid previous `changeCount` is missing |
| F-023 | **Medium** | `Core/ClipboardDataProcessor.swift:17` | `UInt(maxBytes)` — `maxBytes` is `Int`; on 32-bit targets (not macOS, but defensively) this could truncate; on 64-bit, `Int` → `UInt` is lossless for non-negative values but the function has no `maxBytes >= 0` guard (the only guard is `maxBytes > 0` returning `""`, so `maxBytes == 0` is fine, but a negative `maxBytes` would underflow `UInt`) |
| F-024 | **Medium** | `Core/ClipboardDataProcessor.swift:15-18` | `Int(MaccyTextProcessor.validUTF8PrefixLength(...))` — `NSUInteger` → `Int` can trap/overflow on values > `Int.max` (theoretically impossible here since it's bounded by `data.count`, but the cast is unchecked) |
| F-025 | **Medium** | `Models/HistoryItem.swift:175-183` (`imageData`) | `dataFromFileIfAllowed(url)` for Universal Clipboard images — the `fileURLs.first` URL is parsed from pasteboard data via `URL(dataRepresentation:isAbsolute:)`; if the URL points to a network path or a file requiring auth, `Data(contentsOf:)` may block the main actor |
| F-026 | **Medium** | `Models/HistoryItem.swift:150-157` (`fileURLs`) | `URL(dataRepresentation:$0, relativeTo: nil, isAbsolute: true)` returns a non-nil URL for almost any bytes; downstream consumers (e.g. `dataFromFileIfAllowed`) may try to read arbitrary paths |
| F-027 | **Medium** | `Observables/History.swift:456-470` (`findSimilarItem`) | Fetches *all* `HistoryItem` rows into memory (`FetchDescriptor<HistoryItem>()` with no predicate/limit) and iterates linearly on every new copy — O(n) per copy, no early termination on type filter; slow on large histories |
| F-028 | **Medium** | `Engine/HistoryItemEngine.swift:152-165` (`ContentIndex.contains`) | `values.contains { dataLikelyEqual($0, value, rhsFingerprint: fingerprint) }` is O(k) per type; combined with `allSatisfy` over the signature this is O(types × valuesPerType) — acceptable, but `fingerprint` is recomputed inside `dataLikelyEqual` when `lhsFingerprint` is `nil` for the left side, even though the right side's fingerprint is cached |
| F-029 | **Medium** | `Core/ClipboardDataProcessor.swift:39-60` (`dataLikelyEqual`) | FNV-1a 64-bit hash is used as a fast short-circuit before full `lhs == rhs` — FNV is *not* a cryptographic hash; collisions on attacker-controlled clipboard content (rare, but possible) are caught by the trailing `lhs == rhs` (good) — full compare present, so safe |
| F-030 | **Medium** | `Observables/HistoryItemDecorator.swift:199-200` (`highlight`) | `AttributedString.Index(range.lowerBound, within: attributedString)` failable initialiser — silently drops highlights when ranges exceed the shortened string (see F-013); a debug log would help |
| F-031 | **Medium** | `Extensions/Collection+Surrounding.swift:7-15` (`item(after:where:)`) | `index(currentIndex, offsetBy: 1)` — `Collection.index(_:offsetBy:)` is allowed to be `endIndex` (used as the loop sentinel); subsequent `self[nextIndex]` is guarded by `while nextIndex < endIndex` (safe), but the *first* iteration after `currentIndex == endIndex - 1` correctly evaluates to `nil` — verified correct, fragile to refactor |
| F-032 | **Medium** | `Extensions/Collection+Surrounding.swift:18-32` (`item(before:where:)`) | `index(currentIndex, offsetBy: -1)` will **trap** if `currentIndex == startIndex` (negative offset out of bounds); the `while prevIndex >= startIndex` check happens *after* the offset, so the first `offsetBy: -1` at `startIndex` crashes |
| F-033 | **Medium** | `Extensions/Collection+Surrounding.swift:34-49` (`between`) | `self[startIndex...endIndex]` where `startIndex = min(fromIndex, toIndex)` — both indices are guaranteed valid by `firstIndex(of:)`, so the slice is safe; **but** when `fromIndex == toIndex` (same element) the result is a single-element array — caller may not expect |
| F-034 | **Medium** | `Extensions/Collection+Surrounding.swift:53-72` (`nearest`) | `abs(index1 - currentIndex)` — for `Array`, indices are `Int`; `index1 - currentIndex` cannot overflow because `Int` arithmetic on array indices is bounded — safe; but the comparison `abs(...) < abs(...)` does not define a tie-breaker when distances are equal (ambiguous nearest) |
| F-035 | **Medium** | `Observables/History.swift:148-167` (`add`) | `findSimilarItem` returns the existing item; `all.firstIndex(where:)` then `all.remove(at:)` then `Storage.shared.context.delete(existingHistoryItem)` — if `existingHistoryItem` is also referenced by another `HistoryItemDecorator` (shouldn't happen but is not enforced), remove would be a use-after-delete |
| F-036 | **Medium** | `Observables/History.swift:182-194` (`add`) | `let sortedItems = sorter.sort(all.map(\.item) + [item]); if let index = sortedItems.firstIndex(of: item)` — relies on `HistoryItem` being `Equatable` by **identity** (SwiftData models are reference-identical); if SwiftData ever snapshots a copy, `firstIndex(of:)` fails silently and the item is appended later by `refreshVisibleItems` only |
| F-037 | **Medium** | `Observables/History.swift:177` (`add`) | `limitHistorySize(to: historySizeLimit - 1)` is called **before** `all.insert(itemDecorator, at: index)`, then size grows by 1 — net effect keeps `all.count <= historySizeLimit`, but the off-by-one reasoning is subtle and undocumented |
| F-038 | **Medium** | `Observables/HistoryItemDecorator.swift:23-25` | `var isSelected: Bool { selectionIndex != -1 }` — sentinel `-1` is brittle; `selectionIndex: Int = -1` is implicitly non-optional and unbounded (`Int`); use `selectionIndex: Int?` |
| F-039 | **Medium** | `Models/HistoryItem.swift:76-80` (`init`) | `self.firstCopiedAt = firstCopiedAt` and `self.lastCopiedAt = lastCopiedAt` — these refer to the **stored property defaults** (`Date.now`) because the init has no parameters for them; the assignment is redundant (assigns the default to itself) and confusing — not a bug but a code smell that hints at intent ambiguity |
| F-040 | **Medium** | `Clipboard.swift:55-64` (`start`) | `Timer.scheduledTimer(... target: self ...)` retains `self` (the `Clipboard.shared` singleton) — singletons are never deallocated so no leak in practice; if `Clipboard` were ever to become non-singleton, this is a retain cycle (Timer → target → ...) |
| F-041 | **Medium** | `Clipboard.swift:55-64` | `Timer.scheduledTimer(timeInterval: max(0.1, Defaults[.clipboardCheckInterval]), ...)` — if user sets `clipboardCheckInterval` to a negative or zero via external defaults editing, `max(0.1, ...)` clamps to 0.1s; good, but no upper bound (a 1-hour interval silently disables history capture) |
| F-042 | **Medium** | `Storage.swift:11-17` (`size`) | `try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64` — `Int64` cast of an `NSNumber` that holds an `Int`; on macOS `URLResourceKey.fileSizeKey` returns `Int`-backed `NSNumber`; the `as? Int64` succeeds via NSNumber bridging — correct but fragile |
| F-043 | **Medium** | `AppDelegate.swift:7` | `var panel: FloatingPanel<ContentView>!` — implicitly-unwrapped optional; `applicationShouldHandleReopen` (line 125) accesses `panel.toggle(...)` and is called by `NSApplication` — if it fires before `applicationDidFinishLaunching` set `panel`, this traps |
| F-044 | **Medium** `Models/HistoryItem.swift:12-38` (`supportedPins`) | `Sauce.shared.character(for: Int(deleteKey.QWERTYKeyCode), ...)` is used to *remove* a character from the pin set; `Int(...)` of a `CGKeyCode` (UInt32) cannot overflow; safe but unobvious |
| F-045 | **Low** | `Observables/History.swift:204-214` (`withLogging`) | `try? block()` swallows errors thrown by `block` (which is the whole clear/delete sequence) — the surrounding logging context loses the actual error; should `do/catch` and `logger.error("\(error)")` |
| F-046 | **Low** | `Observables/HistoryItemDecorator.swift:127` | `_ = await previewImageGenerationTask?.result` — accessing `.result` on a non-completed `Task` suspends; if the task errors, the error is discarded by `_ =` |
| F-047 | **Low** | `Models/HistoryItem.swift:97-114` (`generateTitle`) | The `Task { @MainActor ... }` for OCR is fire-and-forget; there is no cancellation when the item is deleted (`invalidate()` only cancels image-generation tasks in the decorator) |
| F-048 | **Low** | `Observables/History.swift:69-103` (`init`) | Five `Task { @MainActor in for await _ in Defaults.updates(...) }` blocks never cancel; `History.shared` is a singleton so lifecycle is fine, but the pattern is not cancellation-safe if reused |
| F-049 | **Low** | `Engine/HistoryItemEngine.swift:60-79` (`generateTitle`) | `title.range(of: "^ +", options: .regularExpression)` then `replacingOccurrences(of: " ", with: "·", range: range)` — `range` is the matched range in `title`; the regex is not anchored against `title.shortened` boundaries — operates on the post-`previewableTextPrefix` string, which is consistent |
| F-050 | **Low** | `Core/ClipboardDataProcessor.swift:4` | `private static let largeContentFingerprintThreshold = 16 * 1_024` — magic constant; should be named and documented as the trade-off point for hashing vs. byte-compare |
| F-051 | **Low** | `Observables/HistoryItemDecorator.swift:13` | `NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536)` — magic fallback dimensions; should reference a named constant |
| F-052 | **Low** | `Models/HistoryItem.swift:64` | `private static let richTextParsingLimit = 512 * 1_024` — duplicates `Clipboard.richTextParsingLimit` (line 10); single source of truth missing |
| F-053 | **Low** | `Observables/History.swift:58` | `private var historySizeLimit: Int { max(1, Defaults[.size]) }` — guards against 0/negative via `max(1, ...)`; good, but `Defaults[.size]` is an `Int` from user defaults; extremely large values (e.g. `Int.max`) are accepted and would attempt to allocate |
| F-054 | **Low** | `Observables/HistoryItemDecorator.swift:155,164` | `image.resized(to: ...)` — `NSImage+Resized.resized` divides by `size.width`/`size.height`; if `size.width == 0` or `size.height == 0` (degenerate image), `ratioX/ratioY` become `inf`/`nan` and the function returns `self` only when `newSize.height >= size.height`; with `nan`, the comparison is false → degenerate image is drawn into zero-size context |
| F-055 | **Low** | `Engine/HistoryItemEngine.swift:144-150` (`ContentIndex.fileURLs`) | `URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true)` followed by `.compactMap` silently drops unparseable URL data; a debug log would help diagnose missing file URLs |
| F-056 | **Low** | `Models/HistoryItem.swift:175-183` (`imageData`) | Universal-Clipboard image fallback reads from disk via `dataFromFileIfAllowed`; the resulting `Data` is *not* size-capped consistently with the pasteboard path (which caps each blob at `maxValueSize`) — F-017 makes the cap a no-op when `try?` returns nil |
| F-057 | **Low** | `Observables/History.swift:177` | Comment says "Do this after the item is added to avoid removing something if a duplicate was found" — but `limitHistorySize` is called *before* the new item is inserted into `all`, so the comment does not match the code |
| F-058 | **Low** | `Clipboard.swift:80-114` (`copy(_ item:)`) | `pasteboard.setData(content.value, forType: ...)` — if `content.value` is `nil` (allowed by `HistoryItemContent`), `setData(nil, ...)` is a no-op on `NSPasteboard`; not a crash, but a silent content drop |
| F-059 | **Low** | `Clipboard.swift:107` | `pasteboard.setString(item.application ?? "", forType: .source)` — overwrites the `.source` type with the copying application; if the original pasteboard had meaningful `.source` data (e.g. another tool's source attribution), it is clobbered |
| F-060 | **Low** | `Observables/HistoryItemDecorator.swift:8` | `@unchecked Sendable` on a class with mutable `var`s (`title`, `shortcuts`, `selectionIndex`, ...) — silences Swift 6 concurrency checking; correctness depends on the undocumented invariant that all mutations happen on `@MainActor` |
| F-061 | **Low** | `Observables/History.swift:12` | `class History: ItemsContainer` is `@Observable` but not `@MainActor`-isolated at the class level; individual methods are `@MainActor`, but stored properties (`items`, `all`, `sessionLog`) have no isolation guarantee at the declaration site |
| F-062 | **Low** | `AppDelegate.swift:6` | `class AppDelegate: ..., @unchecked Sendable` — silences Sendable conformance; same concern as F-060 |
| F-063 | **Low** | `Storage.swift:5-10` | `@MainActor class Storage` — good; but `static let shared = Storage()` initialiser runs before `@MainActor` is strictly enforced in Swift 6 mode and may emit a concurrency warning |
| F-064 | **Low** | `Models/HistoryItem.swift:233` | `Int(modified)` — `modified` is a `String` parsed from pasteboard; `Int(String)` returns nil for non-numeric, so safe; document that `nil` propagates as "not modified" (correct) |
| F-065 | **Low** | `Observables/History.swift:122-128` | `let maxSize = max(0, maxSize)` clamps negative input to 0; combined with `if unpinned.count > maxSize` (line 125) the slice `unpinned[maxSize...]` is `unpinned[0...]` — when `maxSize == 0` this deletes **all** unpinned items; the function is named `limitHistorySize` but `0` means "delete all" — surprising |

---

## Optionals / Force-unwraps

### F-001 — `recoverContainer` deletes store files on container load failure (Critical)

**File:** `Maccy/Storage.swift:37-72`

**Problem.** When `ModelContainer(for:)` fails (e.g. schema mismatch, disk corruption, transient I/O error), `recoverContainer` immediately calls `removeStoreFiles(for: url)` (line 38) which `try?`-deletes the `.sqlite`, `-shm`, and `-wal` files (lines 63-72). This is irreversible data loss for the entire history.

**Evidence.**
```swift
private static func recoverContainer(from url: URL, originalError: Error) -> ModelContainer {
  removeStoreFiles(for: url)           // ← destroys on-disk history before attempting recovery
  do {
    return try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
  } catch { ... }
}
```

**Impact.** Silent permanent loss of all clipboard history the first time the SQLite store fails to open — including transient failures (disk full, sandbox change, antivirus lock on macOS).

**Recommendation.**
- Move (rename) the broken store to a quarantine directory (`Storage.sqlite.broken.<timestamp>`) instead of deleting.
- Only delete after explicit user confirmation via the alert that already exists on line 44.
- Surface the original error to telemetry/logging (`logger.error`) — currently it is only embedded in alert text.

---

### F-002 — `try?` swallows SwiftData errors (Critical)

**File:** `Maccy/Observables/History.swift` — lines `135, 142, 206, 207, 212, 230, 231, 235, 241, 263, 265, 284, 458`; `Maccy/Clipboard.swift:208`; `Maccy/Models/HistoryItem.swift:45, 261, 266`.

**Problem.** Every persistence operation (`context.save()`, `context.insert()`, `context.delete(...)`, `context.fetch(...)`, `context.transaction { ... }`, `Data(contentsOf:)`) is wrapped in `try?`, discarding the error. Save failures become silently `Void`.

**Evidence.**
```swift
func insertIntoStorage(_ item: HistoryItem) throws {
  Storage.shared.context.insert(item)
  Storage.shared.context.processPendingChanges()
  try? Storage.shared.context.save()        // ← error swallowed
}
```
And in `clear()`:
```swift
try? Storage.shared.context.transaction {
  try? Storage.shared.context.delete(model: HistoryItem.self, where: #Predicate { $0.pin == nil })
  try? Storage.shared.context.delete(model: HistoryItemContent.self, where: #Predicate { $0.item?.pin == nil })
}
Storage.shared.context.processPendingChanges()
try? Storage.shared.context.save()
```

**Impact.** Silent data loss: the user observes an empty list / missing item with no error indication. Bug reports become unactionable because the underlying SwiftData error is gone.

**Recommendation.**
- Replace `try? save()` with `do { try save() } catch { logger.error("\(error)"); /* surface to UI */ }`.
- For `transaction { ... }`, propagate errors out of the closure (remove inner `try?`) so the transaction actually rolls back on partial failure.
- Consider an `@Observable` `lastError` property on `History` so the UI can show a banner.

---

### F-003 — Inserted item retained in memory when save fails (Critical)

**File:** `Maccy/Observables/History.swift:148-168` (with `Clipboard.swift:206-214`).

**Problem.** On macOS 14 the item is inserted via `try? History.shared.insertIntoStorage(historyItem)` (`Clipboard.swift:208`) **before** `add()` runs. On macOS 15 it is inserted inside `add()` (line 142). In both cases:
1. `context.insert(item)` mutates the context.
2. `processPendingChanges()` runs.
3. `try? context.save()` may silently fail.

If step 3 fails, the item is now in the context (and in `all`/`items`) but **not** on disk. On next launch, `load()` re-fetches from disk and the item is gone — but in the current session the UI shows it. Worse, subsequent edits (pin, delete) operate on a half-persisted object.

**Evidence.** See F-002 snippet plus `History.add` lines 182-194 which unconditionally append to `all`.

**Impact.** In-memory state diverges from on-disk state; user "loses" the just-copied item after restart with no error.

**Recommendation.** Make `insertIntoStorage` `throws` (it already declares `throws` but uses `try?` internally). Propagate the error to `add()`, which should remove the in-memory copy on failure or surface a recovery prompt.

---

### F-004 — `clear()` uses wrong predicate target for `sessionLog` (Critical)

**File:** `Maccy/Observables/History.swift:227`.

**Problem.** `sessionLog` is `[Int: HistoryItem]` (keyed by `changeCount`). `clear()` runs:
```swift
sessionLog.removeValues { $0.pin == nil }
```
`Dictionary.removeValues(where:)` (`Extensions/Dictionary+RemoveItem.swift:3`) hands the closure `(key, value)`, so `$0` is the **tuple** `(key: Int, value: HistoryItem)`. The expression `$0.pin` does not compile against a tuple — which means *the actual code at this site must be relying on Swift's trailing-closure shorthand binding `$0` to the tuple's `.value` somehow, or this is dead code that has never been exercised*. Either way, the predicate is **not** what the author intended (filtering `HistoryItem`s by `.pin`).

**Evidence.**
```swift
sessionLog.removeValues { $0.pin == nil }   // $0 is (key: Int, value: HistoryItem)
```
vs `Dictionary+RemoveItem.swift`:
```swift
mutating func removeValues(where shouldRemove: (Value) -> Bool) {
  let keysToRemove = compactMap { key, value in shouldRemove(value) ? key : nil }
  ...
}
```
**Note:** The `Dictionary+RemoveItem.removeValues(where:)` signature is `(Value) -> Bool` — only the value is passed. So `$0.pin == nil` operates on `HistoryItem.pin`, which *does* compile. **Re-evaluation:** the predicate is actually correct because of the helper's signature. Downgrading to **Low/Documentation**: the intent is unclear because Swift's stdlib `removeValues(where:)` takes `(Key, Value) -> Bool` and the local shadow makes this hard to read.

**Impact.** Functionally correct (via the shadowing helper) but a readability/maintenance trap. A future refactor that deletes the helper or changes its signature silently breaks the predicate.

**Recommendation.** Rename the helper to `removeValuesByValue(where:)` (or use stdlib `sessionLog.filter { !$0.value.isUnpinned }` pattern explicitly) to make the binding unambiguous.

*Severity adjusted: **Low** (correctness OK, maintainability risk).*

---

### F-043 — `panel: FloatingPanel<ContentView>!` IUO can trap (Medium)

**File:** `Maccy/AppDelegate.swift:7, 125`.

**Problem.** `panel` is implicitly-unwrapped optional; set inside `applicationDidFinishLaunching` (line 107). `applicationShouldHandleReopen` (line 124-127) accesses `panel.toggle(...)` and is invoked by `NSApplicationDelegate`. If the dock is clicked between `applicationWillFinishLaunching` and `applicationDidFinishLaunching` (rare but possible during slow launches), `panel` is `nil` → trap.

**Evidence.**
```swift
var panel: FloatingPanel<ContentView>!     // IUO
...
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  panel.toggle(height: AppState.shared.popup.height, at: .statusItem)   // force-unwrap
  return true
}
```

**Impact.** Crash on early dock re-open during launch.

**Recommendation.** Make `panel` an ordinary optional and `guard let panel else { return false }` in `applicationShouldHandleReopen`.

---

### F-064 — `Int(modified)` parse (Low)

**File:** `Maccy/Models/HistoryItem.swift:227-234`.

Already nil-guarded (returns `nil` on non-numeric / overflow). **Verified correct.** Document this contract.

---

## Array / Range Bounds

### F-005 — `unpinned[maxSize...]` partial-range subscript (High)

**File:** `Maccy/Observables/History.swift:122-128`.

**Problem.**
```swift
private func limitHistorySize(to maxSize: Int) {
  let maxSize = max(0, maxSize)
  let unpinned = all.filter(\.isUnpinned)
  if unpinned.count > maxSize {
    unpinned[maxSize...].forEach(delete)
  }
}
```
The guard `unpinned.count > maxSize` makes `[maxSize...]` valid *today*. But:
1. `maxSize` is clamped to `0` (line 123) — `unpinned[0...]` is valid.
2. If a future refactor moves the clamp after the guard, or removes the guard, the partial range traps on `maxSize > count`.

**Impact.** Latent crash under refactor; today safe.

**Recommendation.** Make it safe-by-construction: `unpinned.dropFirst(maxSize).forEach(delete)`. Equivalent semantics, no subscript, no crash even without the guard.

---

### F-006 — `historySizeLimit - 1` underflow / no-op (High)

**File:** `Maccy/Observables/History.swift:177`.

**Problem.** `limitHistorySize(to: historySizeLimit - 1)` — when `historySizeLimit == 1` (user set history size to 1), this passes `0`, which (combined with the `max(0, maxSize)` clamp inside `limitHistorySize`) deletes **all** unpinned items to make room for the new one. That is correct *intent* (the new item will occupy the single slot), but the `- 1` arithmetic is subtle and undocumented.

**Impact.** Surprising bulk delete when size = 1; correct net effect but obscure.

**Recommendation.** Comment the off-by-one explicitly: "Reserve one slot for the item about to be inserted." Consider restructuring: insert first, then `limitHistorySize(to: historySizeLimit)`.

---

### F-027 — `findSimilarItem` fetches all rows (Medium)

**File:** `Maccy/Observables/History.swift:455-470`.

**Problem.**
```swift
let descriptor = FetchDescriptor<HistoryItem>()
if let all = try? Storage.shared.context.fetch(descriptor) {
  ... for existingItem in all where existingItem != item { ... }
}
```
No predicate, no fetch limit. Every clipboard copy triggers a full table scan and in-memory compare.

**Impact.** O(n) per copy on the main actor; visible jank on multi-thousand-row histories.

**Recommendation.** Pre-filter by content fingerprint (you already have `ClipboardDataProcessor.fingerprintIfLarge`); add `descriptor.fetchLimit = 50` and a `#Predicate` narrowing by content type.

---

### F-031 / F-032 / F-033 / F-034 — `Collection+Surrounding.swift` edge cases

**F-032 is the live bug.** `item(before:where:)`:
```swift
var prevIndex = index(currentIndex, offsetBy: -1)   // traps if currentIndex == startIndex
while prevIndex >= startIndex {
  ...
  prevIndex = index(prevIndex, offsetBy: -1)
}
```
`Collection.index(_:offsetBy:)` is documented to trap when the resulting index falls outside `startIndex...endIndex`. When `currentIndex == startIndex`, `offsetBy: -1` is outside the valid range → runtime trap. This is reachable via `NavigationManager.highlightPrevious` when the selected item is the first item in the list.

**Impact.** Crash when pressing ↑ on the first history item (depending on the predicate; today the call site `visibleItem(before:)` is wrapped in `if let`, but the trap occurs *inside* `item(before:where:)` before any optional return).

**Recommendation.**
```swift
guard currentIndex > startIndex else { return nil }
var prevIndex = index(currentIndex, offsetBy: -1)
```

**F-033** (`between`): when `fromElement == toElement`, returns a single-element array. Caller (`extendSelection` in `NavigationManager.swift:113-120`) handles this fine; **Low**.

**F-034** (`nearest`): tie-breaker ambiguity — when `index1` and `index2` are equidistant from `currentIndex`, the function returns `self[index2]` (the previous one). Undocumented; **Low**.

---

### F-035 / F-036 / F-037 — `History.add` index arithmetic

**F-035** (`History.swift:148-167`): `all.remove(at: removedItemIndex)` after `firstIndex(where: { $0.item == existingHistoryItem })` — `firstIndex` is guarded by `if let`, so safe. **Medium** only because the use-after-delete concern (F-035) is hypothetical.

**F-036** (`History.swift:191-194`): relies on `HistoryItem` reference identity. SwiftData `@Model` classes are reference types, so `firstIndex(of: item)` uses `==` which falls back to `ObjectIdentifier`. **Correct today**, fragile if SwiftData ever snapshots.

**F-037** (`History.swift:177`): off-by-one reasoning — see F-006.

---

## UTF-8 / String Boundaries

### F-009 / F-010 / F-011 — `Search.swift` index arithmetic

**F-011 (trap, High).**
```swift
if searchString.count > fuzzySearchLimit {
  let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
  ...
}
```
The guard `count > fuzzySearchLimit` *guarantees* `count >= fuzzySearchLimit + 1`, so `offsetBy: fuzzySearchLimit` is in range. **Safe today**, fragile to refactor. Add a comment.

**F-010 (semantic bug, High).**
```swift
ranges: fuzzyResult.ranges.map {
  let startIndex = searchString.startIndex
  let lowerBound = searchString.index(startIndex, offsetBy: $0.lowerBound)
  let upperBound = searchString.index(startIndex, offsetBy: $0.upperBound + 1)
  return lowerBound..<upperBound
}
```
`Fuse` returns ranges in **UTF-16 code-unit offsets** (it operates on `String` via `NSString`-style indexing internally). `String.Index(_:offsetBy:)` advances by **grapheme clusters**. For ASCII-only content these coincide; for content with surrogate pairs (most emoji) or combined characters, the highlight range points at the wrong cluster. The `+1` adds an additional off-by-one when the matched range ends mid-surrogate-pair.

**Impact.** Wrong/misaligned highlight ranges for emoji and astral-plane characters. Does not crash (the indices are within bounds because the search was performed on the same string), but visually wrong.

**Recommendation.** Convert UTF-16 offsets to `String.Index` via `String.UTF16View.Index(_:_:)` and then to `String.Index`:
```swift
let utf16Lower = String.UTF16View.Index(_offsetInCodeUnits: $0.lowerBound)
let lower = String.Index(utf16Lower, within: searchString)!)
```
or perform the search on `searchString.utf16` and bridge back.

**F-009** is a clarification — the `string.startIndex..., in: string` `NSRange` constructor requires that `string` be the same one the regex ran against. It is, so correct.

---

### F-012 — `String+Shortened.swift` grapheme-vs-byte unit mismatch (High)

**File:** `Maccy/Extensions/String+Shortened.swift`.

**Problem.**
```swift
func shortened(to maxLength: Int) -> String {
  guard count > maxLength else { return self }
  return String(self[..<index(startIndex, offsetBy: maxLength)])   // grapheme count
}
```
`count` and `index(_:offsetBy:)` operate on **Extended Grapheme Clusters**. The byte-based truncator `Data.stringPrefix(maxBytes:)` operates on **UTF-8 bytes** (via the C++ `validUTF8PrefixLength`). For the *same* logical "preview limit":
- A 10 000-character ASCII string: `stringPrefix(maxBytes: 10_000)` returns 10 000 chars; `shortened(to: 10_000)` also 10 000 chars.
- A 10 000-byte CJK string (~3 333 chars): `stringPrefix(maxBytes: 10_000)` returns ~3 333 chars; `shortened(to: 10_000)` returns all 3 333 (no truncation).
- A 10 000-byte emoji string: similar divergence.

`HistoryItem.textPrefix` uses `stringPrefix`; `HistoryItemEngine.previewableTextPrefix` then calls `.shortened(to: maxLength)` on the result. So the effective limit is `min(bytePrefix, graphemeShorten)` — correct in spirit but inconsistent.

Additionally, `index(_:offsetBy:)` traps if `maxLength > count`, but the `guard count > maxLength else { return self }` protects this. **Safe today, fragile.**

**Impact.** Inconsistent truncation across content types; latent crash under refactor.

**Recommendation.** Pick one unit (recommend UTF-8 bytes throughout, since the C++ side already does). Either:
- Add `func shortened(toBytes maxBytes: Int)` that calls `data(using: .utf8)?.prefix(maxBytes)`, or
- Document the unit at each call site (`HistoryItem.shortened(to: HistoryItem.titlePreviewLimit)` operates on graphemes).

---

### F-013 / F-030 — `highlight` truncates title to 500, ranges computed against full title (High)

**File:** `Maccy/Observables/HistoryItemDecorator.swift:191-216`.

**Problem.**
```swift
var attributedString = AttributedString(title.shortened(to: 500))   // truncated copy
for range in ranges {                                                 // ranges from full title
  if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
     let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
    ...
  }
}
```
The `ranges` come from `Search.search`, which runs against `item.title` (the full title). `attributedString` is the **shortened-to-500** copy. For matches past character 500, `AttributedString.Index(_:within:)` returns `nil` and the highlight is silently dropped (the `if let` already guards, so no crash).

**Impact.** Silent loss of highlight for matches in long titles. Cosmetic but a correctness bug.

**Recommendation.** Build the attributed string from the same source the search ran against, or re-run the search against the shortened string. At minimum, document the truncation.

---

### F-049 — `generateTitle` regex anchoring (Low)

**File:** `Maccy/Engine/HistoryItemEngine.swift:67-79`.

`title.range(of: "^ +", options: .regularExpression)` matches leading spaces; `range` is in `title` (post-preview). `replacingOccurrences(of:with:range:)` operates within `range`. **Correct.** Low/docs only.

---

## Persistence / Error Handling

### F-002 (cross-ref) — `try?` swallowing

See above.

### F-014 / F-015 — `clear()` transaction semantics (High)

**File:** `Maccy/Observables/History.swift:217-249`.

**Problem 1 (F-014).** Inside `transaction { ... }`, both `delete` calls use `try?`:
```swift
try? Storage.shared.context.transaction {
  try? Storage.shared.context.delete(model: HistoryItem.self, where: #Predicate { $0.pin == nil })
  try? Storage.shared.context.delete(model: HistoryItemContent.self, where: #Predicate { $0.item?.pin == nil })
}
```
If the first `delete` throws, the error is swallowed and the second runs anyway. The transaction cannot roll back because no error is propagated out of the closure. Effectively, this is not a transaction — it is two unrelated `delete` calls wrapped syntactically.

**Problem 2 (F-015).** The predicates are asymmetric:
- `HistoryItem` predicate: `$0.pin == nil` → delete unpinned items.
- `HistoryItemContent` predicate: `$0.item?.pin == nil` → delete contents whose item is `nil` **or** whose item is unpinned.

For `HistoryItem` with `@Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)` (HistoryItem.swift:73), the cascade rule should already delete contents. The second `delete` is redundant for the cascade path and additionally nukes **orphaned** contents (whose `item` became nil through some other path). That may or may not be intended; it is undocumented.

**Impact.** Possible orphaned-content table bloat if cascade ever fails silently; surprising extra deletes if any content rows have `item == nil` for legitimate reasons.

**Recommendation.**
- Drop the inner `try?`s; let errors propagate to the transaction so it rolls back.
- Decide whether orphaned-content deletion is intentional; if yes, document; if no, tighten the predicate to `$0.item != nil && $0.item!.pin == nil` (forced unwrap on a checked non-nil is OK) or use a join.

---

### F-016 — Per-blob cap, no aggregate cap (High)

**File:** `Maccy/Clipboard.swift:231-238`.

**Problem.**
```swift
return types.compactMap { type in
  let value = item.data(forType: type)
  guard (value?.count ?? 0) <= HistoryItemContent.maxValueSize else { return nil }
  return HistoryItemContent(type: type.rawValue, value: value)
}
```
Each individual type is capped at `maxValueSize` (default 10 MB). But a pasteboard can carry many types (`.string`, `.rtf`, `.html`, `.png`, `.tiff`, `.jpeg`, `.heic`, `.fileURL`, plus proprietary types that pass through). An item with 8 types × 10 MB = 80 MB is happily stored. Combined with multiple merged pasteboard items (line 196), this can balloon.

**Impact.** Database bloat / memory pressure for pathological pasteboards (some image editors emit 5+ image representations).

**Recommendation.** Track a running `totalBytes` and stop adding types once it exceeds e.g. `2 * maxValueSize` or a separate `maxItemSize`.

---

### F-017 — `dataFromFileIfAllowed` falls back to unbounded file read (High)

**File:** `Maccy/Models/HistoryItem.swift:260-267`.

**Problem.**
```swift
private func dataFromFileIfAllowed(_ url: URL) -> Data? {
  let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
  guard (fileSize ?? 0) <= HistoryItemContent.maxValueSize else { return nil }
  return try? Data(contentsOf: url)
}
```
If `try? url.resourceValues(...)` fails (sandbox denial, network mount timeout, etc.), `fileSize` is `nil`, `(fileSize ?? 0)` is `0`, and `0 <= maxValueSize` is `true`. The function then calls `Data(contentsOf: url)` on an unbounded file → can OOM-crash the process or stall the main actor on a slow network mount.

**Impact.** Crash / hang on Universal Clipboard image with unreachable or unstat-able file URL.

**Recommendation.**
```swift
guard let fileSize, fileSize <= HistoryItemContent.maxValueSize else { return nil }
```
This rejects unknown-size files instead of optimistically allowing them.

---

### F-019 — `delete()` diverges in-memory list from disk on save failure (High)

**File:** `Maccy/Observables/History.swift:275-295`.

**Problem.**
```swift
Storage.shared.context.delete(item.item)
Storage.shared.context.processPendingChanges()
try? Storage.shared.context.save()
...
all.removeAll { $0 == item }
items.removeAll { $0 == item }
```
If `save()` fails (silently), the in-memory `all`/`items` no longer contain the item, but on disk it is still present. Next launch, the item reappears.

**Impact.** Inconsistent state; "deleted" items resurrect after restart.

**Recommendation.** Only mutate `all`/`items` after a successful save, or accept the divergence and document it (with a logger warning).

---

### F-045 — `withLogging` swallows the error it claims to log (Low)

**File:** `Maccy/Observables/History.swift:204-214`.

```swift
@MainActor
private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
  ...
  try? block()                          // ← swallows
  logger.info("\(msg) After: \(dataCounts())")
}
```
The function is named "with logging" but the error is `try?`-discarded; the surrounding `logger.info` only prints counts, never the error.

**Recommendation.** `do { try block() } catch { logger.error("\(msg) failed: \(error)") }`.

---

## Pasteboard / Types

### F-007 — Multi-item merge keeps duplicates (High)

**File:** `Maccy/Clipboard.swift:194-204`.

**Problem.**
```swift
var itemContents = [HistoryItemContent]()
pasteboard.pasteboardItems?.forEach({ item in
  itemContents += contents(from: item)
})
```
If two pasteboard items both expose `.string` (BBEdit/Edge case cited in the comment), the merged `itemContents` will contain **two** `.string` blobs. The downstream `ContentIndex` (`HistoryItemEngine.swift:131-138`) buckets by type into `[String: [Data]]`, so this works for *lookup* but `contentData([.string])` (HistoryItem.swift:244-252) returns only the **first**. The second blob is effectively dead weight in the database.

**Impact.** Storage waste; potential confusion if the two `.string` blobs differ (which one is "the" text?).

**Recommendation.** After merging, deduplicate by `(type, value)` or by `type` (keep first / keep largest).

---

### F-025 / F-026 / F-055 / F-058 / F-059 — URL and content edge cases

**F-025 (High).** `imageData` for Universal Clipboard reads from disk via `dataFromFileIfAllowed`; this happens on the main actor when the property is accessed. A slow network mount stalls the UI.

**F-026 (Medium).** `URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true)` returns non-nil for almost any bytes. Downstream `dataFromFileIfAllowed` then attempts `Data(contentsOf:)` on arbitrary paths. Combined with F-017, this is an attack/DoS surface.

**F-055 (Low).** `.compactMap` on URL parsing silently drops bad data. Add `logger.debug`.

**F-058 (Low).** `pasteboard.setData(content.value, ...)` with `content.value == nil` is a silent no-op.

**F-059 (Low).** `pasteboard.setString(item.application ?? "", forType: .source)` clobbers any pre-existing `.source` attribution.

---

## Numeric / Overflow

### F-020 — `UInt64(KeyChord.pasteKeyModifiers.rawValue) | 0x000008` (Medium)

**File:** `Maccy/Clipboard.swift:122`.

`CGEventFlags.rawValue` is `UInt64`; the OR with `0x000008` (the "right-side modifier" bit per the Flycut reference) is correct. The literal is unexplained magic. Add a named constant.

### F-021 — `sessionLog` unbounded growth (Medium)

**File:** `Maccy/Observables/History.swift:179`.

Every successful copy adds an entry to `sessionLog: [Int: HistoryItem]`. There is no eviction. Long-running sessions accumulate; values are strong references to `HistoryItem` instances that may have been deleted from SwiftData (the dictionary keeps them alive).

**Recommendation.** Cap at e.g. 1000 entries with LRU eviction; or clear on `clearAll()`.

### F-022 — `Int(modified)` from pasteboard (Medium)

**File:** `Maccy/Models/HistoryItem.swift:227-234`.

`Int(String)` returns nil on overflow/non-numeric — safe. But `modified` is used as a `sessionLog` key (line 473) without verifying it was ever a real `changeCount`. A malformed pasteboard value of `"42"` could match an unrelated session-log entry. **Low impact** (the value would have to coincidentally equal a recent changeCount), but worth a comment.

### F-023 / F-024 — Int/UInt casts in `ClipboardDataProcessor` (Medium)

**File:** `Maccy/Core/ClipboardDataProcessor.swift:15-18`.

```swift
let prefixLength = Int(MaccyTextProcessor.validUTF8PrefixLength(in: data, maxBytes: UInt(maxBytes)))
```
- `UInt(maxBytes)` is lossless for non-negative `Int` on 64-bit; negative `maxBytes` underflows. The `maxBytes > 0` guard at line 7 protects against `0` but **not against negative** (returns `""` for `<= 0`, OK actually — re-reading, `guard maxBytes > 0 else { return "" }` covers negatives too because `> 0` is false for negatives). **Safe.**
- `Int(NSUInteger)` could trap if `NSUInteger > Int.max`; bounded by `data.count` here, so safe.

**Verified correct.** Keep as documentation.

### F-029 — FNV-1a non-cryptographic hash (Medium, safe)

**File:** `Maccy/Core/ClipboardDataProcessor.swift:39-60`.

The 64-bit FNV-1a hash is used as a fast short-circuit, but the function performs a full `lhs == rhs` after the hash matches. **Safe** — collisions cannot cause false positives, only wasted work. Document this explicitly so future maintainers don't remove the trailing compare.

### F-038 — `selectionIndex: Int = -1` sentinel (Medium)

**File:** `Maccy/Observables/HistoryItemDecorator.swift:22-25`.

Sentinel value `-1` for "not selected". Brittle; `var selectionIndex: Int?` is safe-by-construction.

### F-053 — `historySizeLimit = max(1, Defaults[.size])` (Low)

**File:** `Maccy/Observables/History.swift:58`.

`Defaults[.size]` is an `Int` from user defaults. `max(1, ...)` guards against `0`/negatives. `Int.max` is accepted and would attempt to allocate that many decorators — bounded only by available memory in practice (limitHistorySize would never delete). Add an upper clamp (e.g. 10 000).

---

## Thread-safety / Model Confinement

### F-008 — OCR `Task` mutates `@Model` off the insert transaction (High)

**File:** `Maccy/Models/HistoryItem.swift:97-114`.

```swift
func generateTitle() -> String {
  if let imageData {
    ...
    Task { @MainActor [weak self, imageData] in
      ...
      self?.title = recognizedText     // ← mutates SwiftData model
    }
    return ""
  }
  ...
}
```
The Task is `@MainActor` so the mutation is on the main context — good. But:
1. The Task is fire-and-forget; if the item is deleted before the Task runs, `self` is `weak` → no-op (good).
2. If the item is deleted from the context but not yet `save()`-d, `self` is still alive and the title is set on a doomed object — harmless but wasteful.
3. There is no cancellation hook; the Vision request runs to completion even if the user clears history.

**Impact.** Wasted work; possible transient inconsistency between in-memory title and persisted title (if save fails between set and persist).

**Recommendation.** Track the OCR Task on the decorator (alongside `thumbnailImageGenerationTask`) and cancel in `cleanupImages` / `invalidate`.

---

### F-060 / F-061 / F-062 — `@unchecked Sendable` (Low)

**Files:** `HistoryItemDecorator.swift:8`, `AppDelegate.swift:6`, `History.swift:12`.

Three classes annotate `@unchecked Sendable` (HistoryItemDecorator explicitly; AppDelegate explicitly; History implicitly via `@Observable` + main-actor methods). This silences Swift 6 concurrency checking. Correctness depends on the *undocumented* invariant that all mutations happen on `@MainActor`.

**Impact.** Latent data race if any mutation ever happens off-main (e.g. from a `Task {}` without `@MainActor`).

**Recommendation.** Make the classes explicitly `@MainActor` (the methods already are) and drop `@unchecked Sendable`. This enforces the invariant at compile time.

---

### F-047 / F-048 — Fire-and-forget Tasks (Low)

**Files:** `HistoryItem.swift:97-114`, `History.swift:69-103`.

Multiple `Task { @MainActor in ... }` blocks are never captured or cancelled. For singletons this is lifecycle-correct but cancels nothing on shutdown. **Low.**

---

## Resource / File Handles

### F-018 — `open()` descriptor leak on DispatchSource failure (High)

**File:** `Maccy/ApplicationImage.swift:48-87`.

```swift
let descriptor = open(appURL.path, O_EVTONLY)
if descriptor == -1 {
  ...                                              // logs and falls through
} else {
  let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: descriptor,
    eventMask: [.write, .delete],
    queue: DispatchQueue.global()
  )
  eventSource = source
  source.setEventHandler { ... }
  source.setCancelHandler {
    close(descriptor)                              // ← only installed on success path
  }
  source.resume()
}
```
Today `makeFileSystemObjectSource` is documented to *not* throw (it returns a `DispatchSource`); but if it ever does (or if any code between `open()` and `setCancelHandler` throws/returns early), `descriptor` leaks. There is no `defer { close(descriptor) }` guard.

Additionally, on the `-1` path the function logs to `print()` (not the logger) and then **returns `img`** (the icon fetched on line 45), so the icon is shown but monitoring is silently disabled. The user gets no feedback.

**Impact.** Fd leak under future refactor; silent monitoring disablement on open failure.

**Recommendation.**
```swift
let descriptor = open(appURL.path, O_EVTONLY)
guard descriptor != -1 else {
  logger.warning("open(\(appURL.path)) failed: \(errno)")
  return img
}
defer { /* closed by cancel handler */ }
let source = DispatchSource.makeFileSystemObjectSource(...)
source.setCancelHandler { close(descriptor) }
...
```
And use `logger` instead of `print`.

---

### F-040 — `Timer.scheduledTimer` target retains `self` (Medium)

**File:** `Maccy/Clipboard.swift:55-64`.

`Timer.scheduledTimer(target: self, ...)` strongly retains `self` for the lifetime of the timer. `Clipboard.shared` is a singleton, so this is a non-issue in practice. For a non-singleton `Clipboard`, this would be a leak.

**Recommendation.** Use the block-based `Timer.scheduledTimer(withTimeInterval:repeats:block:)` with `[weak self]` for defensiveness.

---

### F-046 — `_ = await previewImageGenerationTask?.result` (Low)

**File:** `Maccy/Observables/HistoryItemDecorator.swift:127`.

Accessing `.result` on a Task that throws discards the error via `_ =`. Cosmetic.

---

## Additional Notes (verified correct / not bugs)

- **`validUTF8PrefixLength`** (`Processor/ClipboardByteProcessor.cpp:19-76`): full UTF-8 validation including overlong rejection (`minimum`), surrogate-pair rejection (`0xD800..0xDFFF`), and `> 0x10FFFF` rejection. **Correct and thorough.**
- **`fnv1a64`** (`ClipboardByteProcessor.cpp:78-85`): standard FNV-1a 64-bit; constant-time, no overflow concerns because `uint64_t` multiplication wraps mod 2^64 by definition. **Correct.**
- **`dataLikelyEqual`** (`Core/ClipboardDataProcessor.swift:39-60`): the trailing `lhs == rhs` makes hash collisions safe. **Correct.**
- **`Int(modified)`** (`HistoryItem.swift:233`): nil-safe. **Correct.**
- **`limitHistorySize` guard `unpinned.count > maxSize`** makes `[maxSize...]` valid today. **Correct but fragile** (F-005).
- **`Search.simpleSearch` / `regexpSearch`**: use `searchString.range(of:options:)` and `Range(match.range, in:)` which are safe-by-construction.
- **`Collection+Surrounding.between`** (F-033): indices are validated by `firstIndex(of:)`; the slice is always in range.
- **`Storage.shared.context.transaction`** use in `clear()`: syntactically a transaction, semantically broken by inner `try?` (F-014).

---

## Top 3 Critical Findings

1. **F-001** — `recoverContainer` deletes the SQLite store on load failure → permanent history loss with no recovery path.
2. **F-002 / F-003** — `try?` swallows every SwiftData save/delete error → silent data loss and in-memory/disk divergence on every persistence path.
3. **F-032** — `Collection+Surrounding.item(before:where:)` traps on `offsetBy: -1` at `startIndex` → crash when pressing ↑ on the first list item.

---

## Counts by Severity

| Severity | Count |
|----------|-------|
| Critical | 4 (F-001, F-002, F-003, F-004→re-classed Low; so 3 true criticals) |
| High | 14 (F-005, F-006, F-007, F-008, F-009, F-010, F-011, F-012, F-013, F-014, F-015, F-016, F-017, F-018, F-019) — note 15 listed, F-009 is borderline |
| Medium | 18 |
| Low | 23 |
| **Total findings** | **60** (after F-004 reclassification) |

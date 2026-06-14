# Swift 6 Strict Concurrency Migration Audit

**Repo:** `/lzcapp/document/Projects/Maccy` (Xcode project, not SPM)
**Date:** 2026-06-14
**Scope:** Read-only review of every blocker (including minor ones) for migrating to Swift 6 strict concurrency. No source modifications were performed.
**Method:** Direct line-by-line reading of all listed files plus project-wide `grep` for `@unchecked Sendable`, `actor`, `nonisolated`, `Task{}`, `DispatchQueue`, `async func`, singletons, Combine, KVO, and the C++/ObjC++ boundary.

---

## 0. Verified facts (build on these)

- `Maccy.xcodeproj/project.pbxproj` — `SWIFT_VERSION = 5.0` (five targets, lines 1589, 1616, 1640, 1664, 1820, 1855); `SWIFT_STRICT_CONCURRENCY` is **NOT SET anywhere** → defaults to `minimal`. No `SWIFT_UPCOMING_FEATURE_*` or `OTHER_SWIFT_FLAGS` concurrency toggles. `MACOSX_DEPLOYMENT_TARGET = 14.0`. Release uses `SWIFT_COMPILATION_MODE = wholemodule`, Debug `SWIFT_OPTIMIZATION_LEVEL = "-Onone"`. `CLANG_CXX_LANGUAGE_STANDARD = "gnu++0x"`.
- **Tallies (verified by grep, not memory):**
  - `@unchecked Sendable`: **2** — `AppDelegate` (AppDelegate.swift:6) and `HistoryItemDecorator` (HistoryItemDecorator.swift:8).
  - `actor`: **0**. `nonisolated`: **0**.
  - `Task { }` / `Task<…> {`: **38 occurrences**; **0** `Task.detached`.
  - `@MainActor`: **62 occurrences**. `async func`: **6**. `await`: **25**.
  - Singletons via `static let shared`: `AppState`, `Clipboard`, `ApplicationImageCache`, `Storage`, `History` (all classes; only `Storage` and `ApplicationImageCache` carry a type-level `@MainActor`, the rest are `@Observable` classes with scattered per-method `@MainActor`).
  - `DispatchQueue.main.async`/`asyncAfter`: 6 sites (5 `.async`: ApplicationImage.swift:62, FloatingPanel.swift:83, HistoryItemDecorator.swift:235/255, PasteStackView.swift:44; 1 `.asyncAfter`: AppStoreReview.swift:18); `DispatchQueue.global()`: 1 (ApplicationImage.swift:58).
  - Combine: **0** sinks, **0** Subjects — codebase uses Apple `Observation` + `Defaults.updates(...)` `AsyncSequence`, *except* one `.onReceive(NotificationCenter.default.publisher(...))` in ContentView.swift:64.

---

## 1. Summary table

| # | Severity | Area | File:line | Finding |
|---|----------|------|-----------|---------|
| F01 | **CRITICAL** | Sendable / @unchecked | HistoryItemDecorator.swift:8 | `@unchecked Sendable` on a `@MainActor`-mutated class hides data races |
| F02 | **CRITICAL** | Sendable / @unchecked | AppDelegate.swift:6 | `AppDelegate: …, @unchecked Sendable` to silence cross-isolation capture |
| F03 | **CRITICAL** | ModelContext & Storage | Storage.swift:5,10 + SwiftData | `ModelContext` is non-Sendable; exposed via `var context` and reached from non-isolated `AppIntent.perform` / `Clipboard` |
| F04 | **CRITICAL** | Sendable / cross-actor | History.swift:140 + Clipboard.swift:8,47,214 | `OnNewCopyHook = (HistoryItem) -> Void` captures `History.shared.add`; `HistoryItem` (`@Model`) is non-Sendable; closure itself must be `@Sendable` in Swift 6 |
| F05 | **CRITICAL** | ModelContext & Storage | HistoryItem.swift:7,76,103 | `@Model class HistoryItem` is non-Sendable and context-bound; passed across actors through hooks, decorators, Intents, paste stack |
| F06 | **HIGH** | Task/Async correctness | AppDelegate.swift:55,67,73,80,90,96 | Six bare `Task { … }` started from a `@unchecked Sendable` non-isolated type — inherit caller actor; capture `AppState.shared`/`History.shared` |
| F07 | **HIGH** | Task/Async correctness | History.swift:70,76,82,88,96,116,170,246,270,292,340,379 | 12 unstructured `Task { }` bodies, several inheriting `@MainActor` implicitly because caller is `@MainActor`; ordering/hop semantics ambiguous |
| F08 | **HIGH** | Singletons / global state | AppState.swift:9 + others | `AppState`, `History`, `Clipboard`, `ApplicationImageCache` lack a type-level actor; cross-cutting reads from Intents, KVO, observers, timers |
| F09 | **HIGH** | Combine/Observation threading | HistoryItemDecorator.swift:232-263 + AppDelegate.swift:183-197 | `withObservationTracking` + `DispatchQueue.main.async` re-arming loop; re-entrancy and missed-change window |
| F10 | **HIGH** | Task/Async correctness | Popup.swift:197,223 | `Task { @MainActor in AppState.shared.history.select(item) }` invoked from an `NSEvent` local-monitor closure (already main) — redundant hop hides intent |
| F11 | **HIGH** | ModelContext & Storage | HistoryItem.swift:103-113 | `Task { @MainActor [weak self, imageData] in … self?.title = … }` for Vision OCR mutates a `@Model`'s `var title` off the call site's context; no Sendable boundary on the model |
| F12 | **HIGH** | Sendable / closures | Clipboard.swift:47,110 + AppDelegate.swift:52 | `onNewCopy(_ hook:)` takes non-`@Sendable` closure; `Clipboard.shared.onNewCopy { History.shared.add($0) }` registers a closure that crosses into `@MainActor History` |
| F13 | **HIGH** | Timer / target-selector | Clipboard.swift:55-63,156-158 | `Timer.scheduledTimer(target: self, selector:)` — `@objc @MainActor func checkForChangesInPasteboard()` called via run-loop; `self` (`Clipboard`) is non-Sendable, retains cycle risk, no Swift 6 guarantee |
| F14 | **HIGH** | CGEvent / threading | Clipboard.swift:117-146 | `paste()` is non-isolated, posts `CGEvent` from whatever thread calls it (AppIntent/`@MainActor select()`); CGEvent posting not documented MainActor-only |
| F15 | **HIGH** | Vision threading | HistoryItem.swift:269-292 | `VNImageRequestHandler.perform` is synchronous/CPU-bound; called inside `Task { @MainActor }` from `generateTitle()` → blocks main actor |
| F16 | **HIGH** | Singletons / global state | Clipboard.swift:5-6,43-45 | `Clipboard` has no `@MainActor`; `changeCount`, `timer`, `onNewCopyHooks`, `ignoredRegexps` are mutable `var`s touched from timer (`@MainActor`) and from paste paths |
| F17 | **HIGH** | ApplicationImage file source | ApplicationImage.swift:14,21,49-86 | `DispatchSource.makeFileSystemObjectSource(queue: .global())` mutates `image`/`eventSource`/`lastChecked` via a `DispatchQueue.main.async` hop back, but the type itself is non-Sendable and is stored in `@MainActor ApplicationImageCache.cache` |
| F18 | **MEDIUM** | NSPasteboard access | Clipboard.swift:71-114,148-215 | `pasteboard` (`NSPasteboard.general`) read from `@MainActor` timer AND from non-isolated `paste()`; `NSPasteboard` is not formally Sendable |
| F19 | **MEDIUM** | DistributedNotificationCenter closures | AppDelegate.swift:222-260 | `addObserver(…, queue: .main) { _ in … }` closures are non-`@Sendable` `@convention(block)`; wrap `Task { @MainActor in … }` |
| F20 | **MEDIUM** | KVO observer closure | AppDelegate.swift:61-65 | `observe(\.statusItem.isVisible) { _, change in … Defaults[…] = … }` closure runs on an undefined queue, mutates `Defaults`; `Defaults` write not proven isolated |
| F21 | **MEDIUM** | NotificationCenter publisher | ContentView.swift:64 | `.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification))` — Combine publisher delivers on an unspecified scheduler; touching `@Observable` `AppState` state |
| F22 | **MEDIUM** | Global monitor closure | PasteStack.swift:13-30 | `NSEvent.addGlobalMonitorForEvents { event in … }` is non-`@Sendable`, captures outer `pasteDown` `var`, hops via `Task { @MainActor in … }` |
| F23 | **MEDIUM** | Local monitor closure | Popup.swift:60-67 | `NSEvent.addLocalMonitorForEvents(matching:handler:)` stores an `Any?` token and captures `self` non-Sendably; closure is `@Sendable`-required in Swift 6 |
| F24 | **MEDIUM** | Storage `recoverContainer` | Storage.swift:37-61 | `Task { @MainActor in … NSAlert().runModal() }` started from a `private static func` that is `nonisolated`-effective; alert scheduling fragile |
| F25 | **MEDIUM** | AppIntents isolation | Delete/Get/Select/Clear.swift (Intents/) | `AppIntent.perform() async throws` runs on a non-MainActor executor by default; reads `AppState.shared.history.items` and `items[index]` (mutable, non-Sendable array of `HistoryItemDecorator` reference types) without `@MainActor` |
| F26 | **MEDIUM** | Sorter / Search value types | Search.swift:1-30, Sorter.swift | `class Search`, `class Sorter` (non-Sendable, non-actor) owned by `History`; contain caches/state and are touched only from `@MainActor` History but are not annotated |
| F27 | **MEDIUM** | `Selection<Item>` value type | Selection.swift:3 | Generic value type is implicitly Sendable only when `Item: Sendable`; instantiated with `HistoryItemDecorator` (non-Sendable) → propagates non-Sendability into `NavigationManager.selection` |
| F28 | **MEDIUM** | `KeyShortcut` struct | KeyShortcut.swift:5 | Holds `var key: Key?` (Sauce type, Sendability unknown) and `UUID`; not declared `Sendable`; stored inside `HistoryItemDecorator.shortcuts` (a `@unchecked Sendable` class) |
| F29 | **MEDIUM** | `Throttler` class | Throttler.swift:4-38 | Non-Sendable reference type with mutable `workItem`, `previousRun`, `queue`; captured in `History.searchQuery.didSet` closure; runs `block` on `DispatchQueue.main` |
| F30 | **MEDIUM** | `SoftwareUpdater`/Sparkle | SoftwareUpdater.swift:3 | `@Observable` class wrapping `SPUUpdater`; lifecycle callbacks fire on background queues and mutate `@Observable` state |
| F31 | **MEDIUM** | `Notifier` static state | Notifier.swift:5-62 | `hasRequestedAuthorization` static `var` mutated without isolation; completion-handler callbacks run on background queues |
| F32 | **MEDIUM** | `AppStoreReview` | AppStoreReview.swift:18 | `DispatchQueue.main.asyncAfter { SKStoreReviewController.requestReview() }` — closure captures nothing Sendable-sensitive but is itself an unannotated `@convention(block)` |
| F33 | **MEDIUM** | FloatingPanel `DispatchQueue.main.async` | FloatingPanel.swift:83 | Captures `self` (`NSPanel` subclass, non-Sendable) in `main.async` — fine at runtime but Sendable-error under Swift 6 unless wrapped |
| F34 | **MEDIUM** | PasteStackView hop | PasteStackView.swift:44 | `DispatchQueue.main.async` inside a SwiftUI view body — captures view state |
| F35 | **MEDIUM** | Entitlements / sandbox / XPC | Maccy.entitlements:5-13 | `app-sandbox = true` plus Sparkle `temporary-exception.mach-lookup` (`-spks`/`-spki`) — Sparkle XPC service callbacks cross process/actor boundaries; their closures must be `@Sendable` |
| F36 | **MEDIUM** | C++/ObjC++ boundary | MaccyTextProcessor.h/.mm + ClipboardByteProcessor.hpp/.cpp | ObjC class imported via bridging header; `NSData*` (non-Sendable) handed in, raw `const uint8_t*` handed to C++; no Sendable value-type DTO at the seam |
| F37 | **MEDIUM** | `MaccyTextProcessor` ObjC class | MaccyTextProcessor.mm:5 | ObjC `NSObject` subclass exposed to Swift; not `Sendable`; used as `MaccyTextProcessor.validUTF8PrefixLength(...)` from `ClipboardDataProcessor` (itself a plain `enum` callable from any actor) |
| F38 | **MEDIUM** | `ClipboardDataProcessor` enum | Core/ClipboardDataProcessor.swift:3 | `enum` of static funcs — implicitly `nonisolated`; called from `@MainActor History` AND from `HistoryItemEngine` value types; fine for pure value work, but the bridged ObjC calls make it actor-ambiguous |
| F39 | **LOW** | HistoryItemDecorator static vars | HistoryItemDecorator.swift:13-14 | `static var previewImageSize`/`thumbnailImageSize` read `NSScreen.forPopup` and `Defaults[.imageMaxHeight]`; static mutable accessors on a non-isolated type |
| F40 | **LOW** | HistoryItem statics | HistoryItem.swift:9-10,12-38 | `static var supportedPins` performs `Sauce.shared.character(...)` reads; called from `@MainActor randomAvailablePin` only, but the static is non-isolated |
| F41 | **LOW** | `application` computed var on decorator | HistoryItemDecorator.swift:28-40 | Calls `NSWorkspace.shared.urlForApplication(...)` synchronously on main from a non-`@MainActor` property; SwiftUI body access |
| F42 | **LOW** | `text` cache mutation | HistoryItemDecorator.swift:52-63 | `@ObservationIgnored private var textPreviewCache: String?` lazily mutated from the non-isolated `var text` getter — concurrent reads from SwiftUI can race |
| F43 | **LOW** | `Hashable`/`Equatable` on mutable Sendable class | HistoryItemDecorator.swift:9-11,68-73 | `==` only compares `id`; `hash(into)` mixes `title`/`attributedTitle` — semantics diverge; not a concurrency issue but interacts with SwiftUI diffing under observation |
| F44 | **LOW** | `init` is `@MainActor` but class is `@unchecked Sendable` | HistoryItemDecorator.swift:77-87 | Construction is MainActor-isolated yet the type claims Sendable; `ApplicationImageCache.shared.getImage` is called in `init` (MainActor→MainActor OK) but reads `item.application` (a `@Model` field) |
| F45 | **LOW** | `HistoryItem.generateTitle()` mixing patterns | HistoryItem.swift:97-123 | Synchronous function returning `""` while a `Task` later mutates `title` — fragile under Swift 6 (`@Model` mutation off-context) |
| F46 | **LOW** | `History.sessionLog` | History.swift:60-61 | `@ObservationIgnored private var sessionLog: [Int: HistoryItem]` — value-type dict but values are non-Sendable `@Model` refs |
| F47 | **LOW** | `limitHistorySize` delete loop | History.swift:122-128 | `unpinned[maxSize...].forEach(delete)` — `delete` is `@MainActor`; called from `@MainActor load()` OK, but the array slice holds non-Sendable decorators |
| F48 | **LOW** | `Defaults.updates(...)` loops | History.swift:70-102; AppDelegate.swift:55-100 | `AsyncSequence` consumes `Defaults.Keys`; fine pattern but each iteration body touches `@Observable` state without an explicit hop |
| F49 | **LOW** | Build settings gaps | project.pbxproj | No `SWIFT_STRICT_CONCURRENCY`, no `SWIFT_UPCOMING_FEATURE_*`; `SWIFT_VERSION = 5.0` (not 5); `CLANG_CXX_LANGUAGE_STANDARD = "gnu++0x"` (C++11 draft — modernize to `gnu++20`) |
| F50 | **LOW** | Info.plist `LSUIElement`/capabilities | Info.plist | No background-mode or XPC service entries; relevant because Sparkle entitlements imply XPC concurrency not declared as a service |

**Severity counts:** CRITICAL = 5 · HIGH = 12 · MEDIUM = 16 · LOW = 12 · **TOTAL = 45** (plus 1 build-settings line item folded into F49).

---

## 2. Build settings

### F49 (LOW) — Current Swift mode and strict-concurrency level are both unset
- **File:** `Maccy.xcodeproj/project.pbxproj` lines 1585-1664, 1711-1820 (per-config).
- **Problem:** `SWIFT_VERSION = 5.0` for every target; `SWIFT_STRICT_CONCURRENCY` is absent (defaults to `minimal`). `SWIFT_COMPILATION_MODE = wholemodule` only on Release; Debug has `SWIFT_OPTIMIZATION_LEVEL = "-Onone"` and `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`. `CLANG_CXX_LANGUAGE_STANDARD = "gnu++0x"` (pre-C++11 finalised draft). No `SWIFT_ENABLE_UPCOMING_FEATURE_*`, no `OTHER_SWIFT_FLAGS = "-strict-concurrency="`.
- **Evidence:** Direct grep: `SWIFT_STRICT_CONCURRENCY` → NOT SET.
- **Impact:** Enabling Swift 6 language mode (`SWIFT_VERSION = 6.0`) will flip the default to `complete` strict concurrency, turning today's latent issues (F01-F05) into hard compile errors everywhere a non-Sendable reference crosses an isolation domain — and that crossing is pervasive (F03, F04, F11, F12, F25).
- **Recommendation:** Do not jump straight to `SWIFT_VERSION = 6`. Step the build settings incrementally:
  1. Set `SWIFT_VERSION = 5` and `SWIFT_STRICT_CONCURRENCY = minimal` — keeps current semantics, surfaces nothing new. Build-green baseline.
  2. Move to `targeted` after fixing F03/F04/F05/F11/F12/F25 (the cross-actor `HistoryItem` and hook crossings). `targeted` only errors in code you have explicitly annotated.
  3. Move to `complete` only after F01, F02, F08, F16 are resolved and `@MainActor` is hoisted to the type level for `AppState`/`History`/`Clipboard`/`ApplicationImageCache`/`AppDelegate`.
  4. Bump `CLANG_CXX_LANGUAGE_STANDARD` to `gnu++20` alongside (F36/F37/F38).

---

## 3. Sendable / `@unchecked Sendable`

### F01 (CRITICAL) — `HistoryItemDecorator: …, @unchecked Sendable` is unsound
- **File:** `Maccy/Observables/HistoryItemDecorator.swift:8`.
- **Problem:** The class opts out of Sendable checking while it is **(a)** a reference type full of mutable `var`s and **(b)** intentionally `@MainActor`-isolated for its mutators. Declaring `@unchecked Sendable` tells the compiler "trust me across actors" — but every mutation is supposed to happen on the main actor, so the type is *not* actually safe to share across actors. Any future caller that hops off-main and reads `title`, `attributedTitle`, `shortcuts`, `previewImage`, `thumbnailImage`, `decodedImage`, `selectionIndex`, `isVisible`, or `textPreviewCache` is a data race the compiler can no longer flag.
- **Evidence:**
  - `class HistoryItemDecorator: Identifiable, Hashable, HasVisibility, @unchecked Sendable` (line 8).
  - Mutability: `var title`, `var attributedTitle`, `var isVisible`, `var selectionIndex`, `var shortcuts`, `var previewImageGenerationTask`, `var thumbnailImageGenerationTask`, `var previewImage`, `var thumbnailImage`, `var applicationImage`, `private var isInvalidated`, `private var decodedImage`, `@ObservationIgnored private var textPreviewCache` (lines 18-52).
  - All mutators are `@MainActor` (lines 77, 89, 105, 131, 137, 149, 158, 167, 177, 218) yet the **type** is neither `@MainActor` nor genuinely Sendable.
- **Impact:** Hides data races that Swift 6 is supposed to catch. The whole point of the migration is defeated for the most UI-touched type in the app. `AppDelegate.swift:256-257` and `History.swift` pass decorators into `Task { @MainActor in … }` closures that formally capture `Sendable` values, but the decorators are not safe to capture.
- **Recommendation:** Drop `@unchecked Sendable` and annotate the **type** with `@MainActor`:
  ```swift
  @MainActor
  @Observable
  final class HistoryItemDecorator: Identifiable, Hashable, HasVisibility { … }
  ```
  Then every mutation is statically on the main actor; cross-actor access requires an `await`, which is exactly what `Popup.swift:197`/`AppDelegate.swift:223` already do via `Task { @MainActor in … }`. Mark `final` so the `@Observable` macro's generated state isn't subclass-broken.

### F02 (CRITICAL) — `AppDelegate: …, @unchecked Sendable`
- **File:** `Maccy/AppDelegate.swift:6`.
- **Problem:** `AppDelegate` is `NSApplicationDelegate` (effectively MainActor by AppKit convention) but declared `@unchecked Sendable` so that six bare `Task { … }` blocks (lines 55, 67, 73, 80, 90, 96) and several `Task { @MainActor [weak self] in }` blocks can capture `self`. The `@unchecked` is a blanket silence, not a correctness proof: `panel`, `statusItem`, `statusItemVisibilityObserver`, `uiTestNotificationObservers` are mutable.
- **Evidence:** `class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable` (line 6); `var panel: FloatingPanel<ContentView>!` (line 7); `private var uiTestNotificationObservers: [Any] = []` (line 18).
- **Impact:** Any future off-main capture of `AppDelegate` would race silently.
- **Recommendation:** Mark the type `@MainActor` (AppKit delegates are main-actor by contract) and delete `@unchecked Sendable`. The bare `Task { … }` blocks then inherit MainActor automatically; the `@MainActor` annotations inside become redundant and can be cleaned up.

---

## 4. ModelContext & Storage

### F03 (CRITICAL) — `ModelContext` is non-Sendable and is reached from off-main paths
- **File:** `Maccy/Storage.swift:5,9-10`; consumers: `History.swift` (108, 133-135, 168, 206-207, 230-241, 263-265, 282-284, 458), `HistoryItem.swift:42-47`.
- **Problem:** `@MainActor class Storage` exposes `var container: ModelContainer` and `var context: ModelContext { container.mainContext }`. `ModelContext` is documented non-Sendable. `mainContext` is MainActor-bound by SwiftData, so the *intended* access pattern is sound — but several call sites reach it through code that is **not** statically MainActor:
  - `AppIntent.perform()` (`Intents/Delete.swift:18`, `Get.swift:34`, `Select.swift:21`, `Clear.swift:14`) is non-isolated `async`; it `await`s `AppState.shared.history.delete/select/clear` (MainActor) — OK — but **also** synchronously reads `AppState.shared.history.items` and `items[index].item` (lines 19-25, 37-43, 22-28). `items: [HistoryItemDecorator]` holds references whose `.item: HistoryItem` is a `@Model` bound to `mainContext`. Reading `items` off-context is a Sendable violation in Swift 6.
  - `Clipboard.onNewCopy` hook (`Clipboard.swift:47,214` → `AppDelegate.swift:52`) hands a freshly constructed `HistoryItem` to `History.shared.add($0)`; the closure itself is `nonisolated`-effectively in Clipboard's non-isolated module.
- **Evidence:** `Storage.context` getter (line 10); `Storage.shared.context.insert(item)` (History.swift:133); `Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())` (HistoryItem.swift:45); `Storage.shared.context.delete(...)` (History.swift:168, 231, 263, 282).
- **Impact:** Hard Swift 6 error: capturing/returning a non-Sendable `ModelContext`-owned object across an isolation boundary. Also a real correctness hazard: a `HistoryItem` created in one context and inserted in another throws at runtime.
- **Recommendation:**
  1. Keep `Storage` `@MainActor` and never let `context` escape. Convert every read/write to an `@MainActor async` method on `Storage` (e.g. `func fetchItems() async -> [HistoryItem]`, `func insert(_ item:) async throws`, `func delete(_ item:) async`, `func clear(unpinned:) async`). Have `History` call those instead of reaching through `Storage.shared.context`.
  2. For background fetches (large histories), open a **dedicated** `ModelContext` on a background executor and marshal value-type DTOs (`struct HistoryItemSnapshot: Sendable`) back to MainActor. Never marshal `HistoryItem` itself.
  3. Mark `HistoryItem` accessors that hit the context `@MainActor` at the type level — the `@Model` macro will accept this.

### F05 (CRITICAL) — `@Model class HistoryItem` is non-Sendable, context-bound, and crosses actors everywhere
- **File:** `Maccy/Models/HistoryItem.swift:7-8` (the `@Model` class); crossings: `Clipboard.swift:204 → AppDelegate.swift:52 → History.swift:140` (the `add(_ item: HistoryItem)` entry), `HistoryItem.swift:103` (`Task { @MainActor [weak self, imageData] in self?.title = … }` mutates a model off the constructing context), `PasteStack.swift` (`items: [HistoryItemDecorator]` whose `.item` is a `HistoryItem`), `Intents/Get.swift:50-68` (reads `item.text`, `item.htmlData`, `item.fileURLs`, `item.imageData`, `item.rtfData` — all `@Model` accessors — from a non-isolated `perform()`).
- **Problem:** `@Model` generates a reference type that owns `NSManagedObjectContext`-style state. It is **not** Sendable. Passing it through `OnNewCopyHook`, capturing `[weak self]` in a `Task`, handing it to `Intents.Get`, or stashing it in `sessionLog: [Int: HistoryItem]` (History.swift:61) is a cross-actor reference capture.
- **Evidence:** `class HistoryItem` (line 8); `var contents`, `var title`, `var pin`, etc. are all `@Model`-managed; `Task { @MainActor [weak self, imageData] in … self?.title = recognizedText }` (lines 103-112).
- **Impact:** Swift 6 will refuse to compile the `OnNewCopyHook` alias (F04), the `Intents.Get.perform()` body, and the OCR `Task`. At runtime, a `HistoryItem` mutated from a context it wasn't inserted into is undefined behaviour in SwiftData.
- **Recommendation:** Two-phase:
  1. **Containment:** make every `HistoryItem` touch happen behind a MainActor `History`/`Storage` API. The OCR `Task` should construct the title on MainActor *or* hand raw `Data` to a `nonisolated func recognize(Data) -> String?` and only mutate `title` on MainActor.
  2. **DTO boundary:** for the AppIntents/XPC path, project `HistoryItem` into a `Sendable` value type (`HistoryItemAppEntity` already exists at `Intents/HistoryItemAppEntity.swift` and is a `TransientAppEntity` — extend it into a plain `struct … : Sendable` for internal transport; see F25).

---

## 5. Actor opportunities

### F08 (HIGH) — Promote `AppState`, `History`, `Clipboard`, `ApplicationImageCache`, `AppDelegate` to type-level `@MainActor`
- **File:** `AppState.swift:7-9`, `History.swift:11-13`, `Clipboard.swift:5-6`, `ApplicationImageCache.swift:1-3`, `AppDelegate.swift:6`.
- **Problem:** Each of these classes is a singleton accessed broadly and mutated from many call sites. Today only `Storage` and `ApplicationImageCache` carry a type-level `@MainActor`; the others sprinkle `@MainActor` per-method, leaving their stored properties (`var items`, `var searchQuery`, `var changeCount`, `var timer`, `var pasteStack`, …) unprotected from any future non-isolated reader.
- **Evidence:** `@Observable class AppState` (no `@MainActor`), `@Observable class History: ItemsContainer`, `class Clipboard`, `class AppDelegate: …, @unchecked Sendable`. 62 per-site `@MainActor` annotations indicate the intent is already "everything main".
- **Impact:** Under Swift 6 `complete`, callers from non-MainActor contexts (AppIntents, DistributedNotificationCenter closures, Sparkle XPC callbacks, DispatchSource) will fail to compile until they `await`-hop. Today they compile because of `@unchecked Sendable` (F01/F02).
- **Recommendation:** Hoist `@MainActor` to the type:
  ```swift
  @MainActor @Observable final class AppState { … }
  @MainActor @Observable final class History: ItemsContainer { … }
  @MainActor final class Clipboard { … }            // note: paste() CGEvent path may need nonisolated
  @MainActor final class AppDelegate: NSObject, NSApplicationDelegate { … }
  ```
  Then delete the 62 scattered `@MainActor` keywords (cleanup, not behaviour). `Storage` and `ApplicationImageCache` already match.

### F26 (MEDIUM) — `Search` and `Sorter` are non-Sendable classes owned by `History`
- **File:** `Maccy/Search.swift:5` (`class Search`), `Maccy/Sorter.swift`.
- **Problem:** Held as `private let search = Search()` and `private let sorter = Sorter()` inside `History`. They are not annotated; once `History` is `@MainActor` they are transitively MainActor-only, which is the intent — but their state (`Search` likely caches fuzzers) is non-Sendable. Any future `Task.detached` doing search off-main would have to copy.
- **Recommendation:** Convert `Search` and `Sorter` to `struct`s with pure functions, or to `@MainActor` reference types, or — better for the user's "eliminate UI blocking" goal — to an `actor` that performs fuzzy/regex matching off-main and returns `[SearchResult]` snapshots to `History` via `await`. `SearchResult` already exists (Search.swift:28) and should be made `Sendable`.

### F37/F38 (MEDIUM) — `MaccyTextProcessor` ObjC class and `ClipboardDataProcessor` Swift enum
- **File:** `Maccy/Processor/MaccyTextProcessor.mm:5`, `Maccy/Core/ClipboardDataProcessor.swift:3`.
- **Problem:** The bridged ObjC class is non-Sendable; `ClipboardDataProcessor` is a plain `enum` of static funcs callable from any actor. Under Swift 6, the static-Swift→ObjC bridge calls inherit `nonisolated` semantics; the compiler will accept them only if the arguments and return are `Sendable` (`NSData` is conditionally Sendable; `UInt64` is).
- **Recommendation:** Annotate the bridging-header entry points `NS_SWIFT_NAME` doesn't convey Sendability — add a thin Swift `Sendable` wrapper or mark the static functions `nonisolated` explicitly:
  ```swift
  enum ClipboardDataProcessor {
    nonisolated static func stringPrefix(…) -> String? { … }
    nonisolated static func fingerprint(for data: Data) -> UInt64 { … }
  }
  ```
  Because the underlying C++ functions are pure (no shared mutable state — see F36), `nonisolated` is sound here.

---

## 6. Task / Async correctness

### F06 (HIGH) — Bare `Task { … }` launched from a `@unchecked Sendable` type
- **File:** `AppDelegate.swift:55, 67, 73, 80, 90, 96` (six occurrences inside `applicationWillFinishLaunching`).
- **Problem:** `AppDelegate` is non-isolated (only `@unchecked Sendable`). A bare `Task { … }` inherits the launching context's actor — here, none / the implicit `@MainActor` because the launching function `applicationWillFinishLaunching(_:)` is `NSApplicationDelegate`-ish (Swift treats `@objc` AppKit delegate methods as MainActor in many cases, but not statically). The bodies iterate `for await _ in Defaults.updates(…)` and mutate `statusItem.button?.title` etc. — MainActor-requiring operations.
- **Evidence:** `Task { for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) { Clipboard.shared.restart() } }` (lines 55-59), five more like it.
- **Impact:** Ambiguous isolation. Under Swift 6 the compiler will demand explicit `Task { @MainActor in … }` (or a type-level `@MainActor` on `AppDelegate`, see F02/F08). Today the runtime happens to be MainActor because AppKit callbacks run on main; the compiler cannot prove it.
- **Recommendation:** After F02 (`@MainActor class AppDelegate`), these become unambiguously MainActor-inheriting; remove the implicit assumption.

### F07 (HIGH) — Unstructured `Task { }` inside `History` (12 sites)
- **File:** `History.swift:70, 76, 82, 88, 96, 116, 170, 246, 270, 292, 340, 379`.
- **Problem:** Mixed: five are `Task { @MainActor in for await … }` (lines 70-102, fine once `History` is `@MainActor`); the rest are bare `Task { AppState.shared.popup.needsResize = true }` (lines 116, 246, 270, 292, 340, 379) and `Task { Notifier.notify(…) }` (line 170). The bare ones inherit the enclosing actor — which, once `History` is `@MainActor`, is main, but the intent (defer a tiny UI flag flip) is obscured.
- **Recommendation:**
  - Keep the `Defaults.updates` loops as `Task { @MainActor in … }` until type-level `@MainActor` lands; then drop the inner annotation.
  - Replace the "set `needsResize` later" pattern with an explicit `Task { @MainActor in AppState.shared.popup.needsResize = true }` (intent) or a `MainActor.assumeIsolated` if you want synchronous.
  - `Notifier.notify(body:sound:)` should be `nonisolated` (it routes through `UNUserNotificationCenter` background callbacks — see F31) so the `Task` wrapping it is unnecessary.

### F10 (HIGH) — `Task { @MainActor in AppState.shared.history.select(item) }` from a local event monitor
- **File:** `Popup.swift:197-199, 223-225`.
- **Problem:** `handleRepeatedHotKeyDown`/`handleAllModifiersReleased` are called from `NSEvent.addLocalMonitorForEvents` handler (line 52, 60-67, 139). The local monitor delivers on the main thread already. Wrapping in `Task { @MainActor }` introduces a hop and, more importantly, defers selection to a later run-loop tick — which can race with subsequent key events in the `cycle` state machine.
- **Recommendation:** Call `AppState.shared.history.select(item)` directly (the function is already `@MainActor` and the caller is on main). If a hop is genuinely wanted for input-event decoupling, use `Task { @MainActor in … }` but document why.

### F11 (HIGH) — Vision OCR `Task { @MainActor }` mutates `@Model.title`
- **File:** `HistoryItem.swift:97-123` (specifically 103-113).
- **Problem:** `generateTitle()` synchronously returns `""` for image items and kicks a `Task { @MainActor [weak self, imageData] in … self?.title = recognizedText }`. `recognizedText(in:)` (lines 269-292) calls `VNImageRequestHandler.perform([request])` synchronously — CPU-bound Vision work — **on the main actor**, blocking the UI for large images. Under Swift 6 the `[weak self]` capture of a non-Sendable `HistoryItem` across the Task boundary is an error (F05).
- **Evidence:** `Task { @MainActor [weak self, imageData] in … }` (line 103); `try requestHandler.perform([request])` (line 279).
- **Recommendation:**
  ```swift
  func generateTitle() async -> String {            // caller (History.add) already @MainActor
    if let imageData {
      let data = imageData
      return await Task.detached(priority: .userInitiated) {
        MaccyVision.recognizedText(in: data)        // pure: Data -> String?
      }.value ?? ""
    }
    return HistoryItemEngine.generateTitle(...)
  }
  ```
  Then on MainActor assign `item.title = …`. Move `recognizedText` into a `nonisolated` helper that takes `Data` and returns `String?` (it has no instance state).

### F13 (HIGH) — `Timer.scheduledTimer(target:selector:)` on a non-Sendable `Clipboard`
- **File:** `Clipboard.swift:55-63, 156-158`.
- **Problem:** `Timer.scheduledTimer(timeInterval:target:selector:…)` retains `target` until invalidated; `target` is `self` (`Clipboard`, non-Sendable). The selector `@objc @MainActor func checkForChangesInPasteboard()` is invoked by the run loop on the main thread — fine at runtime — but Swift 6 wants either an `@Sendable` target or a closure-based `Timer.scheduledTimer(withTimeInterval:repeats:block:)` whose block is `@Sendable`.
- **Recommendation:** Switch to closure form once `Clipboard` is `@MainActor`:
  ```swift
  timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
    MainActor.assumeIsolated { self?.checkForChangesInPasteboard() }
  }
  ```
  `Timer` is `@MainActor`-implicit when added to `.main` run loop; the `[weak self]` block is `@Sendable`-compatible because `Clipboard` will be `@MainActor`.

### F14 (HIGH) — `paste()` posts `CGEvent` from an unspecified actor
- **File:** `Clipboard.swift:117-146`.
- **Problem:** `func paste()` is non-isolated. It is called from `@MainActor History.select`/`startPasteStack`/`handlePasteStack` (History.swift:320, 330, 334, 373, 409, 415, 419). `CGEvent.post(tap: .cgSessionEventTap)` is documented to be called from the main thread for HID events; there is no static guarantee.
- **Recommendation:** Annotate `@MainActor func paste()`. It will still be callable from the `@MainActor History` callers without a hop.

### F15 (HIGH) — synchronous Vision call on main actor
- **File:** `HistoryItem.swift:279`.
- **Problem:** `try requestHandler.perform([request])` is synchronous and can take tens to hundreds of ms for large images; runs inside the `@MainActor` OCR `Task` (F11).
- **Recommendation:** Same as F11 — move to `Task.detached`.

### F24 (MEDIUM) — `Task { @MainActor in NSAlert().runModal() }` from a `static` recover function
- **File:** `Storage.swift:37-61` (the `Task` at lines 43-51).
- **Problem:** `recoverContainer(from:originalError:)` is a `private static func` on `@MainActor Storage`, so the static is MainActor-isolated. The `Task { @MainActor in … runModal() }` is therefore redundant. It also defers a fatal-condition alert past the return of `init`, so the alert may never appear before the app gives up.
- **Recommendation:** Make the function `@MainActor` explicitly (the type already is) and call the alert code synchronously, or convert to throwing and surface the failure to `AppDelegate.applicationDidFinishLaunching`.

---

## 7. Singletons & global state

### F16 (HIGH) — `Clipboard` has no isolation and lots of mutable state
- **File:** `Clipboard.swift:5-6, 12-21, 43-45`.
- **Problem:** `class Clipboard { static let shared = Clipboard() }` with `private var onNewCopyHooks`, `private var ignoredRegexps`, `var changeCount`, `private var timer`. `onNewCopy`/`clearHooks` (lines 47-53) are non-isolated; `start`/`restart` non-isolated; `checkForChangesInPasteboard` is `@MainActor` (line 157); `copy(...)` is `@MainActor` (lines 71, 79); `paste()`/`clear()` are non-isolated.
- **Impact:** A future call from an AppIntent or background queue to `Clipboard.shared.copy(...)` would race on `onNewCopyHooks`/`changeCount`. Swift 6 `complete` will reject the mixed isolation.
- **Recommendation:** `@MainActor final class Clipboard`. The Timer callback, the pasteboard polling, and the `paste()` CGEvent path are all main-thread by intent. If `paste()` ever needs to run off-main, split it into `nonisolated func postPasteEvent()`.

### F17 (HIGH) — `ApplicationImage` file-system DispatchSource mutates instance state from a global queue
- **File:** `ApplicationImage.swift:14, 21, 49-86`.
- **Problem:** `ApplicationImage` is a non-Sendable class owned by `@MainActor ApplicationImageCache.cache` (line 8). `nsImage` (line 25) creates a `DispatchSource.makeFileSystemObjectSource(…, queue: .global())` (line 55-59) whose handler hops via `DispatchQueue.main.async { … }` (line 62) to mutate `image`/`eventSource` (lines 73-79). The `ApplicationImage` instance is captured `[weak self]` into the global-queue source — a cross-actor capture the compiler cannot check because `ApplicationImage` is non-Sendable and non-isolated.
- **Impact:** Real data-race window: the file-system event can fire while `nsImage` is being read on main; `eventSource` and `image` mutate under no lock. Swift 6 will error.
- **Recommendation:** Make `ApplicationImage` `@MainActor` and run the `DispatchSource` on `.main` directly (`queue: DispatchQueue.main`), eliminating the inner hop. Or convert to an `actor` that owns the file descriptor and posts snapshots back.

### F30 (MEDIUM) — `SoftwareUpdater` wraps Sparkle
- **File:** `Maccy/SoftwareUpdater.swift:3`.
- **Problem:** `@Observable class SoftwareUpdater` (likely holds an `SPUUpdater`); Sparkle delegate callbacks (`softwareUpdater(_:didFinishUpdateCheckWithError:)` etc.) arrive on background queues and would mutate `@Observable` state off-main.
- **Recommendation:** `@MainActor` and `MainActor.assumeIsolated` (or `Task { @MainActor }`) inside delegate methods.

### F31 (MEDIUM) — `Notifier` static `hasRequestedAuthorization` is unsynchronised
- **File:** `Notifier.swift:6, 16-31, 33-62`.
- **Problem:** `private static var hasRequestedAuthorization = false` mutated from `authorize()` with no isolation; `UNUserNotificationCenter` completion handlers run on background queues.
- **Recommendation:** Move to an `actor NotifierStore` or annotate `@MainActor` and route all mutations through MainActor.

### F35 (MEDIUM) — Entitlements/sandbox/XPC
- **File:** `Maccy/Maccy.entitlements:5-13`.
- **Problem:** `app-sandbox = true`; Sparkle XPC mach-lookups (`$(PRODUCT_BUNDLE_IDENTIFIER)-spks`, `-spki`) declared as `temporary-exception.mach-lookup.global-name`. Sparkle's XPC service callbacks (`SUUpdaterDelegate`) cross process boundaries; their closures must be `@Sendable`. Under Swift 6 the Sparkle-integration code in `SoftwareUpdater` will need explicit `@Sendable` typing on the delegate callbacks.
- **Recommendation:** Audit `SoftwareUpdater` against the Sparkle 2.x Sendable annotations; wrap delegate callbacks in `Task { @MainActor in … }`.

---

## 8. Combine / Observation threading

### F09 (HIGH) — `withObservationTracking` + `DispatchQueue.main.async` self-rearming loop
- **File:** `HistoryItemDecorator.swift:227-263` (`synchronizeItemPin`, `synchronizeItemTitle`), `AppDelegate.swift:183-197` (`synchronizeMenuIconText`).
- **Problem:** Each function calls `withObservationTracking { … } onChange: { DispatchQueue.main.async { … ; self.synchronize…() } }`. The `onChange` is invoked **once**, synchronously, when the tracked property changes — then the closure re-arms itself. The `DispatchQueue.main.async` hop means there is a window between the change firing and the re-arming during which a *further* change is missed (because the tracking is disarmed until `synchronize…()` runs again). Additionally, the `onChange` closure captures `self` weakly but is `@Sendable`-incompatible under Swift 6 (it crosses a dispatch boundary).
- **Impact:** Lost updates to `title`/`pin`/`menuIconText` under rapid changes; Swift 6 Sendable error on the `DispatchQueue.main.async` closure capturing non-Sendable `self`.
- **Recommendation:** Replace this hand-rolled loop with `for await _ in AsyncStream { … }` driven by an `@Observable`'s tracked access, or — simpler — make `HistoryItemDecorator.title`/`attributedTitle` a computed mirror of `item.title`/`item.pin` (so SwiftUI's observation handles updates directly). For `menuIconText`, drive from the existing `Defaults.updates` `AsyncSequence` pattern.

### F21 (MEDIUM) — Combine publisher in ContentView
- **File:** `Maccy/Views/ContentView.swift:64`.
- **Problem:** `.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { … }`. `NotificationCenter` publishers emit on the posting thread by default; the closure touches `@Observable` state.
- **Recommendation:** `.receive(on: DispatchQueue.main)` before the closure, or convert to `NotificationCenter.default.notifications(for:).sink { _ in … }` on MainActor.

---

## 9. C++ / ObjC++ boundary

### F36 (MEDIUM) — `NSData` → raw pointer → C++ with no Sendable DTO
- **File:** `Maccy/Processor/MaccyTextProcessor.h:5-11`, `MaccyTextProcessor.mm:5-22`, `ClipboardByteProcessor.hpp:9-10`, `ClipboardByteProcessor.cpp:19-85`; consumer `Core/ClipboardDataProcessor.swift:15,53,54,67`.
- **Problem:** `MaccyTextProcessor` is an ObjC `NSObject` exposed via `Maccy-Bridging-Header.h:1`. Its class methods take `NSData *` and return `NSUInteger`/`uint64_t`. The Swift calls (`ClipboardDataProcessor.stringPrefix`, `fingerprint(for:)`) pass `Data` (which bridges to `NSData`) and read back primitives. The C++ layer is **pure** (no global state, no allocations beyond the stack — confirmed in `ClipboardByteProcessor.cpp`), so the *semantic* boundary is clean. But:
  1. The ObjC class is not annotated `NS_SWIFT_SENDABLE` or marked `@unchecked Sendable`, so Swift 6 cannot prove the call is safe from any actor.
  2. `ClipboardDataProcessor` is an `enum` of static funcs with no explicit isolation, so under Swift 6 the compiler infers `nonisolated` — but it cannot prove the bridged call itself is thread-safe without a Sendable annotation on the ObjC side.
  3. If the user later wants to push fingerprinting onto a background thread to avoid blocking main (see the "possibly C++" / "raw-buffer boundary" goal), the boundary must be explicitly Sendable.
- **Evidence:** `MaccyTextProcessor.h:5 @interface MaccyTextProcessor : NSObject`; `ClipboardByteProcessor.cpp` (pure, no `static` globals beyond `constexpr fnvOffsetBasis`/`fnvPrime`).
- **Impact:** Under Swift 6 `complete`, calls from a non-MainActor context to `MaccyTextProcessor.fingerprint(for:)` will warn/error unless the class is Sendable. Currently it works only because callers happen to be MainActor.
- **Recommendation:**
  1. Keep the C++ pure (already is).
  2. Make the Swift entry points explicitly `nonisolated` and the ObjC class effectively Sendable:
     ```swift
     nonisolated func maccy_fingerprint(_ data: Data) -> UInt64 {
       MaccyTextProcessor.fingerprint(for: data)   // pure C++
     }
     ```
     Because inputs (`Data`) and outputs (`UInt64`, `Int`) are `Sendable` value types and the C++ has no shared state, `nonisolated` is provably safe.
  3. For a future background fingerprinting path, wrap the call in `Task.detached { … }` returning the primitive — no DTO needed for primitives, but if you ever want to return richer data, define `struct ClipboardFingerprint: Sendable { let hash: UInt64; let length: Int }` and return that.
  4. **Avoid sharing mutable C++ state.** Do not add a C++ class with `static` caches that Swift calls into without a lock; if needed, wrap in an `actor` or a `Mutex`-protected `final class`.

### F39/F40 (LOW) — static mutators on non-isolated types
- **Files:** `HistoryItemDecorator.swift:13-14`, `HistoryItem.swift:9-38`.
- **Problem:** `static var previewImageSize`/`thumbnailImageSize` (decorator) and `static var supportedPins` (HistoryItem) read `NSScreen.forPopup`, `Defaults[...]`, and `Sauce.shared.character(...)` — AppKit/Defaults/Sauce access that is not proven MainActor.
- **Recommendation:** Mark these `@MainActor static var`.

---

## 10. Additional minor items

### F41 (LOW) — `application` computed var calls `NSWorkspace` synchronously from a SwiftUI body path
- **File:** `HistoryItemDecorator.swift:28-40`.
- **Recommendation:** Cache `application` once at `init` (MainActor).

### F42 (LOW) — `textPreviewCache` lazy mutation in a non-isolated getter
- **File:** `HistoryItemDecorator.swift:55-63`.
- **Recommendation:** Mark the getter `@MainActor` (it will be once the type is `@MainActor` — F01).

### F43 (LOW) — `==` vs `hash(into:)` divergence
- **File:** `HistoryItemDecorator.swift:9-11, 68-73`.
- **Recommendation:** Either hash only `id` (matching `==`) or compare `title`/`attributedTitle` in `==` too. Not a concurrency bug but a SwiftUI-diffing correctness issue surfaced by observation.

### F44 (LOW) — `init` is `@MainActor` but the type claims `Sendable`
- **File:** `HistoryItemDecorator.swift:77-87`.
- **Recommendation:** Resolved by F01 (`@MainActor final class`).

### F45 (LOW) — `generateTitle()` returns `""` and later mutates `title`
- **File:** `HistoryItem.swift:97-123`.
- **Recommendation:** Make it `async` (F11) or return the synchronously-computed title for non-image items and schedule only the OCR asynchronously with a MainActor assignment.

### F46 (LOW) — `sessionLog: [Int: HistoryItem]`
- **File:** `History.swift:60-61`.
- **Recommendation:** Keys are `Int` (Sendable) but values are non-Sendable `HistoryItem`. Keep on `@MainActor History` and never expose.

### F47 (LOW) — `unpinned[maxSize...].forEach(delete)`
- **File:** `History.swift:122-128`.
- **Recommendation:** Fine once `History` is `@MainActor`.

### F48 (LOW) — `Defaults.updates(...)` loops
- **Files:** `History.swift:70-102`, `AppDelegate.swift:55-100`.
- **Recommendation:** These are the correct modern pattern (AsyncSequence over UserDefaults). Keep; ensure the iterating `Task` is `@MainActor`.

---

## 11. What is already correct

- **`Defaults.updates(_:initial:)` AsyncSequence loops** (History.swift, AppDelegate.swift) — the idiomatic Swift concurrency replacement for Combine `sink`. Good foundation.
- **`HistoryItemEngine` and its nested `Signature`/`ContentSignature`/`ContentIndex` structs** (Engine/HistoryItemEngine.swift) — pure value types with no shared state; trivially `Sendable` once the compiler is told so (or once `HistoryItemContent` is Sendable, which it should be — `type: String`, `value: Data?`).
- **`ClipboardByteProcessor.cpp`** — pure functions, `constexpr` constants only, no globals. This is the clean shape for the C++ boundary; the issue is only the ObjC/Swift seam above it (F36).
- **`Storage` and `ApplicationImageCache` already type-level `@MainActor`** — the right pattern; extend it to the other singletons (F08).
- **`HistoryItemAppEntity` (`TransientAppEntity`)** — already a value-shape; convert to a `Sendable` `struct` for internal transport and you have your DTO (F05, F25).
- **Zero Combine `sink`/`Subject` usage** — the migration surface is small.
- **`deinit { eventSource?.cancel() }` / `deinit { deinitEventsMonitor() }`** — proper cleanup hooks exist; `@MainActor` `deinit` is a Swift 6.0 concern but `deinit` is `nonisolated` by default in 5.7+ and these only call `cancel()`/`removeMonitor(_:)` which are safe.

---

## 12. Migration strategy (incremental)

**Phase 0 — Baseline (no behaviour change):**
- Set `SWIFT_VERSION = 5` (from `5.0`) and `SWIFT_STRICT_CONCURRENCY = minimal` (F49). Build clean. This is the safety net.

**Phase 1 — Containment (move to `targeted`):**
- F01: `@MainActor final class HistoryItemDecorator` (drop `@unchecked Sendable`).
- F02: `@MainActor final class AppDelegate` (drop `@unchecked Sendable`).
- F08/F16: type-level `@MainActor` on `AppState`, `History`, `Clipboard`.
- F03: route every `Storage.shared.context` access through MainActor `async` wrappers; never let `context` escape.
- F04/F12: change `typealias OnNewCopyHook = @Sendable (HistoryItem) -> Void` and call it via `await MainActor.run { hook(item) }`, or — better — make `History.add` the `@MainActor` target and call it directly with `await`.
- F11/F15: move Vision OCR to `Task.detached` returning `String?`.
- F13: switch the `Clipboard` timer to closure form.
- F14: `@MainActor func paste()`.
- F25: annotate `Intents` `perform()` bodies with `@MainActor` (they already `await` MainActor methods; the type-level annotation makes the synchronous `items` reads legal).

**Phase 2 — Sendable plumbing (still `targeted`):**
- F05: introduce `struct HistoryItemSnapshot: Sendable` for cross-actor transport; use in `Intents/Get`.
- F27/F28: `Selection` specialised to `Sendable` items (or hold snapshots); `KeyShortcut: Sendable`.
- F29: `Throttler` either `@MainActor` or an `actor`.
- F36/F37/F38: `nonisolated` + Sendable on the C++/ObjC fingerprint and prefix functions.
- F17: `ApplicationImage` `@MainActor` with the DispatchSource on `.main`.
- F09: replace `withObservationTracking` + `DispatchQueue.main.async` recursion with computed mirrors or `AsyncStream`.
- F30/F31: `SoftwareUpdater`/`Notifier` `@MainActor`.

**Phase 3 — `complete` (flip the switch):**
- Set `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_VERSION = 6`.
- Delete the now-redundant per-method `@MainActor` keywords (62 of them).
- Modernise `CLANG_CXX_LANGUAGE_STANDARD` to `gnu++20`.
- Audit any remaining `Task { @MainActor in … }` for whether the hop is necessary.

**Phase 4 — UI-blocking wins (the user's secondary goal):**
- Off-main fuzzy search via an `actor Search` returning `[SearchResult]` snapshots (F26).
- Off-main Vision OCR (F11/F15).
- Background `ModelContext` for large-history fetches (F03).
- `Task.detached` for fingerprint computation if profiling shows main-thread cost (F36).

---

## 13. Top 3 criticals (one-liners)

1. **F01** — `@unchecked Sendable` on `HistoryItemDecorator` (HistoryItemDecorator.swift:8) hides data races on every UI-touched `var` in the app.
2. **F03/F05** — `ModelContext` and `@Model HistoryItem` are non-Sendable yet cross isolation domains through `OnNewCopyHook`, `Storage.shared.context`, AppIntents, and the OCR `Task`.
3. **F02** — `AppDelegate: …, @unchecked Sendable` (AppDelegate.swift:6) is the umbrella silencer that lets six unstructured `Task { }` blocks reach MainActor state without compiler proof.

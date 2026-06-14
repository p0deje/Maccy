# BS-7 — Swift 6 迁移(增量)

> **依赖**:BS-1~BS-6(actor/DTO/后台 context/事件流/隔离模型已就位)。**编译边界**:**分阶段表里的每一级 strict concurrency 升级都是一个独立编译检查点**;`minimal→targeted` 通过 → 升 `SWIFT_VERSION = 6.0`(仍 `targeted`)通过 → `complete` 通过。任一级编译失败,回滚到上一级设置并补漏,不跳级。

**目标**:在 BS-1~6 已建立的真实隔离之上,逐级打开 Swift 严格并发检查,**消除 `@unchecked Sendable`** 与所有跨域的伪 Sendable 捕获,把"`@Model HistoryItem`/`ModelContext` 不跨域"从约定变成**编译器强制**,最终在 `SWIFT_VERSION = 6.0` + `complete` 下零并发警告编译。本步是**类型安全/隔离收敛**,不改运行时算法或性能特性。
**依据**:`06-F01`(decorator `@unchecked`)、`06-F02`(AppDelegate `@unchecked`)、`06-F03`(ModelContext 非 Sendable)、`06-F04`/`06-F12`(OnNewCopyHook 闭包)、`06-F05`(`@Model` 跨域)、`06-F06`/`06-F07`/`06-F10`(裸 `Task{}`)、`06-F08`(单例隔离)、`06-F09`(`withObservationTracking` 递归)、`06-F13`(Timer target-selector)、`06-F14`(CGEvent 线程)、`06-F15`/`06-F11`(Vision 线程)、`06-F16`/`06-F17`(Clipboard/ApplicationImage 隔离)、`06-F19`~`06-F23`(通知/KVO/monitor 闭包)、`06-F25`(AppIntent 隔离)、`06-F27`/`06-F28`/`06-F29`(Selection/KeyShortcut/Throttler)、`06-F35`(Sparkle XPC/entitlements)、`06-F36`~`06-F38`(C++/ObjC 桥接)、`06-F49`(构建设置缺口)、`06-F50`(Info.plist 能力声明)。
**编译安全性**:本大步骤**只**调整构建设置与隔离标注,不改业务行为;`SWIFT_STRICT_CONCURRENCY`/`SWIFT_VERSION` 每升一级都**必须 `xcodebuild build` 全绿**才进入下一级。`@unchecked Sendable` 的删除发生在隔离已真实就位后(前置依赖 BS-1~6),不是先删再补。

## 受影响文件
- 改:`Maccy.xcodeproj/project.pbxproj`(`:1589,1616,1640,1664,1820,1855` `SWIFT_VERSION`;新增 `SWIFT_STRICT_CONCURRENCY`;`:1676,1739` `gnu++0x`;`:1782` `SWIFT_COMPILATION_MODE`;`:1726,1727,1819` `SWIFT_OPTIMIZATION_LEVEL`/`SWIFT_ACTIVE_COMPILATION_CONDITIONS`)— 见分阶段表。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:8,13-14,28-40,52-63,77,89,105,131,137,149,158,167,177,218,227-263` — 去 `@unchecked Sendable`,类型升 `@MainActor final`;`static var` 归 `@MainActor`;`synchronizeItemPin/Title` 改 computed mirror 或 `AsyncStream`(去 `DispatchQueue.main.async` 递归)。
- 改:`Maccy/AppDelegate.swift:6,7,18,38,52,55-100,61-65,164-181,183-197,199-211,214-268` — 去 `@unchecked Sendable`;类型升 `@MainActor final`;6 处裸 `Task{}`(`:55,67,73,80,90,96`)显式化;KVO/`DistributedNotificationCenter`/`NotificationCenter` 闭包隔离。
- 改:`Maccy/Storage.swift:5-10,37-61` — `context` 不逃逸;`recoverContainer` 的 `Task{@MainActor}`(`:43-51`)改同步或 throwing。
- 改:`Maccy/Clipboard.swift:5-6,8,12-21,43-53,55-63,66-69,71,79,117-146,148,156-158,204,214` — 类型升 `@MainActor final`;`OnNewCopyHook` 加 `@Sendable` 或经 BS-2 的 ingestor 事件流;Timer 改闭包形式;`paste()`/`clear()` 标注。
- 改:`Maccy/Observables/History.swift:11-13,16-17,22-36,55-57,60-61,70-103,106-119,122-128,130-201,203-214,216-249,251-273,275-295,297-322,340-343,379-382,408-422,455-470,472-478,500-527` — 类型升 `@MainActor final`;12 处裸 `Task{}`(`:70,76,82,88,96,116,170,246,270,292,340,379`)显式化;`sessionLog: [Int: HistoryItem]` 改 `[Int: ItemID]`(BS-1 DTO)。
- 改:`Maccy/Observables/AppState.swift:7-9,13-18,28-33,54-102,108-162` — 类型升 `@MainActor @Observable final`;`menuIconText`(`:28-33`)改 `@MainActor`。
- 改:`Maccy/Models/HistoryItem.swift:7-8,9-38,40-51,76,97-123,103-113,260-292` — `@Model` 不跨域;`supportedPins`/`availablePins`/`randomAvailablePin`(`:12-51`)归 `@MainActor static`;`generateTitle()` 改 `async` 并经 BS-2/3 的后台 OCR;`recognizedText(in:)`(`:269-292`)抽 `nonisolated` 纯函数。
- 改:`Maccy/Engine/HistoryItemEngine.swift`(`Signature`/`ContentSignature`/`ContentIndex` 改 `Sendable` 值类型,移除 `private` 改 `internal` 供 BS-1 DTO 复用)。
- 改:`Maccy/Core/ClipboardDataProcessor.swift:3-89` — 静态函数显式 `nonisolated`(C++ 纯函数,见 `06-F36/F37/F38`)。
- 改:`Maccy/Processor/MaccyTextProcessor.mm`(`:5`)— ObjC 类显式 Sendable 注解或经 Swift 薄封装。
- 改:`Maccy/PasteStack.swift:5-6,13-30,33-52` — 类型隔离;全局 monitor 闭包(`:13-30`)加 `@Sendable`;`items: [HistoryItemDecorator]` 因 decorator 已 `@MainActor` 而传递隔离。
- 改:`Maccy/ApplicationImage.swift:4,12-14,21-23,25-93,55-86` — 类型升 `@MainActor`;`DispatchSource.queue`(`:55-59`)改 `.main`,消除内层 `DispatchQueue.main.async`(`:62`)。
- 改:`Maccy/ApplicationImageCache.swift`(`:1-3,8`)— 复核类型级 `@MainActor` 与 NSCache 边界(BS-6 已落地)。
- 改:`Maccy/SoftwareUpdater.swift:3`、`Maccy/Notifier.swift:5-62`、`Maccy/AppStoreReview.swift:18`、`Maccy/FloatingPanel.swift:83`、`Maccy/Views/PasteStackView.swift:44`、`Maccy/Views/ContentView.swift:64` — Sparkle/UN 闭包 `@MainActor` 或 `Task{@MainActor}`;Combine publisher `.receive(on: .main)`。
- 改:`Maccy/Intents/Delete.swift`/`Get.swift`/`Select.swift`/`Clear.swift`(`perform()` 非 MainActor)与 `Maccy/Intents/HistoryItemAppEntity.swift`(`TransientAppEntity` → Sendable transport)。
- 改:`Maccy/Search.swift:7`、`Maccy/Sorter.swift`、`Maccy/Selection.swift:3`、`Maccy/KeyShortcut.swift:5`、`Maccy/Throttler.swift:4-38` — `Sendable`/`@MainActor` 标注(BS-5 已重构 search;本步补标注)。
- 改:`Maccy/Maccy.entitlements:5-13`、`Maccy/Info.plist` — 复核 Sparkle XPC mach-lookup 与后台能力声明(`06-F35/F50`)。
- 新:`Maccy/Concurrency/SendableWrappers.swift` — Sparkle/ObjC 桥接的薄 `Sendable` 封装(若桥接侧无法直接标注)。

## 分阶段表(严格按序,每级一个编译检查点)

| 阶段 | `project.pbxproj` 设置(全部 5 个 `SWIFT_VERSION` 段 + project-level) | 预期警告/错误类别 | 收敛动作(对应小步骤) | 编译检查点 |
|---|---|---|---|---|
| **P0 — Baseline** | `SWIFT_VERSION = 5.0 → 5`(去 `.0`,纯写法规范化);`SWIFT_STRICT_CONCURRENCY = minimal`(`:1585,1722,1779,1813,1849` 各 Debug/Release + project-level `:1676,1739` 段);`gnu++0x → gnu++17`(`:1676,1739`,对齐 `gnu++14` 主体,与 BS-0 一致;预留 `gnu++20` 给 BS-8) | 无新增(strict concurrency 仍 minimal);仅规范化警告(若有 `SWIFT_VERSION = 5.0` 历史告警消除) | 7.1 规范化设置;7.2 隔离标注前置(`@MainActor` 类型级、`Sendable` struct)但**仍可被 minimal 忽略** | `minimal` build + test 全绿 |
| **P1 — Containment(targeted)** | `SWIFT_STRICT_CONCURRENCY = targeted`(同上 5 处 + project-level);`SWIFT_VERSION` 暂留 `5` | 仅在**已显式标注**的类型/函数上检查:跨 `@MainActor` 边界捕获非 Sendable、`@Sendable` 闭包捕获非 Sendable、`OnNewCopyHook` 闭包、`Timer` block、KVO/通知闭包 | 7.3 去 `@unchecked Sendable`(decorator/AppDelegate);7.4 单例类型级 `@MainActor`;7.5 `@Model`/context 不跨域(投影到 BS-1 DTO);7.6 裸 `Task{}` 显式化;7.7 Timer/CGEvent/Vision/通知闭包隔离 | `targeted`(SWIFT_VERSION=5)build + test 全绿 |
| **P2 — SWIFT_VERSION 6.0(targeted)** | `SWIFT_VERSION = 5 → 6.0`(`:1589,1616,1640,1664,1820,1855`);`SWIFT_STRICT_CONCURRENCY = targeted`(不变) | Swift 6 默认语义:`@MainActor` 继承增强、`Sendable` 默认更严、`nonisolated`/`@objc` 交互、`deinit` 隔离;可能暴露 P1 未覆盖的边缘(`@objc` selector、`deinit`、`NSApplicationDelegate` 协议方法继承) | 7.8 `@objc` + 隔离对齐;7.9 `deinit`/释放路径复核;7.10 C++/ObjC 桥接 `nonisolated` | `SWIFT_VERSION=6.0` + `targeted` build + test 全绿 |
| **P3 — complete** | `SWIFT_STRICT_CONCURRENCY = complete`(5 处 + project-level) | **全量**:任何非 Sendable 跨隔离域、任何缺少 `nonisolated` 的可跨域访问、Combine scheduler、Selection/KeyShortcut/Throttler 传播、AppIntent 默认执行器 | 7.11 值类型 Sendable 化(Selection/KeyShortcut/Throttler/SearchResult);7.12 AppIntent `perform()` 隔离或 DTO 投影;7.13 Combine/Observation 线程收敛;7.14 entitlements/Info.plist 复核 | `complete` + `SWIFT_VERSION=6.0` build + test 全绿;`-strict-concurrency=complete` 下零并发警告 |
| **P4 — 收尾清理** | 删除冗余 per-method `@MainActor`(62 处的大部分);`CLANG_CXX_LANGUAGE_STANDARD` 评估升 `gnu++20`(若 BS-8 不需要 C++20 特性则留 `gnu++17`);可选 `SWIFT_COMPILATION_MODE` 复核 | 仅死代码/冗余标注告警 | 7.15 清理冗余标注;7.16 复核 C++ 标准;7.17 全量验证 | 清理后 build + test 全绿;`xcodebuild -dry-run` 无新增告警 |

> "5 处 `SWIFT_VERSION` 段"指 `:1589`(MaccyUITests Debug)、`:1616`(MaccyUITests Release)、`:1640`、`:1664`、`:1820`、`:1855`(Maccy target Debug/Release + MaccyTests 等)。`project-level`(target 之上的 `XCBuildConfiguration`,`:1676`/`:1739` 段)承载 `gnu++0x`/`SWIFT_COMPILATION_MODE`/`SWIFT_OPTIMIZATION_LEVEL`,同样需要加 `SWIFT_STRICT_CONCURRENCY`。

## 小步骤

### 阶段 P0 — Baseline(`minimal`)

- [ ] **7.1 规范化构建设置** — `project.pbxproj`。在**所有 5 个含 `SWIFT_VERSION` 的 `XCBuildConfiguration` 块**(`:1585-1590`、`:1612-1617`、`:1636-1641`、`:1660-1665`、`:1813-1821`、`:1849-1856`)及**project-level 块**(`:1676` Debug / `:1739` Release)中:`SWIFT_VERSION = 5.0 → 5`;新增 `SWIFT_STRICT_CONCURRENCY = minimal`;`:1676,1739` 的 `gnu++0x → gnu++17`。**不改变任何源码**。验证:`xcodebuild build` 通过,行为零变化。
- [ ] **7.2 隔离标注前置(纯加法,minimal 下不报错)** — 在 `minimal` 下**预先**为后续阶段铺垫,但因 minimal 不强制故不破坏编译:
  - `Maccy/Observables/AppState.swift:7` 加 `@MainActor`(`@Observable @MainActor final class AppState`)。
  - `Maccy/Observables/History.swift:11` 加 `@MainActor final class History`。
  - `Maccy/Clipboard.swift:5` 加 `@MainActor final class Clipboard`(`paste()`/`clear()` 若需保留 nonisolated 则显式 `nonisolated func`)。
  - `Maccy/Engine/HistoryItemEngine.swift`:`Signature`/`ContentSignature`/`ContentIndex` 加 `: Sendable`(值类型,字段均 Sendable)。
  - `Maccy/Core/ClipboardDataProcessor.swift:6,31,39,62` 静态函数加 `nonisolated`(C++ 纯函数)。
  - 验证:`minimal` 下仍全绿(标注被忽略)。

### 阶段 P1 — Containment(`targeted`,SWIFT_VERSION=5)

- [ ] **7.3 去 `@unchecked Sendable`(CRITICAL F01/F02)** — 在 `targeted` 下,这两个类型已被 P0 的类型级 `@MainActor` 覆盖:
  - `HistoryItemDecorator.swift:8`:删 `@unchecked Sendable`,改为 `@MainActor @Observable final class HistoryItemDecorator: Identifiable, Hashable, HasVisibility`。`static var previewImageSize/thumbnailImageSize`(`:13-14`)改 `@MainActor static var`(`06-F39`)。`init`(`:77-87`)与所有 mutator 的 per-method `@MainActor`(`:77,89,105,131,137,149,158,167,177,218`)在类型级标注后变冗余,留待 P4 清理(本步保留以减小 diff)。
  - `AppDelegate.swift:6`:删 `@unchecked Sendable`,改为 `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate`。
  - 验证:`targeted` 下这两个类型的跨域访问点(Popup.swift:197/223、AppDelegate.swift:223-257 的 `Task{@MainActor}`)编译通过(它们已 `await`/`@MainActor` hop)。
- [ ] **7.4 单例类型级 `@MainActor` 复核(06-F08/F16/F17)** — `AppState`/`History`/`Clipboard`(P0 已加)的 stored property(`items`、`searchQuery`、`changeCount`、`timer`、`onNewCopyHooks`、`pasteStack`)在类型级隔离后受静态保护;`ApplicationImageCache`(已类型级 `@MainActor`)与 `Storage`(已 `@MainActor`)无需改。`ApplicationImage.swift:4` 升 `@MainActor final class`;`DispatchSource` 的 `queue: .global()`(`:55-59`)改 `DispatchQueue.main`,删除内层 `DispatchQueue.main.async { … }`(`:62`),`eventSource`/`image`/`lastChecked` 在主线程同步变更(`06-F17`)。
- [ ] **7.5 `@Model`/`ModelContext` 不跨域(06-F03/F04/F05/F12)** — 收敛跨域点:
  - `OnNewCopyHook`(`Clipboard.swift:8`)经 BS-2 已替换为 ingestor 事件流;若 BS-2 保留了过渡 `add(_:)` 入口,本步**不再让 `HistoryItem` 跨 actor**:hook 改为 `typealias OnNewCopyHook = @Sendable (ItemSnapshotDTO) async -> Void` 或直接由 BS-2 的 `StoreEvent` 取代(`06-F04/F12`)。
  - `AppIntent.perform()`(`Intents/Get.swift:34-72`、`Delete.swift`、`Select.swift`、`Clear.swift`)同步读 `items`/`items[index].item`(`@Model`)的路径:改为 `@MainActor func perform()` 或在 `perform()` 内 `await MainActor.run { … }` 投影出 `ItemSnapshotDTO`(`06-F25`);`HistoryItemAppEntity`(`Intents/HistoryItemAppEntity.swift`)转 Sendable transport(从 BS-1 的 `ItemSnapshotDTO` 填充),`Get` 不再持有 `@Model` 引用。
  - `HistoryItem.recognizedText(in:)`(`:269-292`)从 `Task{@MainActor [weak self, imageData]`(`:103-113`)移除 `[weak self]` 跨域捕获:OCR 经 BS-2/3 后台 actor 返回 `String?`,主线程赋值 `item.title`(`06-F11/F15`)。
  - `sessionLog: [Int: HistoryItem]`(`History.swift:60-61`)改 `[Int: ItemID]`(BS-1 DTO,`06-F46`)。
  - 验证:`targeted` 下这些跨域点不再出现"capture non-Sendable"错误。
- [ ] **7.6 裸 `Task{}` 显式化(06-F06/F07/F10)** — `AppDelegate.swift:55,67,73,80,90,96`(6 处 `Defaults.updates` 循环):类型级 `@MainActor` 后,裸 `Task{}` 继承 MainActor,编译器可证;删除内部 `@MainActor`(若冗余)或保留显式 `Task{@MainActor in}`。`History.swift:70,76,82,88,96`(5 处 `Defaults.updates`)同上。`History.swift:116,170,246,270,292,340,379`(纯 UI 标志位翻转/通知):改 `Task{@MainActor in …}` 显式化或 `MainActor.assumeIsolated`(`06-F07`)。`Popup.swift:197,223`(本地 monitor 内 `Task{@MainActor}`):直接调用 `AppState.shared.history.select(item)`(已在 main,`06-F10`)。
- [ ] **7.7 跨域闭包隔离(06-F13/F14/F18/F19/F20/F21/F22/F23)** —
  - Timer(`Clipboard.swift:55-63`):改 `Timer.scheduledTimer(withTimeInterval:repeats:block:)`,`[weak self]` block 内 `MainActor.assumeIsolated { self?.checkForChangesInPasteboard() }`(`06-F13`)。
  - `paste()`(`:117-146`):`@MainActor func paste()`(CGEvent `tap: .cgSessionEventTap` 主线程契约,`06-F14`)。
  - KVO(`AppDelegate.swift:61-65` `observe(\.statusItem.isVisible)`):类型级 `@MainActor` 后闭包在 main;或 `MainActor.assumeIsolated` 包 Defaults 写(`06-F20`)。
  - `DistributedNotificationCenter`(`AppDelegate.swift:222-260` `queue: .main` + `Task{@MainActor}`):保留 `Task{@MainActor}`,确认闭包捕获 `Sendable`(`06-F19`)。
  - `NotificationCenter`(`AppDelegate.swift:203-211` `disableUnusedGlobalHotkeys`、`ContentView.swift:64` publisher):`.receive(on: DispatchQueue.main)` 或转 `notifications(for:).sink`(`06-F21`)。
  - 全局 monitor(`PasteStack.swift:13-30`):闭包加 `@Sendable`(`NSEvent.addGlobalMonitorForEvents` 的 handler 在 Swift 6 要求 `@Sendable`);`pasteDown` 改 `@MainActor` 之外的隔离或 `Atomic<Bool>`(`06-F22`)。本地 monitor(`Popup.swift:60-67`)同理(`06-F23`)。
  - 验证:`targeted`(SWIFT_VERSION=5)build + test 全绿。**这是 P1 编译检查点。**

### 阶段 P2 — SWIFT_VERSION 6.0(`targeted`)

- [ ] **7.8 `@objc` + 隔离对齐(06-F13/F14)** — 升 `SWIFT_VERSION = 6.0`(`:1589,1616,1640,1664,1820,1855`)。Swift 6 下 `@objc @MainActor func checkForChangesInPasteboard()`(`Clipboard.swift:156-158`)与 `performStatusItemClick()`(`AppDelegate.swift:164-181`)、`statusItem.button?.target = self`/`#selector`(`AppDelegate.swift:25,28`)的 target-selector 交互需复核:Timer 改闭包形式后 `@objc` selector 不再需要(可移除 `@objc`);`@objc` 方法继承类型级 `@MainActor` 默认行为需确认(AppKit 协议方法在 Swift 6 默认 `@MainActor`)。
- [ ] **7.9 `deinit`/释放路径复核(06-F11/F17)** — Swift 6 下 `deinit` 默认 `nonisolated`;`ApplicationImage.deinit { eventSource?.cancel() }`(`:21-23`)、`Popup`/`FloatingPanel` 的 `deinit { deinitEventsMonitor() }`、`HistoryItemDecorator` 的图像清理(`:131-147`)需确认 `nonisolated deinit` 内不访问 `@MainActor` 状态(若需,用 `MainActor.assumeIsolated` 或把可变状态移出)。`Storage.recoverContainer` 的 `Task{@MainActor in NSAlert().runModal() }`(`:43-51`)改 throwing 或同步 alert(BS-0 已动过 recoverContainer,本步对齐隔离)。
- [ ] **7.10 C++/ObjC 桥接 `nonisolated`(06-F36/F37/F38)** — `MaccyTextProcessor.mm:5` ObjC 类:`ClipboardDataProcessor` 的 `nonisolated static func`(`:6,31,39,62`)在 Swift 6 下要求 ObjC 侧可证线程安全;若桥接器无法证明,新增 `Maccy/Concurrency/SendableWrappers.swift` 薄封装:`nonisolated func maccy_fingerprint(_ data: Data) -> UInt64 { MaccyTextProcessor.fingerprint(for: data) }`(C++ 已确认纯函数,`ClipboardByteProcessor.cpp` 仅 `constexpr`)。验证:`targeted` + `SWIFT_VERSION=6.0` build + test 全绿。**这是 P2 编译检查点。**

### 阶段 P3 — `complete`

- [ ] **7.11 值类型 Sendable 化(06-F26/F27/F28/F29)** —
  - `Selection<Item>`(`Selection.swift:3`):泛型值类型,当 `Item: Sendable` 时自动 Sendable;`Selection<HistoryItemDecorator>` 因 decorator 已 `@MainActor`(P1)而 `Sendable`,确认无跨域实例化。
  - `KeyShortcut`(`KeyShortcut.swift:5`):`struct KeyShortcut: Sendable`(`var key: Key?` 的 `Sauce.Key` Sendability 需确认;若 `Key` 非 Sendable,投影为 `String`)。
  - `Throttler`(`Throttler.swift:4-38`):`@MainActor final class Throttler` 或 `actor`;`workItem`/`previousRun` 在 main 改(`06-F29`)。
  - `Search`(`Search.swift:7`)、`Sorter`(`Sorter.swift`):`@MainActor` 或改纯 `struct`(BS-5 已重构搜索;本步补标注),`SearchResult`(`Search.swift:22`)加 `: Sendable`。
  - `SoftwareUpdater`(`SoftwareUpdater.swift:3`)、`Notifier`(`Notifier.swift:5-62`):`@MainActor`;`hasRequestedAuthorization`(`Notifier.swift:6`)的 `static var` 改 `@MainActor` 或 `actor NotifierStore`(`06-F30/F31`)。
- [ ] **7.12 AppIntent 默认执行器(06-F25)** — `complete` 下 `AppIntent.perform()` 默认在非 MainActor 执行器;P1 已改 `@MainActor func perform()` 或 DTO 投影。复核 `Delete/Get/Select/Clear.perform()` 内**所有** `AppState.shared.*` 访问经 `await`/DTO;`HistoryItemAppEntity` 不持 `@Model`。`AppStoreReview`(`AppStoreReview.swift:18` `DispatchQueue.main.asyncAfter`)、`FloatingPanel`(`FloatingPanel.swift:83`)、`PasteStackView`(`PasteStackView.swift:44`)的 `main.async` 闭包确认捕获 `Sendable`(`06-F32/F33/F34`)。
- [ ] **7.13 Combine/Observation 线程收敛(06-F09/F21)** —
  - `HistoryItemDecorator.synchronizeItemPin/synchronizeItemTitle`(`:227-263`)与 `AppDelegate.synchronizeMenuIconText`(`:183-197`)的 `withObservationTracking + DispatchQueue.main.async` 自重装递归:改 computed mirror(`var title: String { item.title }` 让 SwiftUI 观察直接生效)或 `for await _ in AsyncStream { … }`(`06-F09`)。**此为唯一行为级改动**,需对照测试:标题/快捷键/菜单图标在 `pin`/`title`/`menuIconText` 快速变化时不丢更新。
  - `ContentView.swift:64` publisher 已在 7.7 加 `.receive(on:)`。
- [ ] **7.14 entitlements/Info.plist 复核(06-F35/F50)** — `Maccy.entitlements:5-13` Sparkle XPC mach-lookup(`-spks`/`-spki`)的委托回调闭包确认 `@Sendable`(`SoftwareUpdater` 已 `@MainActor` + `Task{@MainActor}`);若 Sparkle 2.x Sendable 注解缺失,在 `SendableWrappers.swift` 封装。`Info.plist` 复核:无后台模式/XPC 服务条目,与 entitlements 隐含的 XPC 并发一致(`06-F50`)。验证:`complete` + `SWIFT_VERSION=6.0` build + test 全绿;`xcodebuild build ... 2>&1 | grep -i "strict concurrency\|sendable\|actor-isolated"` 无残留。**这是 P3 编译检查点。**

### 阶段 P4 — 收尾清理

- [ ] **7.15 删除冗余 per-method `@MainActor`** — 类型级 `@MainActor` 落地后,62 处 per-method `@MainActor`(审计 `06` §0 计数)的大部分变冗余;逐文件删除并保留编译。`@MainActor deinit`(Swift 6.0 新特性)按需。
- [ ] **7.16 复核 C++ 标准** — `CLANG_CXX_LANGUAGE_STANDARD`(`:1676,1739`)评估升 `gnu++20`(若 BS-8 xxh3 需 `std::span`/`constexpr` 增强);否则留 `gnu++17`(`06-F49`)。
- [ ] **7.17 全量验证** — `xcodebuild build` + `xcodebuild test`(含 `MaccyPerformanceTests`)全绿;`xcodebuild -dry-run` 无新增告警;手动冒烟:复制/粘贴/搜索/置顶/OCR 标题/PasteStack 行为零回归。

## 测试

- 引用:`B-test-strategy.md §5`(finding→测试矩阵)、`§4`(性能闸门不变,本步非性能步骤)。
- 新增:
  - `SendableBoundaryTests`:跨域载荷(`ItemSnapshotDTO`/`ContentDTO`/`StoreEvent`)经 `@Sendable` 闭包传递编译期通过(用 `@Sendable (Any) -> Void` 探针调用,运行时断言无陷阱)。
  - `ObservationMirrorTests`:`pin`/`title`/`menuIconText` 在 1ms 内连续变化 100 次,断言最终态与 `@Model` 一致(覆盖 7.13 的递归移除)。
  - `ClipboardIsolationTests`:`Timer` 闭包形式下 `checkForChangesInPasteboard` 在 main 执行(`MainThreadProbe`)。
  - `AppIntentDtoTests`:`Get/Delete/Select/Clear.perform()` 经 DTO 投影,返回值与 `@Model` 直接读一致(对照改前)。
- 闸门:无新增性能闸门(本步是类型安全/隔离,不改算法或线程拓扑;`G-copy-text`/`G-popup-open`/`G-search` 保持 BS-2/4/5 的基线)。
- 复杂度/管线:**不变**。本步不改任何运行时复杂度或管线拓扑(摄取仍在 BS-2 的后台 actor,搜索仍在 BS-5 的后台 actor)。关键点是:**去 `@unchecked Sendable` 依赖 BS-1~6 已建立的真实隔离**——decorator/AppDelegate 之所以能去 `@unchecked`,是因为 UI 可变状态已归 `@MainActor`、数据/图片经 BS-2/3 的 actor、跨域载荷已统一为 BS-1 的 Sendable DTO;若 BS-1~6 未完成,`@unchecked` 无法安全删除,本步骤应推迟。

## 验收标准

- 功能:复制/去重/容量裁剪/搜索/置顶/OCR/PasteStack/AppIntent 行为与改前逐项一致(冒烟 + 自动化对照)。
- 构建:`SWIFT_VERSION = 6.0` + `SWIFT_STRICT_CONCURRENCY = complete` 下 `xcodebuild build` 全绿且**零并发相关警告**;`@unchecked Sendable` 计数 = 0(改前 2:decorator `:8`、AppDelegate `:6`)。
- 隔离:`@Model HistoryItem`/`ModelContext` 不出现在任何 `@Sendable` 闭包捕获或跨 actor 函数签名(经 DTO 投影);`OnNewCopyHook` 不再传递 `HistoryItem`。
- 复杂度:不变(类型安全/隔离步骤,不改算法)。
- 管线:不变(BS-2/4/5 已落地的后台 actor 拓扑本步只做隔离标注强化)。
- I/O 限制:不变。
- 不变性:`A §7` 的"跨 actor 载荷 Sendable""`@Model` 不跨域"由**编译器在 `complete` 级强制**(改前由 `@unchecked` 静默);"主线程无重活"由 BS-2/3/5 已落地,本步不再引入新的主线程同步路径。

## Commit

按阶段分提交(P0~P4 各一),末态:

`build(swift6): migrate to swift 6 strict concurrency (complete) — drop @unchecked Sendable, type-level @MainActor isolation, sendable DTO boundaries, no cross-actor @model/context`

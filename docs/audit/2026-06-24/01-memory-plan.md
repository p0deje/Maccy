# BS-6+ — 内存治理全面计划(实测驱动,2026-06-24)

> **上位文档**:`AGENTS.md`(执行纪律)、`docs/audit/2026-06-14/roadmap/step-6-memory.md`(原 BS-6)、`docs/audit/2026-06-24/00-memory-profile.md`(实测画像,本计划的事实依据)、`A-architecture-target.md`、`B-test-strategy.md`、`C-complexity-and-limits.md`。
>
> **本计划与原 BS-6 的关系**:**扩展**而非取代。原 `bs6.1`–`bs6.12`(图像/缓存封顶、可视区+告警回收、`sessionLog` 迁移)**保留**(仍是正确且路线图要求的工作,压峰值、关闭 `05` 审计项);据 2026-06-24 实测画像新增 `bs6.13`–`bs6.16`(HotKey 泄漏、观察环、盲区、框架项)。**目标从"稳态 <300MiB"上调为"全力逼近 <100MiB 稳态"**(用户 2026-06-24 指令)。

**目标**:把 Maccy 稳态 phys_footprint 从实测 **213MB**(峰值 415MB)尽全力压到 **<100MB**。按实测杠杆排序,先吃最大单项(HotKey 泄漏 ~40MB),再补 BS-6 核心(压峰值 + 关审计项 + 稳态 −10~20MB),并用重抓的盲区数据攻 36.6MB non-object。

**依赖**:BS-3(缩略图/预览管线 `ImageProcessor`/`ThumbnailCache` 已就位);**不依赖 BS-5(文本搜索)** —— 用户 2026-06-24 明确跳过 BS-5 先做内存,依赖安全。`sessionLog` 迁移原计划在 BS-4.6,**实测未做**(`History.swift:140` 仍 `[Int: HistoryItem]`),故 `bs6.5` 在此完成。

**编译边界**(同原 BS-6):`bs6.4` 改 `HistoryItemDecorator` 字段/视图接线会临时破坏既有视图/初始化,`bs6.7` 恢复;末尾全绿。新模块(`bs6.1`–`bs6.3`、`bs6.8`、`bs6.9`)为纯加法可单独编译。`bs6.13`(HotKey)与 `bs6.14`(观察环/autoreleasepool)各自独立小步,单独可编译可测。

**无本机工具链**(`CLAUDE.md`):不本地 build/test/lint;一切经 GitHub Actions(`macOS 26 ARM CI`,~11min)。UI 行为(弹窗热键、预览、滚动)CI 不可全验,**需用户手动复核**(各步"手动验证"列明)。

## 受影响文件(汇总)

- **新**(`Maccy/Memory/`,目录不存在,全为新建):`VisibilityTracker.swift`、`MemoryGovernor.swift`、`DecodedImageCache.swift`、`ColorSwatchCache.swift`、`RegexpCache.swift`。
- **改 `HistoryItemDecorator.swift`**:加 `releaseTransientImages(_:)`、`VisibilityObserving` 一致性;`imageDataCache` 改可 nil(按需重取);删 `sizeImages()`/`.recache()`;`textPreviewCache` 随 purge 清;观察 token 化(`bs6.10`)。
- **改 `History.swift`**:`sessionLog` `[Int: HistoryItem]`→`[Int: UUID]`(`:140` + 5 调用点);`extension History: HistoryRef`;`.imageMaxHeight` 观察改 `releaseTransientImages(.settingChange)`;`load()`/`clear()`/`clearAll()` 循环包 `autoreleasepool`(`bs6.14`)。
- **改 `ApplicationImageCache.swift` / `ApplicationImage.swift`**:Dict→`NSCache`(countLimit=128)+`purge()`;fd `defer` 守护;`eventMask: [.delete, .rename]`;4 处 `print`→`logger`。
- **改 `ColorImage.swift`**:抽 `ColorSwatchCache`;`lockFocus`→`NSImage(size:flipped:drawingHandler:)`。
- **改 `Clipboard.swift`**:`ignoredRegexps`→`RegexpCache` + `Defaults.updates(.ignoreRegexp)` 重建。
- **改 `AppDelegate.swift`**:挂 `applicationDidReceiveMemoryWarning`→`MemoryGovernor`;`attach(history:)` + `start()`。
- **改 `Views/HistoryItemView.swift`**:`.onAppear`/`.onDisappear` 对称回收 + `VisibilityTracker` 注册;`accessoryImage` 走 `ColorSwatchCache`。
- **改 `Views/PreviewItemView.swift`**:popover 关闭触发 `releaseTransientImages(.previewHidden)`。
- **改 `Observables/Popup.swift`**(`bs6.13`):消除 `.popup` 每次 开/关 的 `enable`/`disable` 重注册泄漏。
- **改 `Models/HistoryItem.swift`**(`bs6.14`,微):内联 `Logger(label:)` → 共享静态 logger。

## 小步骤

> 编号沿用 `bs6.x`。`bs6.1`–`bs6.12` 为原 BS-6(按当前 HEAD 校准);`bs6.0`/`bs6.13`–`bs6.16` 为本次据实测新增。每步:TDD(行为变更先写失败测试)→ 最小正确实现 → 聚焦测试 → 提交(`feat/fix/docs(bs6.x): …`)。大步全绿后推送。

### 诊断前置

- [ ] **bs6.0 重抓盲区(诊断,需用户在 macOS 跑)** — 攻 §2 的 36.6MB non-object。
  - 关闭 Maccy → 终端 `MallocStackLogging=1 MallocStackLoggingDirectory=/tmp/msl open -n /Applications/Maccy.app`(或 `export MallocStackLogging=1` 后启动)。
  - 复现重负载:历史含 ~200 条、20% 图;完整滚动浏览一次 + 预览若干 + 触发一次系统内存告警(或 `memory_pressure -l critical` / `notifyutil -p com.apple.system.lowmemorynotification`)。
  - 抓:`heap --sortBySize Maccy > maccy2.heap.txt`、`leaks Maccy > maccy2.leaks.txt`、`malloc_history Maccy --eventsByStack > macc2.mh.txt`、`vmmap --summary Maccy`、另在 **peak 中**与 **Clear History 后**各抓一份 leaks。
  - 目标:把 36.6MB non-object 归因到类/回溯;确认 HotKey 修复后碳注册数回到个位数;确认观察环在 Clear 后是否消失(区分活对象 vs 真泄漏)。
  - **此步阻塞 `bs6.15`**(削减盲区)与最终 <100MB 判定。

### HotKey 泄漏(最大单项,~40MB;偏离原 BS-6 字面,记录见末尾)

- [ ] **bs6.13 修复 Popup `.popup` 重注册泄漏** — `Popup.swift:52,84,123`;`AppDelegate.swift:236-246`。
  - **实测根因**(`00-memory-profile.md` §2)+ **包源码确认**(KeyboardShortcuts 2.0.2,revision `e6b60117`,`CarbonKeyboardShortcuts.swift` / `KeyboardShortcuts.swift`):
    - `HotKey.carbonHotKey` 783 实例/43.5MB,运行 2 天。Popup 每次开关循环:`disable(.popup)`(`:123`,开窗)→ `enable(.popup)`(`:84`,经 `reset()←panel.close()`)。
    - `KeyboardShortcuts.enable`→`register`→`CarbonKeyboardShortcuts.register`:**`hotKeyId += 1` + `RegisterEventHotKey`(新 ref)+ 新 `HotKey`**;`disable`→`UnregisterEventHotKey`+移除。故**每个 enable 都是一次全新 `RegisterEventHotKey`**(`register` 的 `registeredShortcuts` 去重在 disable 后失效),~58KB Carbon backing 未被 `UnregisterEventHotKey` 回收 → 按 开/关 次数线性泄漏。`AppDelegate.disableUnusedGlobalHotkeys` 只在启动+`.delete`/`.pin` 改键时调,**与泄漏无关**。
    - 包内有 `isPaused`(`handleOnKeyDown` 里 `guard !isPaused else { return }`,不重注册)——**但 `isPaused` 是 `internal`,非 `public`,Maccy 用不了**。`isEnabled`(全局)走 `softUnregisterAll`/`softRegisterAll`,**同样重注册、同样漏**。故无公共"暂停"API。
    - **关键性质(Option 1 可行性依据)**:包的 `handleHotKeyEvent` 命中后 `return noErr`(事件被消费)→ Carbon 全局热键**拦截**该 keyDown,**不传到 app 的本地 `eventsMonitor`**。故让 `.popup` 常驻注册、把开窗内热键行为路由进 `handleFirstKeyDown`,**可精确保留** cycle/select/toggle-close 语义(本地 monitor 不再看到热键 keyDown,但 `flagsChanged` 非热键、仍由本地处理 → modifier-release-select 不变)。
  - **选定修复(Option 1,零包改动,零依赖升级)** — `Popup.swift`:
    1. 删 `KeyboardShortcuts.disable(.popup)`(`:123`)与 `enable(.popup)`(`:84`);`.popup` 仅由 `init` 的 `onKeyDown` 注册一次,进程内常驻。
    2. `handleFirstKeyDown` 的 else 分支(原 `close()`)改为 `_ = handleRepeatedHotKeyDown()`(开窗内热键 → cycle/select/toggle-close)。
    3. `handleRepeatedHotKeyDown`:把 `if let event, state == .toggle && isHotKeyModifiers(event.modifierFlags)` 改为 `if state == .toggle`(全局路径下热键必带其修饰键,故 toggle-close 必然成立)。
    4. 本地 `handleKeyDown`:去掉 `isHotKeyCode` 分支(全局已拦截,此分支不可达),直接 `return event` 保非热键导航;若 `isHotKeyCode`/`isHotKeyModifiers` 因此变为 unused,一并删除(避 SwiftLint unused 警告 → CI `--strict` 失败)。
  - **测试**:注册计数无 public 内省 → **不能单测**"不重注册"。`MaccyTests/PopupTests`(若存在)补:开→关 循环后 `handleFirstKeyDown` 在开窗态走 cycle/toggle 路径(状态机正确性)。**主验靠手动**。
  - **手动验证(用户必做,UX 门禁)**:开/关弹窗 50+ 次后 (a) 热键仍 toggle;(b) 按住修饰键连按热键仍 cycle 高亮、松手 select;(c) toggle 态再按热键仍 close;(d) `heap Maccy | grep carbonHotKey` 实例数从 ~50 降到 ≤1。

### BS-6 核心(原路线图,按当前 HEAD 校准)

- [ ] **bs6.1 可视区跟踪协议** — 新 `Maccy/Memory/VisibilityTracker.swift`。`protocol VisibilityObserving` + `@MainActor final class VisibilityTracker`(register/unregister/isVisible/snapshot)。`HistoryItemDecorator` 一致性:`onAppearInViewport`→`ensureThumbnailImage()`;`onDisappearFromViewport`→`releaseTransientImages(.scrollOut)`。纯加法。
- [ ] **bs6.2 `DecodedImageCache`(NSCache)** — 新 `Maccy/Memory/DecodedImageCache.swift`。`NSCache<NSUUID, NSImage>`(`countLimit=32`,`totalCostLimit=64MiB`,cost=W·H·4)。**落地时核对与 BS-3 `ThumbnailCache.swift` 的分工**(预览解码位图 vs 缩略图;若重叠则合并/复用,不造第二套)。纯加法。
- [ ] **bs6.3 `MemoryGovernor`(@MainActor)** — 新 `Maccy/Memory/MemoryGovernor.swift`。`protocol HistoryRef` + `enum Reason { scrollOut, previewHidden, settingChange, memoryWarning, invalidate }`;`handleMemoryWarning()`→ 非可视区 `releaseTransientImages(.memoryWarning)` + `DecodedImageCache.purgeAll()` + `ApplicationImageCache.purge()` + `RegexpCache.purgeStale()` + `ThumbnailCache` 内存层 `removeAllObjects()`(磁盘留,BS-3 API)。纯加法。
- [ ] **bs6.4 [breaks compile until bs6.7] decorator 去常驻 + 解码位图走 NSCache** — `HistoryItemDecorator.swift`。
  - **当前已比原 6.4 前进**:`decodedImage` 字段已无(BS-3);`imageData` 已懒加载。本步剩余:`imageDataCache`(`:92`)改为**可 nil**(告警/`scrollOut` 时置 nil,下次取按需重读 `item.imageData`,任务结束释放)→ 关 `img-fullres-dup-storage` 收尾;新增 `releaseTransientImages(_:)`(`.scrollOut` 清 `previewImage`+`DecodedImageCache.evict(id)`,留缩略图;`.previewHidden` 清 `previewImage`;`.settingChange`/`.memoryWarning`/`.invalidate` 全清 + 取消任务 + `textPreviewCache=nil`);`cleanupImages()`(`:206`)→ 内部调 `releaseTransientImages(.invalidate)`,删 `.recache()`(`:211-212`,IMG-037 收尾);删 `sizeImages()`(`:238`,死代码)。
- [ ] **bs6.5 `History` 实现 `HistoryRef` + `sessionLog` 迁移** — `History.swift`;`AppDelegate.swift`。
  - **`sessionLog: [Int: HistoryItem]`(`:140`)→ `[Int: UUID]`**(BS-4.6 实测未做)。5 调用点:`add`(`:253` 存 `item.id`)、`clear`(`:466` `removeValues` 按 UUID 反查 pinned)、`clearAll`(`:492` OK)、`delete`(`:523` `{ $0 == item.item.id }`)、`isModified`(`:740-746` 改 id 反查;签名若仍返 `HistoryItem?`,经 id→model 取或改调用方)。关 `05 sessionlog-keeps-historyitem`。
  - `extension History: HistoryRef { func decorators() -> [HistoryItemDecorator] { all } }`;`AppDelegate.applicationDidFinishLaunching` 注入 `MemoryGovernor.shared.attach(history: History.shared)` + `.start()`。
- [ ] **bs6.6 `ApplicationImageCache`→NSCache + fd 守护** — `ApplicationImageCache.swift:8-23`;`ApplicationImage.swift:14,42-93`。
  - `cache: NSCache<NSString, ApplicationImage>`(`countLimit=128`,`totalCostLimit` 见 `C`);`getImage(item:)` 走 `object(forKey:)`/`setObject(_:forKey:cost:)`;加 `purge()`。关 `appicon-cache-unbounded`(`ApplicationImage.deinit` 已 cancel `DispatchSource`,审计确认正确)。
  - fd 守护(07-F-018):`open(...)` 后 `makeFileSystemObjectSource` 前加 `defer { if !sourceCreated { close(descriptor) } }` 等价护栏;`eventMask: [.delete, .rename]`(去 `.write`,IMG-010);4 处 `print`(`:51,52,71,77`)→`logger`。
- [ ] **bs6.7 [restores compile] 接线 + 视图 onDisappear + 告警挂载** — `AppDelegate.swift`;`HistoryItemView.swift:48-50`;`PreviewItemView.swift`。
  - `AppDelegate`:挂 `applicationDidReceiveMemoryWarning(_:)`(或注册 `NSApplication.didReceiveMemoryWarningNotification`)→`MemoryGovernor.shared.handleMemoryWarning()`;`attach`+`start()`(可与 bs6.5 合并提交)。
  - `HistoryItemView`:`.onAppear { VisibilityTracker.shared.register(item); item.onAppearInViewport() }` + `.onDisappear { item.onDisappearFromViewport(); VisibilityTracker.shared.unregister(item) }`;`accessoryImage`(`:39`)走 `ColorSwatchCache`(bs6.9)。
  - `PreviewItemView`:popover 关闭回调 `item.releaseTransientImages(.previewHidden)`。
- [ ] **bs6.8 `RegexpCache` + 重建** — 新 `Maccy/Memory/RegexpCache.swift`;`Clipboard.swift:11,287-314`。删 `ignoredRegexps` 字典;`shouldIgnore` 走 `RegexpCache.shared.regex(for:)`;`Task { for await _ in Defaults.updates(.ignoreRegexp, initial: true) { RegexpCache.shared.rebuild(from: Defaults[.ignoreRegexp]) } }`。关 `regex-cache-unbounded`。
- [ ] **bs6.9 `ColorSwatchCache`** — 新 `Maccy/Memory/ColorSwatchCache.swift`;`ColorImage.swift`。把 `ColorImage.swift:15-19` 的内联 `NSCache`(4.10d stopgap)抽成 `ColorSwatchCache`;`lockFocus/unlockFocus`(`:32-34`)→`NSImage(size:flipped:drawingHandler:)`(IMG-029);`from(_:)` 一行委托。关 `colorimage-rebuild-per-render`。
- [ ] **bs6.10 观察重注册足迹收敛(minor)** — `HistoryItemDecorator.swift:367-403`。`synchronizeItemPin/Title` 的 `withObservationTracking` 包进 `@ObservationIgnored private var token`,`invalidate` 时 `token=nil` 同步取消尾挂。主要为 BS-7 隔离确定性。
- [ ] **bs6.11 测试** — 见下"测试"节。
- [ ] **bs6.12 验证** — CI build + test 全绿;手动:200 条 20% 图,滚览 5min + 预览若干,常驻 RSS 对比改前;注入内存告警 → 非可视区缩略图/解码位图清空,RSS 回落;HotKey 修复后开/关 50 次 `carbonHotKey` 不增。量化记 `G-memory`。

### 实测新增(观察环 / autoreleasepool / 盲区 / 框架)

- [ ] **bs6.14 观察环 + autoreleasepool + 共享 logger** — `HistoryItemDecorator.swift`、`History.swift`、`HistoryItem.swift`。
  - **观察环**(`00` §4,14 环/201KB):decorator 强持 `@Model item` + 观察它 → 成环。改 `private(set) var item` 持有方式:`invalidate()` 时显式断观察(`token=nil`,bs6.10)+ 清空 `withObservationTracking` 注册,使 decorator 失效后不再 pin 住模型图(模型由 `mainContext` 生命周期管理)。**不**把 `item` 改 `weak`(decorator 全程需要它,weak 会在 context refresh 后失效)。目标:Clear History 后 leaks 中 `HistoryItem` 环消失。
  - **autoreleasepool**(`05 no-autoreleasepool-loops`):`load()`(`:200-213`)、`reconcileWithStore`(`:349-382`)、`clear()`(`:453-478`)、`clearAll()`(`:481-504`)的逐项循环内包 `autoreleasepool { … }`,收敛瞬态 AppKit(`NSImage`/`NSAttributedString`/`AttributedString`)分配,降峰值 + 降碎片。
  - **共享 logger**:`HistoryItem.swift:233,245` 内联 `Logger(label:)`(每次调用新建)→ 共享 `static let logger`;`HistoryItemDecorator.swift:130` 的实例 logger 评估改 static(242 实例 × 小,微收益,顺手)。
- [ ] **bs6.15 [阻塞于 bs6.0] 盲区削减** — 据 `bs6.0` 的 `malloc_history` 归因,定向削减 36.6MB non-object 中可归因部分。**待数据填具体子步**(可能是:某缓存/某临时大缓冲/某重复构造)。
- [ ] **bs6.16 框架/AttributeGraph/CoreText 调查(ROI 梯度)** —
  - AttributeGraph(~7MB,149624 节点):核对开窗后离屏行视图图是否被保留;`bs6.7` 的 onDisappear 已减装饰器侧,视图侧靠 `LazyVStack`(已用)。调查是否有非必要的 `@Observable` 订阅放大图。
  - CoreText(~1.7MB):`titlePreviewLimit=1000` + `.middle` 截断是放大器(MEMORY.md `render-chain-sample-root-cause`)—— 若 BS-4.10f 已处理则核对无回退;否则评估下调。
  - 碎片(28MB,34%):`bs6.14` autoreleasepool + 减长寿命小对象(观察环)自然降。
  - WebKit(~90MB resident text):**记录为传递性、低 ROI、不擅动**(见 `00` §3)。

## 测试

- 引用:`B-test-strategy.md §2/§4`(`FixtureLoader` 合成图、`HistoryBuilder`、`MainThreadProbe`、`G-memory`)。
- **新增**:
  - `HotKeyLeakTests`:N 次开关循环后注册计数不单调增(spy/计数桩;主验靠手动 `heap | grep carbonHotKey`)。
  - `MemoryGovernanceTests`:`releaseTransientImages_scrollOut_keepsThumbnail_evictsPreview`;`releaseTransientImages_memoryWarning_clearsNonVisibleDecoded`(注入 `handleMemoryWarning`,断言非可视区 `previewImage==nil` 且 `DecodedImageCache` 空);`onAppear_rearmsThumbnail_afterScrollOut`。
  - `DecodedImageCacheTests`:countLimit/totalCostLimit 淘汰;`evict`/`purgeAll`。
  - `ApplicationImageCacheTests`:countLimit=128 淘汰;`purge()` 清空且 `ApplicationImage.deinit`→`eventSource?.cancel()`(spy 计数);fd 守护(注入失败 `makeFileSystemObjectSource` 桩,断言 `descriptor` 被 `close`)。
  - `RegexpCacheTests`:`Defaults[.ignoreRegexp]` 重建后 stale 项消失;命中/未命中。
  - `ColorSwatchCacheTests`:同 hex 同实例;异 hex 异实例。
  - `SessionLogReleaseTests`:`sessionLog` 存 UUID;`HistoryItem` delete 后不再引用其 id;`add` 后 `isModified` 仍命中。
  - `ObservationCycleTests`(bs6.14):Clear History 后 leaks 中无 `HistoryItem` 环(或断言 decorator 失效后不再持观察注册)。
- **闸门**:`G-memory`(`B §4`):200 条 20% 图,滚览+预览 5min,常驻 < 150MiB(阶段目标);最终 <100MiB(依赖 bs6.0/bs6.15)。独立 `MaccyPerformanceTests` target(若仍未建,本计划顺手建)。改性能 PR 须绿。

## 验收标准

- **功能(零回退)**:复制/预览/缩略图/去重/弹窗 toggle/热键 cycle 与改前一致(用户可见);滚出可视区再回能重建缩略图;预览关闭后预览位图释放;内存告警后非可视区位图+解码缓存+应用图标缓存清空,App 不崩、列表仍可交互;**开/关弹窗 50 次热键行为不变且 `carbonHotKey` 不增长**。
- **量化(阶段)**:
  - `bs6.13` 后:稳态 **~150–170MB**(−40MB);peak 不变。
  - `bs6.1`–`bs6.12` + `bs6.14` 后:peak **415→<250MB**;稳态再 −10~20MB → **~130–150MB**。
  - `bs6.15`(盲区)+`bs6.16` 后:逼近 **<100MB 稳态**(硬性达标依赖 bs6.0 归因)。
- **管线(`C §3`)**:不引入新端到端时延;滚动流畅度不回退。
- **I/O(`C §2`)**:`DecodedImageCache` 32/64MiB;`ApplicationImageCache` 128;缩略图磁盘 ≤256MiB(BS-3);`sessionLog` 不持模型;fd:每 `ApplicationImage` 一个 `O_EVTONLY`,`NSCache` 淘汰 deinit 关,有守护。
- **不变性(`A §7`)**:主线程无重活(BS-3 后位图经 actor);跨 actor 载荷 Sendable(MemoryGovernor/DecodedImageCache 走 `@MainActor` 或 NSCache 线程安全)。

## 偏离记录(AGENTS.md 要求,提交前先记)

- **bs6.13(HotKey 泄漏)**:不在原 `step-6-memory.md`。据 `00-memory-profile.md` §2/§7 实测(43.5MB,占可归因堆 49%,单一最大项)新增。改动弹窗热键 enable/disable 路径(用户可见行为邻接)→ **严格 TDD + 用户手动复核 toggle/cycle 语义**,二选一修复方向见上。
- **bs6.0/bs6.15(盲区)**:36.6MB non-object 是 `heap` 因 MSL 关闭的盲区;`step-6-memory.md` 未预见。需用户重抓,达标(<100MB)依赖其结果。
- **目标上调**:原 BS-6 "稳态 <300MiB" → 本计划 "逼近 <100MB 稳态"(用户 2026-06-24 指令);`G-memory` 闸门相应收紧。
- **bs6.14(观察环/autoreleasepool/logger)**:对 `05` 已列项(`no-autoreleasepool-loops`/环)的收尾,非新发现,但聚为一步。
- `bs6.16` WebKit 记为传递性、低 ROI、**不擅动**,避免无效改动。

## Commit / 推送纪律

- 每小步 TDD 后提交,信息名 `bs6.x`(`feat/fix/docs/perf(bs6.x): …`)。
- 大步全绿后推送(BS-6+ 整体作为一个大步:bs6.0 诊断 + bs6.1–bs6.16 全绿 + CI 绿 + 用户手动验证绿 → 推送)。
- 文档先行:`00-memory-profile.md` + 本 `01-memory-plan.md` 已写;每完成一步更新本文 checkbox + `00` 的实测复测数字。

## 执行序建议(收益最大化)

`bs6.0`(用户并行重抓)→ **`bs6.13`(HotKey,最大单项,先吃)** → `bs6.1`–`bs6.9`(BS-6 核心,纯加法先行)→ `bs6.4`–`bs6.7`(编译边界,合并落地)→ `bs6.10`/`bs6.11`/`bs6.12` → `bs6.14`(环+autoreleasepool)→ 据 bs6.0 结果做 `bs6.15` → `bs6.16` 调查 → 复测,逼近 <100MB。

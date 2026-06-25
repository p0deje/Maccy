# Master Plan — Maccy 性能与内存全面优化(2026-06-25)

> **本文件是新的执行总纲**,整合 `docs/audit/2026-06-24/00-memory-profile.md`(实测画像)+ 本目录 2026-06-25 全分析(`00`–`13e`,21 份,已逐条核实 vs HEAD `04298ab`)+ 旧路线图 `docs/audit/2026-06-14/roadmap/` 的未做部分。**取代** 2026-06-14 step-by-step 路线图作为后续执行依据(旧文档保留为历史)。
>
> **目标**:(1) 稳态 `phys_footprint < 100MB`;(2) 主线程 `< 16ms/事件`。按 **影响 × effort** 分 P0–P3 tier。**执行纪律**:TDD(行为变更先失败测试)→ 最小正确实现 → 聚焦测试 → 提交 → 推 CI;**CI 全绿 = 步骤 gate**(用户指令:UX 后测,非阻塞)。无本机工具链(`CLAUDE.md`)。

## 0. 现状基线(已核实 @ `04298ab`)

**已 DONE**:BS-1 并发脚手架、BS-2 ingest→actor、BS-3 图片管线(ImageIO/`ThumbnailCache`/`ImageProcessor`,off-main 解码,预览封顶 800²)、BS-4.2 签名索引去重、BS-4.4a 增量 consume(二分插入)、BS-4.7 预温、BS-4.10 预览封顶、**`bs6.13` HotKey 泄漏修复(CI green `28163959693`,10/10 shards)**。

**实测**(`docs/maccy.*.txt`,2026-06-24):`phys_footprint 213MB`(peak 415MB)= dirty 61MB + swapped(压缩)152MB → **驻留型**(97% 空闲却 1.75h 涨 100MB)。构成:HotKey 泄漏 43.5MB(**已修**)→ 残余盲区 36.6MB(non-object,需重抓)+ 框架/runtime ~50MB + 碎片 ~28MB。**图像+缓存仅 ~182KB、SwiftData <0.3MB**(BS-3 已解决,旧 BS-6 假设过时)。

**两条最大主线程瓶颈(旧内存计划漏掉)**:
1. `History.load()` 仍**全表 fetch + 全表装饰** O(n)(`History.swift:199-213`);`VisibleWindowLoader.fetchWindow` 已实现(`Storage+Background.swift:47-75`,带 fetchLimit + 可视/尾部切分)但**从未接入生产**(仅测试用)。
2. **搜索全表主线程扫描**(BS-5 被跳过);`Search` 是普通 class,`searchQuery.didSet` 经 `Throttler`(仅 debounce,仍主队列)每键扫全表(`History.swift:101-113`、`Search.swift:46-161`)。

**确认无问题(不再投入)**:图像管线(BS-3)、SwiftData/CoreData(<0.3MB)、`leaks` 总量(802KB)、WebKit resident text(传递性、COW、低 ROI)。

## 1. 诊断前置(阻塞盲区判定)

- [ ] **D1 `bs6.0` 重抓 36.6MB 盲区**(用户在 macOS 跑)— `MallocStackLogging=1` 启动 → 重负载(滚览+预览+内存告警)→ `heap --sortBySize` / `leaks` / `malloc_history --eventsByStack`,并在 **peak 中**与 **Clear History 后**各抓一份 leaks。目标:归因 36.6MB non-object;确认 HotKey 修复后碳注册数归零;确认 TIS 修复后 `TSMInputSource` 归零。**阻塞 < 100MB 终判**与 P3 盲区削减。

## 2. P0 — 低 effort 高回报(立即,各步独立可推 CI)

| ID | 问题 | 位置 | 修 | E | Δ | 状态 |
|---|---|---|---|---|---|---|
| **M1** | HotKey 重注册泄漏 ~43MB | `Popup.swift` | `.popup` 常驻注册,路由进 `handleFirstKeyDown` | — | — | ✅ DONE(CI green) |
| **M2** | `KeyboardLayout` TIS 泄漏 | `KeyboardLayout.swift:25` | `takeUnretainedValue()`→`takeRetainedValue()`(一行;**别动 `:16`** 那是 Get 规则) | 1 | **18417 个 `TSMInputSource` leak→0**(72% leaked bytes;~575KiB) | 待做 |
| **M3** | `sessionLog` 强引用 `@Model` | `History.swift:140,253,466,492,523,741` | `[Int: HistoryItem]`→`[Int: UUID]`(5 调用点) | 2 | 释放模型图 + 内容 blob;修 modification-merge 正确性 | 待做(=bs6.5) |
| **M4** | `ApplicationImageCache` 无界 + fd | `ApplicationImageCache.swift:8`;`ApplicationImage.swift:48-87` | Dict→`NSCache`(128)+`purge()`;fd `defer` 守护;`eventMask:[.delete,.rename]`;4 处 `print`→`logger` | 2 | 封顶 fd + 图标内存 | 待做(=bs6.6) |
| **M5** | `ignoredRegexps` 无界 | `Clipboard.swift:11,287-314` | `RegexpCache`(NSCache)+ `Defaults.updates(.ignoreRegexp)` 重建 | 2 | 防陈旧正则堆积 | 待做(=bs6.8) |
| **M6** | bulk 循环无 `autoreleasepool` | `History.swift:199-213,349-382,453-504` | 逐项循环包 `autoreleasepool` | 1 | 降 AppKit 瞬态峰值 + 碎片 | 待做(=bs6.14a) |
| **M7** | `withLogging` 4 次 fetchCount | `History.swift:435-450` | `dataCounts()` 包 `#if DEBUG` | 1 | 每次 clear/delete 省 4 次 DB round-trip | 待做 |
| **M8** | `updateUnpinnedShortcuts` churn | `History.swift:784-795` | `guard item.shortcuts != new` 再赋值 | 1 | 减少 @Observable 通知 churn | 待做 |
| **M9** | `ColorImage` 仅 countLimit | `ColorImage.swift:15-34` | 抽 `ColorSwatchCache` + 补 `totalCostLimit` + `lockFocus`→`drawingHandler` | 1 | 封顶色块缓存 | 待做(=bs6.9) |
| **M10** | `settingsWindowController` 常驻 | `AppState.swift:36,124-177` | `NSWindow.willCloseNotification` → 置 nil | 2 | 首开设置后释放 6 pane + 窗口 | 待做 |

> M2 是**唯一真泄漏**(非单例掩盖),核实为 18417 个 `TSMInputSource` ROOT LEAK 的**唯一来源**(全 repo 仅此一处 `TISCopy*`)。**注意**:它只 ~575KiB,**不是** 36.6MB 盲区(盲区仍需 D1)。

## 3. P1 — 核心内存生命周期 + 主线程(中 effort 高回报)

- [ ] **C1 内存脚手架(纯加法)** — 新 `Maccy/Memory/`:`VisibilityTracker`(`VisibilityObserving` 协议 + `@MainActor` 跟踪器)、`DecodedImageCache`(`NSCache<NSUUID,NSImage>` 32/64MiB;核对与 BS-3 `ThumbnailCache` 分工,不造第二套)、`MemoryGovernor`(`@MainActor`,`HistoryRef` 协议,`Reason` 枚举,`handleMemoryWarning` 清非可视区位图 + 各缓存)。(=bs6.1–6.3)
- [ ] **C2 decorator 去常驻** — `HistoryItemDecorator.swift`:加 `releaseTransientImages(_:)`(`.scrollOut` 清 preview+evict 解码、留缩略图;`.previewHidden` 清 preview;`.settingChange`/`.memoryWarning`/`.invalidate` 全清+取消任务+`textPreviewCache=nil`);`imageDataCache` 改可 nil(按需重取);`cleanupImages()`→调 `releaseTransientImages(.invalidate)`;删 `recache()`(`:211-212`,AppKit 方法、可删)与 `sizeImages()`(`:238`)。(=bs6.4)
- [ ] **C3 视图接线 + 告警挂载** — `HistoryItemView`:`.onAppear`/`.onDisappear` 对称(register/unregister `VisibilityTracker` + `onAppearInViewport`/`onDisappearFromViewport`);`PreviewItemView` popover 关闭→`releaseTransientImages(.previewHidden)`;`AppDelegate` 挂 `applicationDidReceiveMemoryWarning`→`MemoryGovernor.handleMemoryWarning()` + `attach(history:)` + `start()`;`.imageMaxHeight` 观察改 `releaseTransientImages(.settingChange)`。(=bs6.7)
- [ ] **C4 观察环 + token** — `HistoryItemDecorator.swift:367-403`:`synchronizeItemPin/Title` 的 `withObservationTracking` 包 `@ObservationIgnored private var token`,`invalidate()` 时 `token=nil` 同步取消;断 `decorator↔@Model item` 环(`invalidate` 后不再 pin 模型图,Clear 后环消失)。**不**改 `item` 为 weak(全程需要)。(=bs6.10/6.14b)
- [ ] **C5 接入 `VisibleWindowLoader`(最高 ROI 主线程削减)** — `History.load()`(`:199-213`)用后台上下文 `VisibleWindowLoader.fetchWindow` 取可视窗口 + 尾部,主线程只装饰可见项;滚动分页加载剩余;搜索时按需访问全部。冷开 O(n)→O(v)。**处理** `limitHistorySize`(按删除裁剪、部分装饰会破坏它)。

## 4. P2 — 搜索 + copy 路径(恢复 BS-5)

- [ ] **S1 搜索 actor 化** — `Search`→专用 actor(后台、**可取消**、可提前终止);主线程单 hop 发布结果(`[ItemID]`/`ItemSnapshotDTO`,复用 BS-2/4 DTO+actor+事件模式)。可选:标题 trigram/roaring-bitmap 索引(大历史);正则模式缓存 `NSRegularExpression`(别每键重编,`Search.swift:141-145`)。**第 2 大主线程瓶颈**(impact 9)。决策前跑 `TextSearchPerformanceTests`(100/500/999 项)量化。
- [ ] **S2 copy 路径 title/RTF/HTML off-main** — `ClipboardIngestor.swift:144-150,225-235` 的 `MainActor.run{ title(for:) }` 是 copy 路径**最后一处主线程阻塞**;`NSAttributedString(rtf:/html:)` 主亲和。策略:纯文本标题移出主线程;缓存 RTF/HTML 解析;或把"富文本是否空"延迟到渲染。
- [ ] **S3 `ignoredRegexps` 扫描移入 ingest actor** — `Clipboard.shouldIgnore`(`:287-314`)主线程正则扫描移入后台 ingest(M5 已做缓存,本步做离主)。

## 5. P3 — 结构性 / 未来(高 effort,延后)

- [ ] **F1 BS-8 C++ 哈希引擎** — `ClipboardByteProcessor.cpp:78-84` FNV-1a → **xxh3/wyhash**(向量化、avalanche 强);`HistoryItemContent` 增**持久化 `(size, fingerprint)` 列**(轻量迁移);`dataLikelyEqual` 双侧传指纹(移除 nil 默认参数,`HistoryItemEngine.swift:151-153`)。消除大 blob 每比重复哈希(3-5× 吞吐)。**in-memory 侧指纹缓存已做**(`ClipboardDataProcessor.fingerprintIfLarge`),只差持久化列。注意 `ClipboardByteProcessor.cpp:19,78` 补 null/empty guard(F4)。
- [ ] **F2 BS-7 Swift 6** — `pbxproj` 开 `SWIFT_STRICT_CONCURRENCY`;移除 5 处 `@unchecked Sendable`(`AppDelegate:6`、`HistoryItemDecorator:9`、`PasteboardSource:64` 等);完成 DTO/actor 边界确保 `@Model` 不跨 actor;明确 `Clipboard`/`History`/`ImageProcessor` actor 隔离。**前置**:P0/P1/P2 的 Swift-only 优化先落(减少并发错误)。
- [ ] **F3 单例掩盖 ARC 清理簇** — 全部被单例掩盖(非进程泄漏),但延寿 transient + Swift 6 前置:`Popup.eventsMonitor` self-cycle(`Popup.swift:63-66`,**与已修的 bs6.13 HotKey 无关**)、`History↔Throttler` DispatchWorkItem(`History.swift:103`+`Throttler.swift`:`[weak self]` + `cancel()` nil workItem)、`Clipboard` Timer `target:self`(`:61-67`→block-based `[weak self]`)、`AppDelegate` observer token 丢弃(`:239-247`)、`History` `Defaults.updates` Tasks 未存(`:164-196`)、`NavigationManager` 每选 Task(`:48-51`)、`PasteStack` 全局 monitor(永久 observer,非 cycle/不累积)。随 F2 一并做。
- [ ] **F4 安全/防御 trap** — `ClipboardByteProcessor.cpp` null guard;`ImageDownsampler.swift:41` `Int(maxPixelSize)` NaN/inf 守卫;`String+Shortened.swift:7` 负 `maxLength` 守卫;`SearchResult.ranges` `[Range<String.Index>]`(32B)→`NSRange`(16B);`SignatureIndex` 4-way 冗余存储收敛;`HistoryItemDecorator` Hashable/Equatable 语义核对。
- [ ] **F5 SwiftData `#Index` 宏** — `HistoryItem` 的 `pin`/`lastCopiedAt`/`firstCopiedAt`/`title` 加 `#Index`(**用 SwiftData `#Index` 宏,非 xcdatamodel GUI**——模型是 `usedWithSwiftData=YES` 的 `@Model`)。大历史下 clear/pin/sort 查询加速。需轻量迁移。
- [ ] **F6 `ThumbnailCache` 磁盘索引** — `:122-151` 每次写入全目录扫描 O(files);用 SQLite/plist 索引替代(仅写入频繁时值得,先在 perf-image shard 观察)。
- [ ] **F7 `PassthroughImageProcessor` 守护** — 当前是 `MainActorIngestorAdapter` 默认(`ClipboardIngestor.swift:82`);BS-2 wiring 时注入失败会静默回退到主线程 `NSImage(data:)` 全解码。加 assert/guard。
- [ ] **F8 杂项** — `insertDecorator` 用 `BinaryInsertion`(legacy 路径,`History.swift:426-431`);冗余 `processPendingChanges`(**仅** insert/delete/save 的可删,**predicate delete `deleteUnpinned`/`deleteAll` 前的必须保留**——见 [[swiftdata-pending-vs-saved-predicate]]);`Clipboard` 定时器 `.tolerance` + `.common` mode;`ignoredApps` `Set` 镜像 + UI 软上限。

## 6. 撤销 / 修正的分析项(核实结论,勿盲从)

- ❌ **KeyboardLayout TIS = 36.6MB 盲区?** 否。TIS 泄漏仅 ~575KiB(18417×32B)。盲区是独立 non-object,仍需 D1。(我先前 over-claim,已据核实更正。)
- ❌ **13e A1:`imageDataCacheLoaded` 非 `@ObservationIgnored`?** 错,它**是** `@ObservationIgnored`(`:93`)。
- ❌ **06 §3.1:`ForEach` 用 `@Model` 做 identity?** 否,`MultipleSelectionListView.swift:10` 用 `id: \.element.id`(UUID)。
- ⚠️ **指纹 in-memory 缓存**已做(`ClipboardDataProcessor.fingerprintIfLarge`);**只剩持久化列**(=F1/BS-8)。
- ⚠️ **SwiftData 索引**用 `#Index` 宏,**非** xcdatamodel GUI 属性(09 quick-win #14 的机制写错)。
- ⚠️ **删 `processPendingChanges`**:仅 insert/delete/save 的安全;predicate delete(`deleteUnpinned`/`deleteAll`)前的**必须保留**。
- ⚠️ `PasteStack` monitor 不累积(`guard listener==nil`)、非 self-cycle(捕获 `AppState.shared` 静态访问器),仅永久 observer。
- ⚠️ `AppDelegate` observer 闭包捕获 `names`(let),非 self,非 cycle,仅永久 observer。

## 7. 验收目标

- **稳态 `phys_footprint < 100MB`**:M1✅+M2+M3+M4+P1(C1-C4)后评估;硬达标依赖 D1(36.6MB 盲区)+ 据 D1 的定向削减。
- **主线程 `< 16ms/事件`**:C5(load O(v))+ S1(search actor)+ S2(copy off-main)+ M2/M3/M4/M5。
- **CI 全绿**(每步);UX 用户后测(非阻塞)。`G-memory` 闸门:200 条 20% 图,滚览+预览 5min,常驻 <150MiB(阶段)→ <100MiB(终态)。
- **量化阶段预期**:P0 后 ~150–170MB(已含 M1);+ P1 → ~120–150MB 且峰值显著降;+ D1 削减 → 逼近 <100MB。

## 8. 执行序

```
P0(M2→M3→M4→M5→M6→M7→M8→M9→M10,各独立小步,每步推 CI)
 ∥ D1(用户并行重抓盲区)
→ P1(C1→C2→C3→C4→C5)        # C5 接 VisibleWindowLoader 是主线程最大单项
→ P2(S1→S2→S3)              # 恢复 BS-5
→ 据 D1:P3 盲区削减 + F1(BS-8 哈希)+ F2(BS-7 Swift6,含 F3 ARC 簇)+ F4/F5/F6/F7/F8
```

每步:失败测试 → 最小实现 → 聚焦测试 → `feat/fix/perf(bs6.x 或新编号): …` 提交 → 推 CI → CI 绿即过、继续下一步。UX 门禁项(弹窗热键、预览、滚动)记在步骤注释,用户择机手测,不阻塞推进。

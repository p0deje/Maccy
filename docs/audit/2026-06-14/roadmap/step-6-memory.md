> 📌 设计意图原始档案(2026-06-14,冻结)。完成度以 docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md 为准。
> 完成: BS-6(审计 2026-06-28:部分完成 5/12 — DecodedImageCache 为死代码 setImage/image(for:) 零调用;6 测试文件缺失;G-memory gate 未建)
> **2026-07-03 补全进度(本轮)**:✅ 6.2/6.4 **删除 DecodedImageCache**(ADR-001 修订为 DELETE — 接通会增内存 vs 当前可视区限界,仅换边际 re-show,与 06-27 冲突;避免触及预览渲染路径)+ 死 `.previewHidden` 枚举 + 无操作 `evict`/`purgeAll` 调用。✅ 6.3 `handleMemoryWarning` 实际完成:非可视区 `releaseTransientImages(.memoryWarning)` + `ApplicationImageCache.purge`;thumbnail-memory 与 regexp 两 flush 目标是 `NSCache`-backed,系统内存压下自动 evict,显式 purge 冗余(记偏差)。✅ 6.4 `imageData` 已 lazy + `decodedImage` 字段已删;预览位图经 per-decorator `previewImage`(scrollOut 释放)+ BS-3 封顶,已限界于可视区。✅ 6.7 scrollOut 对称接线在(`onDisappear`→`releaseTransientImages(.scrollOut)`);`.previewHidden` 删除(零调用方)。✅ 6.11 `ApplicationImageCacheTests`(+`MemoryGovernanceTests`/`SessionLogReleaseTests` 延后:复杂 History+decorator+visibility setup)。🔄 6.12 `G-memory` gate:按 ADR-004 作 perf-as-class,或按 06-27 实测 floor(~62MB)retire(<300MiB 近平凡)— 待定。BS-6 pending CI 验证。

# BS-6 — 内存治理(NSCache、可视区/告警回收、去双份、缓存封顶)

> **依赖**:BS-3(缩略图管线 `ThumbnailCache`/`ImageProcessor` 已就位)。**编译边界**:小步骤 6.4 改 `HistoryItemDecorator` 的 `imageData`/`decodedImage` 字段会临时破坏既有视图/初始化接线,**6.7 恢复**;完成全部后 `xcodebuild build` 通过且既有测试全绿。

**目标**:把"位图/字节/图标缓存"从"进程生命周期常驻、无上限"收敛到"按需取 + 可视区+告警双路回收 + NSCache 封顶"。落地四件事:(1) `HistoryItemDecorator` 不再常驻全分辨率 `decodedImage`/`imageData` 副本,滚出可视区或 `applicationDidReceiveMemoryWarning` 时仅留(或重新按需取)缩略图;(2) `ApplicationImageCache` 无界 Dict → `NSCache(countLimit≈128)` + fd 生命周期守护;(3) 注册 `NSApplication.didReceiveMemoryWarningNotification` 清非可视区缩略图 + 解码位图 + 应用图标缓存;(4) `sessionLog` 改存 `[Int: ItemID]`,不再持有 `HistoryItem` 阻止其释放。

**依据**:`05` critical(`img-fullres-dup-storage` `img-decoded-nsimage-retained` `img-preview-fullscreen-bitmap` `all-realized-decorators`)、`05` high(`img-no-evict-on-scrollout` `appicon-cache-unbounded` `no-memwarning-handling` `sessionlog-keeps-historyitem`)、`05` medium(`regex-cache-unbounded` `textpreview-cache-per-item` `contents-array-realized` `img-sizeimages-both-bitmaps` `cleanup-recache-only` `colorimage-rebuild-per-render` `appimage-fd-leak-on-uninstall`)、`02`(`IMG-008` `IMG-011` `IMG-029`)、`07-F-018`(`open()` fd 泄漏守护)。

**编译安全性**:核心变更是 decorator 的"位图生命周期 + 数据所有权"重写——新模块(6.1–6.3)为纯加法可单独编译;6.4–6.6 改 decorator/视图接线,末尾 6.7 收敛编译。**边界**:缩略图/预览的解码、降采样、磁盘缓存实现在 **BS-3**;去重签名索引、分批 fetch、`ItemSnapshotDTO` 投影、load 优化在 **BS-4**;本步聚焦"内存治理/回收/封顶/告警",**不重写解码管线或去重算法**。

## 受影响文件

- 新:`Maccy/Memory/VisibilityTracker.swift` — 可视区跟踪协议 + `@MainActor` 协调器(驱动 decorator 的 `.onAppear/.onDisappear` → 释放/重取位图)。
- 新:`Maccy/Memory/MemoryGovernor.swift` — `@MainActor` 内存协调器:持有 `NSCache` 句柄、订阅 `didReceiveMemoryWarningNotification`、暴露 `purge(reason:)` 入口。
- 新:`Maccy/Memory/DecodedImageCache.swift` — `NSCache<NSUUID, NSImage>`(预览解码位图,key=`item.id`,带 cost);供 decorator 按需取/释放,避免在 decorator 实例字段里常驻。
- 新:`Maccy/Memory/ColorSwatchCache.swift` — `NSCache<NSString, NSImage>`(`ColorImage.from` 的 memoizer,见 6.9 / IMG-019/IMG-029)。
- 新:`Maccy/Memory/RegexpCache.swift` — `NSCache<NSString, NSRegularExpression>`(替代 `Clipboard.ignoredRegexps` 无界 Dict)。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:13-14` — `thumbnailImageSize`/`previewImageSize` 仍由 BS-3 封顶;本步确认无回退。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:44-52` — 去 `imageData`(`:50`)/`decodedImage`(`:51`);`textPreviewCache` 改 `@ObservationIgnored private var` 并在 `purge(reason:)` 时清(同 `05` `textpreview-cache-per-item`);新增 `isVisible`/`isPreviewVisible` 由 `VisibilityTracker` 驱动。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:77-87` — `init` 不再 `self.imageData = item.imageData`(`:82`);`applicationImage` 来源不变(走 `ApplicationImageCache.shared.getImage`)。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:88-119` — `ensureThumbnailImage`/`ensurePreviewImage` 在 `Task` 内取 `item.id`→`item.imageData`(按需)→调 `ImageProcessor`(BS-3);可视区切换时由 `VisibilityTracker` 重新 `ensure*`。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:131-189` — `invalidate()`/`cleanupImages()` 调 `releaseTransientImages(.invalidate)`;`image()`(`:177-189`)不再返回常驻 `NSImage`,改委托 `DecodedImageCache`/`ImageProcessor`;`sizeImages()`(`:167-175`,死代码)删除。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:218-263` — `synchronizeItemPin`/`synchronizeItemTitle` 的 `withObservationTracking` + `DispatchQueue.main.async` 递归重注册保留,但在 `isInvalidated` 后停止(避免悬挂尾递归的内存足迹)。
- 改:`Maccy/Observables/History.swift:60-61` — `sessionLog: [Int: HistoryItem]` 改 `[Int: UUID]`(ItemID);`:179,289,474` 调用点同步改。
- 改:`Maccy/Observables/History.swift:88-103` — `.imageMaxHeight` 监听里的 `item.cleanupImages()` 改走 `releaseTransientImages(.settingChange)`;新增 `MemoryGovernor.shared.attach(history:)`(启动期注入 `History`,供 `purge` 遍历非可视区 decorator)。
- 改:`Maccy/ApplicationImageCache.swift:8-23` — `cache: [String: ApplicationImage]` → `NSCache<NSString, ApplicationImage>`(`countLimit = 128`,`totalCostLimit` 见 `C`);`getImage(item:)` 返回值仍按 bundle id 取/插入,但经 `NSCache` API;新增 `func purge()`(告警时调)。
- 改:`Maccy/ApplicationImage.swift:14,42-93` — `DispatchSource` 生命周期守护(07-F-018:`open()` 后用 `defer` 兜底,`makeFileSystemObjectSource` 失败立即 `close(descriptor)`);`eventMask` 收敛为 `[.delete, .rename]`(去 `.write`,见 IMG-010);`print` → `logger`;`lastChecked`/`retryInterval`(`:9,36-40`)保留(IMG-025 不在本步范围,但守护 fd 时核对 `eventSource` 仅在 icon resolve 成功后建)。
- 改:`Maccy/ColorImage.swift:4-16` — `from(_:)` 经 `ColorSwatchCache.shared` 取;`lockFocus` → `NSImage(size:flipped:drawingHandler:)`(IMG-029)。
- 改:`Maccy/Clipboard.swift:13,282-300` — `ignoredRegexps: [String: NSRegularExpression]` → 走 `RegexpCache`;`Defaults.updates(.ignoreRegexp)` 触发 `RegexpCache.shared.rebuild()`(去 stale 项,见 `05` `regex-cache-unbounded`)。
- 改:`Maccy/AppDelegate.swift:38-101` — `applicationDidReceiveMemoryWarning(_:)` override(或 `applicationDidReceiveMemoryWarningNotification` 注册)→ `MemoryGovernor.shared.handleMemoryWarning()`;`applicationDidFinishLaunching` 注入 `MemoryGovernor.shared.attach(history: History.shared)` 与 `ApplicationImageCache`/`ThumbnailCache`。
- 改:`Maccy/Views/HistoryItemView.swift:49-51` — `.onAppear { item.ensureThumbnailImage() }` 增 `.onDisappear { item.releaseTransientImages(.scrollOut) }`(对称,见 `05` recommendation 5);`accessoryImage`(line 40)经 `ColorSwatchCache`(6.9)。
- 改:`Maccy/Views/PreviewItemView.swift` — 关闭预览 popover 时触发 `item.releaseTransientImages(.previewHidden)`(释放预览位图,见 IMG-008 recommendation 4)。

## 小步骤

- [ ] **6.1 可视区跟踪协议** — `VisibilityTracker.swift`。定义"谁负责上报可视性变化":
  ```swift
  protocol VisibilityObserving: AnyObject {
    var id: UUID { get }
    func onAppearInViewport()
    func onDisappearFromViewport()
  }
  @MainActor
  final class VisibilityTracker {
    private var visible: Set<UUID> = []
    func register(_ o: VisibilityObserving)        // .onAppear 调
    func unregister(_ o: VisibilityObserving)      // .onDisappear 调
    func isVisible(_ id: UUID) -> Bool
    func snapshot() -> Set<UUID>                   // 供 MemoryGovernor purge 遍历"非可视区"
  }
  ```
  `HistoryItemDecorator` 实现 `VisibilityObserving`:`onAppearInViewport` → `ensureThumbnailImage()`;`onDisappearFromViewport` → `releaseTransientImages(.scrollOut)`(只清预览位图与解码位图,缩略图走 `NSCache` 由 cost 淘汰,见 6.4)。**纯加法,可单独编译**。

- [ ] **6.2 `DecodedImageCache`(NSCache)** — `DecodedImageCache.swift`。
  ```swift
  final class DecodedImageCache: @unchecked Sendable {   // NSCache 自身线程安全
    static let shared = DecodedImageCache()
    private let cache: NSCache<NSUUID, NSImage> = {
      let c = NSCache<NSUUID, NSImage>()
      c.countLimit = 32            // C:解码位图最大驻留 32 项(预览瞬时性)
      c.totalCostLimit = 64 * 1024 * 1024   // 64 MiB 上限
      return c
    }()
    func image(for id: UUID) -> NSImage?
    func setImage(_ image: NSImage, for id: UUID, cost: Int)   // cost = W*H*4
    func evict(_ id: UUID)
    func purgeAll()               // 告警时
  }
  ```
  `countLimit=32` 与 `totalCostLimit=64MiB` 取值依据 `C §4` 单项最大驻留(预览 ≤1600² → ≤10MiB backing;32×2MiB ≈ 64MiB 量级;实测校准)。**纯加法**。

- [ ] **6.3 `MemoryGovernor`(@MainActor 协调器)** — `MemoryGovernor.swift`。
  ```swift
  @MainActor
  final class MemoryGovernor {
    static let shared = MemoryGovernor()
    private weak var history: HistoryRef?          // 弱引用 History,避免循环
    private var observer: NSObjectProtocol?
    enum Reason { case scrollOut, previewHidden, settingChange, memoryWarning, invalidate }
    func attach(history: History)                  // AppDelegate 启动期注入
    func start()                                   // 注册 NSApplication.didReceiveMemoryWarningNotification
    func stop()
    func handleMemoryWarning() {
      // 1) 非可视区 decorator: releaseTransientImages(.memoryWarning)
      // 2) DecodedImageCache.shared.purgeAll()
      // 3) ApplicationImageCache.shared.purge()
      // 4) RegexpCache.shared.purgeStale()
      // 5) ThumbnailCache 内存层 removeAllObjects()(磁盘保留,BS-3 提供 API)
    }
  }
  ```
  **纯加法**;`History` 解耦通过新增轻量 `protocol HistoryRef: AnyObject { func decorators() -> [HistoryItemDecorator] }`,`History` 一致性在 6.5 加。

- [ ] **6.4 [breaks compile until 6.7] decorator 去双份 + 解码位图走 NSCache** — `HistoryItemDecorator.swift:44-52,77-189`。
  - 删 `private let imageData: Data?`(`:50`)与 `private var decodedImage: NSImage?`(`:51`);`init` 不再 `self.imageData = item.imageData`(`:82`)。**`img-fullres-dup-storage` 关闭**——按需从 `item.imageData` 取(主上下文已缓存;若需跨线程,在 `Task` 内拷一份 `Data` 传给 `ImageProcessor`,任务结束自动释放,见 `05` recommendation)。
  - `image()`(`:177-189`)不再返回常驻 `NSImage`;调用方(`generatePreviewImage`/`generateThumbnailImage`)在 BS-3 已改走 `ImageProcessor`。本步把残留的 `image()`/`decodedImage` 路径彻底删掉,**`img-decoded-nsimage-retained` 关闭**——预览解码位图进 `DecodedImageCache`(6.2),按 `item.id` 取/淘汰。
  - 新增 `func releaseTransientImages(_ reason: MemoryGovernor.Reason)`:`thumbnailImage`/`previewImage` 按 reason 决策——`.scrollOut` 仅清 `previewImage` + `DecodedImageCache.evict(id)`(缩略图留,因列表滚动会快速复现);`.previewHidden` 清 `previewImage`;`.settingChange`/`.memoryWarning`/`.invalidate` 全清 + 取消任务 + `textPreviewCache = nil`。对应 `05` `img-no-evict-on-scrollout` `cleanup-recache-only`。
  - `cleanupImages()`(`:137-147`)改为内部调 `releaseTransientImages(.invalidate)`;删 `recache()` 调用(IMG-037:在 BS-3 之后无 `decodedImage` 可 recache,本步收尾)。
  - `sizeImages()`(`:167-175`,死代码,`05` `img-sizeimages-both-bitmaps`)删除。

- [ ] **6.5 `History` 实现 `HistoryRef` + 接入 `MemoryGovernor`(`sessionLog` 迁移归属 BS-4 4.6)** — `AppDelegate.swift`。
  - **`sessionLog` 改 `[Int: UUID]` 在 BS-4 4.6 已落地**(两步皆依赖 BS-2 主干,推荐执行序 BS-4 在 BS-6 前,故通常已完成)。本步默认仅**核对**:`sessionLog: [Int: UUID]`(`:60-61`)生效、`add/delete`(`:179,289`)与 `isModified`(`:472-478`)的 id 反查正确、`05 sessionlog-keeps-historyitem` 已关闭。**仅当先执行 BS-6(跳过 BS-4)时**,才在此完成 `[Int:HistoryItem]`→`[Int:UUID]` 改造。本步**不重复迁移**,消除原 6.5 与 BS-4 4.6 的重复声明。
  - `extension History: HistoryRef { func decorators() -> [HistoryItemDecorator] { all } }`;`applicationDidFinishLaunching` 注入 `MemoryGovernor.shared.attach(history: History.shared)` + `MemoryGovernor.shared.start()`。

- [ ] **6.6 `ApplicationImageCache` → NSCache + fd 守护** — `ApplicationImageCache.swift:8-23`;`ApplicationImage.swift:14,42-93`。
  - `private let cache: NSCache<NSString, ApplicationImage>`(`countLimit = 128`,`totalCostLimit` 见 C;`getImage(item:)` 走 `cache.object(forKey:)` / `cache.setObject(_:forKey:cost:)`,cost 取固定 1 或按 icon 估算)。新增 `func purge()` → `cache.removeAllObjects()`。**`appicon-cache-unbounded` 关闭**——`ApplicationImage.deinit` 已 cancel `DispatchSource`(`ApplicationImage.swift:21-23`,审计确认为正确),`NSCache` 淘汰时 deinit 即触发 fd 释放。
  - **fd 守护(07-F-018)**:`ApplicationImage.swift:48-60` 在 `let descriptor = open(...)` 之后、`makeFileSystemObjectSource` 之前加 `defer {  }` 的等价护栏——具体为把 `source` 创建包进 `do/catch` 风格的失败路径:`guard let source = try? makeFileSystemObjectSourceSafe()` else { close(descriptor); return img }`(`DispatchSource.makeFileSystemObjectSource` 当前不抛错,故本步以"显式 `defer { if sourceCreated == false { close(descriptor) } }`"守护未来重构);`eventMask: [.delete, .rename]`(去 `.write`,IMG-010);`print` → `logger`(IMG-026/027)。

- [ ] **6.7 [restores compile] 接线 + 视图 onDisappear + 告警挂载** — `AppDelegate.swift`;`HistoryItemView.swift:49-51`;`PreviewItemView.swift`。
  - `AppDelegate.applicationDidFinishLaunching`(或 `applicationWillFinishLaunching`)末尾:`MemoryGovernor.shared.attach(history: History.shared)`;`MemoryGovernor.shared.start()`(注册 `NSApplication.didReceiveMemoryWarningNotification`,selector 跳 `handleMemoryWarning`)。
  - `HistoryItemView.swift:49-51`:`.onAppear { VisibilityTracker.shared.register(item); item.onAppearInViewport() }` + `.onDisappear { item.onDisappearFromViewport(); VisibilityTracker.shared.unregister(item) }`(对称回收,`05` recommendation 5)。`accessoryImage`(line 40)走 `ColorSwatchCache`(6.9)。
  - `PreviewItemView`:popover 关闭回调里 `item.releaseTransientImages(.previewHidden)`(预览只展示单项,切换即释放,IMG-008 recommendation 4)。
  - 至此所有 decorator 调用点经新路径,编译恢复。

- [ ] **6.8 `RegexpCache` + 重建** — `RegexpCache.swift`;`Clipboard.swift:13,282-300`。
  - `final class RegexpCache { static let shared = RegexpCache(); private let cache: NSCache<NSString, NSRegularExpression>; func regex(for pattern: String) -> NSRegularExpression?; func rebuild(from patterns: [String]); func purgeStale() }`。
  - `Clipboard.ignoredRegexps`(`:13`)删除;`shouldIgnore`(`:282-300`)改 `RegexpCache.shared.regex(for: regexp)`。
  - `Clipboard.start()`(或 `AppDelegate`)新增 `Task { for await _ in Defaults.updates(.ignoreRegexp, initial: true) { RegexpCache.shared.rebuild(from: Defaults[.ignoreRegexp]) } }`——移除 stale 项(`05` `regex-cache-unbounded`)。

- [ ] **6.9 `ColorSwatchCache`** — `ColorSwatchCache.swift`;`ColorImage.swift:4-16`。
  - `final class ColorSwatchCache { static let shared = ColorSwatchCache(); private let cache: NSCache<NSString, NSImage>; func swatch(for hex: String) -> NSImage? }`(内部 `NSImage(size:flipped:drawingHandler:)` 替代 `lockFocus`,IMG-029)。
  - `ColorImage.from(_:)` 改一行 `return ColorSwatchCache.shared.swatch(for: colorHex)`。**`colorimage-rebuild-per-render` 关闭**。

- [ ] **6.10 `withObservationTracking` 重注册足迹收敛(minor)** — `HistoryItemDecorator.swift:218-263`。
  - `synchronizeItemPin`(`:227-245`)/`synchronizeItemTitle`(`:247-263`)已 `[weak self]` 且 `isInvalidated` 守卫(审计确认无环);本步补:`invalidate()` 里设 `isInvalidated = true` 后,**同步**取消尾挂的 `DispatchQueue.main.async` 重注册(用 `isInvalidated` 已能短路,但确认 `onChange` 闭包不被 SwiftUI 缓存为长生命周期对象——必要时把 `withObservationTracking` 包进 `@ObservationIgnored private var token`,`invalidate` 时 `token = nil`)。**minor**:审计已认定无泄漏,此步主要是为 BS-7 strict concurrency 时的隔离确定性。

- [ ] **6.11 测试** — 见下节"测试"。`MaccyTests/MemoryGovernanceTests.swift`、`DecodedImageCacheTests`、`ApplicationImageCacheTests`、`RegexpCacheTests`、`ColorSwatchCacheTests`、`SessionLogReleaseTests`。

- [ ] **6.12 验证** — `xcodebuild build` + `xcodebuild test` 通过;手动:历史 200 条 20% 图片,滚动浏览 5min,常驻 RSS 对比改前明显下降(量化留 `G-memory`);触发系统内存告警(或测试桩注入 `NSApplication.didReceiveMemoryWarningNotification`)→ 非可视区缩略图/解码位图清空,RSS 回落。

## 测试

- 引用:`B-test-strategy.md §2`(`FixtureLoader` 合成图片、`HistoryBuilder`、`MainThreadProbe`)、`§4`(`G-memory`)。
- 新增:
  - `MemoryGovernanceTests`:
    - `releaseTransientImages_scrollOut_keepsThumbnail_evictsPreview`(对应 `img-no-evict-on-scrollout`)。
    - `releaseTransientImages_memoryWarning_clearsNonVisibleDecoded`(注入 `MemoryGovernor.handleMemoryWarning`,断言非可视区 decorator 的 `previewImage == nil` 且 `DecodedImageCache` 空)。
    - `onAppear_rearmsThumbnail_afterScrollOut`(对称回收后再出现能重建)。
  - `DecodedImageCacheTests`:`countLimit`/`totalCostLimit` 淘汰行为(插入 >32 项或 cost 超 64MiB 触发淘汰);`evict`/`purgeAll`。
  - `ApplicationImageCacheTests`:`countLimit = 128` 淘汰;`purge()` 清空且 `ApplicationImage.deinit` 取消 `DispatchSource`(用 spy 计数 `eventSource?.cancel()`);**fd 守护**(07-F-018):注入一个总是失败的 `makeFileSystemObjectSource` 测试桩,断言 `descriptor` 被 `close`(用 `MockFileHandle` 或在测试 build 下注入 `open` 桩)。
  - `RegexpCacheTests`:从 `Defaults[.ignoreRegexp]` 重建后 stale 项消失;命中/未命中。
  - `ColorSwatchCacheTests`:同 hex 返回同一实例;不同 hex 不同实例。
  - `SessionLogReleaseTests`:`sessionLog` 存 `UUID`;`HistoryItem` 被 delete 后 `sessionLog` 不再引用其 id(`05` `sessionlog-keeps-historyitem`);`History.add` 后 `isModified` 仍能命中 modified。
- 闸门:`G-memory`(`B §4`):浏览 + 预览 5min,常驻 < 300MiB(从 ~GB 级降)。以独立 `MaccyPerformanceTests` target 运行,改性能 PR 须绿。

## 验收标准

- **功能**:复制/预览/缩略图/去重行为与改前一致(用户可见);滚动离开可视区后再回来能重建缩略图;预览 popover 关闭后预览位图释放;系统内存告警触发后非可视区位图 + 解码缓存 + 应用图标缓存清空,App 不崩溃、列表仍可交互。
- **复杂度(内存前→后估算,参考 `05` worst-case)**:
  - 配置:`size=999`、20% 图片(200 项)、avg 源图 3MiB、retina、用户滚过全部 + 预览 25%。
  - **改前**(`05` §"Worst-case Analysis"):imageData 副本 200×3MiB = 600MiB;`decodedImage` 200×49MiB = **9.6GiB**;`previewImage` 50×55MiB = **2.6GiB**;文本项 ~20MiB;`ApplicationImageCache` ~10MiB;**合计 ~12.8GiB**。
  - **改后**:
    - `imageData` 副本:**0**(按需从 `item.imageData` 取,任务结束释放)→ 省 600MiB。
    - `decodedImage`:**0**(字段删除);预览解码走 `DecodedImageCache`(countLimit=32 / totalCostLimit=64MiB)→ 上限 **64MiB**。
    - `previewImage`:可视区 + `previewHidden` 回收,稳态 ≤可视图片数(假设可视 ~10 项 × BS-3 封顶后 ≤1600²≈10MiB)= **~100MiB**(滚动后非可视清)。
    - 缩略图(BS-3 已封顶):NSCache + 磁盘;内存层 ~可视数 ×54KiB ≈ 可忽略;磁盘 LRU ≤256MiB(BS-3)。
    - `ApplicationImageCache`:NSCache countLimit=128 × ~200KiB ≈ **~25MiB**(原无界,理论上限更高)。
    - 文本项 / `textPreviewCache`:`.memoryWarning` 时清非可视区 → 稳态 ≤可视数 ×25KiB ≈ 可忽略。
    - `sessionLog`:`[Int: UUID]` → 5000 粘贴 ×16B ≈ **80KiB**(原持 `HistoryItem` 引用,虽增量小但阻止 faulting)。
    - **合计稳态 < 300MiB**(满足 `C §4` 目标);**重度浏览告警可回收**(`MemoryGovernor.handleMemoryWarning` 后 `< 100MiB` 量级)。
  - 量级降幅:**~12.8GiB → < 300MiB**(主要来自去 `decodedImage` + 预览封顶 + 可视区/告警回收)。
- **管线(`C §3`)**:不引入新端到端时延;反而滚动流畅度提升(非可视区位图不参与驻留集,减少 Jetsam 压力下的 swap)。`G-memory` 通过。
- **I/O 限制(`C §2`)**:`DecodedImageCache.countLimit=32 / totalCostLimit=64MiB`;`ApplicationImageCache.countLimit=128`;缩略图磁盘 LRU ≤256MiB(BS-3);`sessionLog` 不持模型引用;fd:每 `ApplicationImage` 仅一个 `open(O_EVTONLY)`,被 `NSCache` 淘汰时 `deinit` 关闭,有 07-F-018 守护。
- **不变性(`A §7`)**:"主线程无重活"维持(BS-3 后位图经 `ImageProcessor`);"跨 actor 载荷 Sendable"维持(`MemoryGovernor`/`DecodedImageCache` 走 `@MainActor` 或 `NSCache` 线程安全);`@unchecked Sendable` 风险随 `decodedImage`/`imageData` 字段移除进一步下降(彻底摘除留 BS-7)。

## Commit
`perf(memory): NSCache for decoded/app-icon/regex/color caches, viewport+warning eviction, drop full-res image duplicate, sessionLog by id`

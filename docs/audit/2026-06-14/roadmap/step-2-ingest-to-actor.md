> 📌 设计意图原始档案(2026-06-14,冻结)。完成度以 docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md 为准。
> 完成: BS-2(审计 2026-06-28:已完成)

# BS-2 — 摄取管线迁入 actor

> **依赖**:BS-1。**编译边界**:小步骤 2.4 起会临时破坏编译(`onNewCopyHooks` 拆除),**2.5 恢复**;完成全部后可编译且测试通过。

**目标**:把"复制→入库"整条同步主线程管线搬进后台 actor,主线程只接收 `StoreEvent` 做增量 UI 更新;写入收敛为**单事务**。**行为与现状一致**(复杂度优化留给 BS-4)。
**依据**:`01`(pasteboard-polling-callback-heavy)、`04`(no-background-modelcontext、add-multi-processpending-save-per-copy)、`03-LT-MAIN-01`。
**编译安全性**:核心变更是 `Clipboard` 与 `History` 的接线方式;末尾所有调用点统一经 actor/事件流,恢复编译。

## 受影响文件
- 新:`Maccy/Ingest/PasteboardSource.swift` — 抽象 `NSPasteboard` 读取(可注入测试)。
- 新:`Maccy/Ingest/ClipboardIngestor.swift` — 真实 actor 实现(BS-1 已定义协议,本步填实现)。
- 改:`Maccy/Observables/History.swift` — 新增 `consume(_ event:)`,内部化 `add()` 为事件处理;移除每复制全量重排依赖(留待 BS-4 优化)。
- 改:`Maccy/Clipboard.swift:55-215` — `checkForChangesInPasteboard` 瘦化为"探测+派发";移除 `onNewCopyHooks`(`:8,12,47-53`)与同步摄取;`start()` Timer 保留但仅触发后台 `Task`。
- 改:`Maccy/AppDelegate.swift`(构造 ingestor,移除旧 hook 注册)。

## 小步骤

- [x] **2.1 PasteboardSource 抽象** — `PasteboardSource.swift`。`protocol PasteboardSource: Sendable { var changeCount: Int { get}; func snapshot() -> [PasteboardItemSnapshot] }`;`PasteboardItemSnapshot { types: Set<PasteboardType>, data: (PasteboardType) -> Data? }`。`NSPasteboardSource` 包真 `NSPasteboard`;测试用 `PasteboardSimulator`。
  - 证据:提交 `334cb70`;macOS 26 ARM CI run `27498442988`(分支 `master`、`push`)通过 SwiftLint、clean build、`MaccyTests`、`MaccyUITests`、日志扫描。
  - 偏离记录(相对路线图字面文本):(1) `Dtos.swift` 在 BS-1 已有 `struct PasteboardSource`(origin 元数据:`changeCount`+`name`),与本步协议同名冲突 → 重命名为 `CopyOrigin`(`ClipboardItemDTO.source`、`IngestRequest.source` 及 7 处调用点),协议保留 `PasteboardSource` 名称;(2) `PasteboardItemSnapshot` 在 BS-1.6 已存在于测试模块,本步迁入主模块 `Maccy/Ingest/PasteboardSource.swift` 以便生产协议引用,沿用其 eager/Sendable 设计(`contents: [String: Data]`、**不过滤/不限长**——过滤与 `maxValueSize` 留给 ingestor,BS-2.2);(3) `NSPasteboardSource` 标注 `@unchecked Sendable`(`NSPasteboard` 非 Sendable,仅经只读 API 访问);(4) `project.pbxproj` 用显式文件引用,新增文件需在 PBXBuildFile/PBXFileReference/Ingest group/Sources phase 四处登记。
- [x] **2.2 actor ClipboardIngestor 实现** — `ClipboardIngestor.swift`。
  - `init(bg: ModelContext, image: ImageProcessing, now: @escaping @Sendable () -> Date, onEvent: @escaping @Sendable (StoreEvent) async -> Void)`(`now` 注入便于测试,不在库内用 `Date.now`)。
  - `func ingest(_ req: IngestRequest) async -> IngestResult`:内部分两段——
    - `materialize(req) -> IngestPlan`(纯函数,见 `B §3`):类型过滤(`filteredTypes` 等价)、忽略规则(`shouldIgnore`)、富文本/HTML 解析(后台)、去重**沿用现有 fetch-all 比对**(行为不变,只是搬后台)、决定 `.create/.merge/.ignore`。
    - `commit(plan)`:在 **`bg.transaction { }` 单事务**内完成 insert + dup-delete + size-trim,**一次 save**;构建 `ItemSnapshotDTO` 与 `StoreEvent`;`await onEvent(event)`。
  - `metrics.bytesHashed/parseMs/dedupHits` 记入 `IngestResult`。
  - **拆分记录**:本步拆为 2.2a + 2.2b 以降低单步风险、提高可测性。**2.2a(已完成)**:把过滤/忽略规则抽成纯函数 `filterContents`(`Maccy/Ingest/IngestFilter.swift`,+ `IngestConfig` 注入配置);去重因依赖 `@Model`/`HistoryItemEngine`(`[HistoryItemContent]`)而留在 actor 侧(2.2b),偏离"materialize 含去重"的字面文本。证据:CI run `27499729026`(master、push)通过 SwiftLint/clean build/`MaccyTests`/`MaccyUITests`/日志扫描。两处审查修复:`filteredTypeSet` 改用 `subtracting(supportedTypes - enabledTypes)` 以保留自定义/非 supported 类型(与 `Clipboard.filteredTypes` 逐字节等价,原 `intersection(supported ∩ enabled)` 会误删);`IngestConfig` 字段改 `var` 以支持测试按字段覆写。**2.2b(已完成)**:actor `BackgroundClipboardIngestor`(`ClipboardIngestor.swift`,保留既有 protocol + `MainActorIngestorAdapter`)+ 单事务 commit(`makeHistoryItem`/`findDuplicate`/`mergeFields`/`commit`)+ `StoreEvent`。证据:CI run `27501895719`(master、push、attempt 2)通过 SwiftLint/clean build/`MaccyTests`/`MaccyUITests`/日志扫描。本地无编译环境,以下问题经 CI 逐轮暴露并修复:SwiftLint `function_body_length`/`identifier_name`(拆 `ingest` 为四个 helper + `bg`→`backgroundContext`)、`IngestConfig` memberwise-init 参数顺序、测试缺 `import Defaults`、测试 `Storage.shared` 跨用例隔离(setUp 清空)+ Swift 6 captured-var 警告(锁化 `EventCollector`)。首 attempt 因 runner 解析 `XCUIAutomation.framework` 的无关 Mach-O 告警被日志扫描误判,re-run 通过(代码本身首 attempt 已全绿,仅扫描步骤误报)。
- [x] **2.3 History 事件消费** — `History.swift`。
  - `@MainActor func consume(_ event: StoreEvent)`:依 `event` 增量更新 `all`/`items`(本步沿用现有插入位置逻辑,BS-4 改 O(log n));`added`→装饰新项并插入;`merged`→更新计数/时间并位移;`removed/cleared`→清理。
  - 保留 `add(_:)` 供 `MainActorIngestorAdapter`(BS-1)与既有测试过渡;新路径走 `consume`。
  - 证据:CI run `27503170506`(master、push)通过 SwiftLint/clean build/`MaccyTests`/`MaccyUITests`/日志扫描。实现:`consume` 四个 case 均委托 `reconcileWithStore`(从 mainContext 重取 → 按 `persistentModelID` 复用既有 decorator 保护已解码位图 → 新增/变更项重新装饰 → 对被移除/合并掉的 decorator 调 `cleanup` 释放位图 → `refreshVisibleItems`)。`Storage.newBackgroundContext()` 文档说明 SwiftData 跨 context 可见性(同 container 的 context 共享持久存储,fetch 可见对方已提交 save);初版误加的 `automaticallyMergesChangesFromParent = true`(`ModelContext` 无此 API)已移除。残留运行时不确定:bg save → mainContext.fetch 的可见性靠 SwiftData 共享存储语义,需 2.5 接线后由 UI 测试验证。
- [x] **2.4 [breaks compile] 拆除同步 hook** — `Clipboard.swift`。删除 `onNewCopyHooks`/`onNewCopy`/`clearHooks`(`:8,12,47-53`)与 `checkForChangesInPasteboard` 内的 `onNewCopyHooks.forEach`(`:214`)。`checkForChangesInPasteboard` 改为:`guard changeCount 变化` → 构建 `IngestRequest`(从 `PasteboardSource.snapshot()`)→ `Task { await ingestor.ingest(req) }`。
  - 证据:提交 `341bca2`(`fix(bs2.4): stabilize UI ingest handoff`)+ 先前接线;CI run `27517644893`(master、push)全绿(SwiftLint/clean build/`MaccyTests`/`MaccyUITests`/日志扫描)。实际末段为 `guard let ingestor else { return }; Task { await ingestor.ingest(request) }`(捕获 Sendable `ingestor`,不再经可选链捕获非 Sendable `self`);Notifier 的 `Task` 标 `@MainActor`。根因与教训见 `docs/audit/architecture-and-root-causes.md` §3(数据安全)。
- [x] **2.5 [restores compile] AppDelegate 接线** — `AppDelegate.swift`。构造 `ClipboardIngestor`(注入 `Storage.newBackgroundContext()`、`PassthroughImageProcessor`、`now: { Date() }`、`onEvent: { @MainActor ev in History.shared.consume(ev) }`);注入到 `Clipboard`;移除旧 `onNewCopy` 注册。此时编译恢复。
  - 证据:提交 `341bca2`/`66344e6`;`AppDelegate` 在 `Clipboard.shared.start()` 之前构造 `BackgroundClipboardIngestor(modelContainer: Storage.shared.container, image: PassthroughImageProcessor(), now: { Date() }, onEvent: { @MainActor in History.shared.consume($0) })`。GPT-5.5 另把 5 个 `UITestNotification` 观察者由 `Task { @MainActor in … }` 改为 `MainActor.assumeIsolated { … }`(已在 `queue:.main`,同步内联执行,消除多一跳 runloop 延迟——UI 测试"发通知后立即断言"不再超时)。同批修复还包括 `History.togglePin` 落盘(`d416e7e`)、`reconcileWithStore` 对齐 selection(`66344e6`)——根因与教训见 `docs/audit/architecture-and-root-causes.md` §3(数据安全)。CI `27517644893` 全绿。
- [x] **2.6 测试** — `BackgroundClipboardIngestorTests`(契约 + 单事务原子性 + 主线程纯净性)。
  - 证据:提交 `db0b066`(`test(bs2.6): close ClipboardIngestor test gaps`)+ `46bca23`(fix:移除多余 `type_body_length` disable——SwiftLint `--strict` 把"未触发的 disable"当硬错);CI run `27521644300`(master、push)全绿。新增两枚 characterization 测试:`testIngestKeepsMainThreadFreeUnderLoad`(`MainThreadProbe` + 预置 300 行 + `heavy_text.txt` 31 KB 纯文本 → `maxGap < 0.1`,证明摄取的持久化工作离线主线程——核心 BS-2 承诺);`testCommitPreservesDistinctItemsAndCountsDuplicateOnMerge`(size=2,复制**较新**项 → 计数 2 / 较旧的不同项存活 / `numberOfCopies==2`——单事务原子性的最强可行行为代理,`commit` 的"trim 计数前先剔除 dup"不变式由此变为可观测)。契约测试(added/merged/maxValueSize/ignoreRegexp/trim/metrics/跨 context 可见性/离线 RTF 回归)在 2.2b/2.3 已落;`ClipboardTests`/`HistoryTests` 的 async 适配在 2.4 已完成(GPT-5.5)。
  - 偏离记录:(1) `B §2` 的 `ContextSpy`(断言单次 save)未创建——经 sosumi 核实 `ModelContext` 非 `final`(`class ModelContext`)且 SwiftData 有 `ModelContext.didSave`,但 `@ModelActor` 在 actor 内部构造私有 context、无注入点,而 `didSave` 由该不暴露的实例发出;加生产侧 save-spy seam 属反模式,故改用行为代理(精确理由见 `BackgroundClipboardIngestorTests` 文件头注释)。(2) `B §4` 的严格 `<16ms` `G-copy-text` 闸门延期——需尚未创建的 `MaccyPerformanceTests` 独立 target;本步在 `MaccyTests` 内加了一枚粗粒度 `<100ms` `MainThreadProbe` 回归守卫(注释已声明非严格闸门)。
- [x] **2.7 验证** — CI build + test 全绿;行为与改前一致。**BS-2 完整落地。**
  - 证据:CI run `27521644300`(master、push、head `46bca23`)全绿——SwiftLint `--strict --no-cache`、`xcodebuild` clean build、`MaccyTests`、`MaccyUITests`、日志扫描(`warning:`/`error:`/`TEST FAILED` 均无命中)。行为一致性由 `MaccyUITests` 套件全绿作证(覆盖复制文本/RTF/图片/重复合并/清空/pin 等流程),即复制文本/图片/重复/超大/裁剪行为与改动前一致。`bytesHashed` 本步仍非 0(指纹持久化在 BS-8)。

## 测试
- 引用:`B §2`(`PasteboardSimulator`、`IngestorSpy`、`MainThreadProbe`)、`§3`(数据流抽象)、`§4`(`G-copy-text`)。
- 新增:`ClipboardIngestorTests`(契约 + 单 save + 主线程纯净性)。
- 闸门:`G-copy-text`(主线程 <16ms;`bytesHashed` 本步仍非 0,BS-8 后趋 0)。

## 验收标准
- 功能:复制/去重/容量裁剪行为与改前一致;单事务(单 save);解析/去重不在 main。
- 复杂度:**不变**(仍 fetch-all 比对 + 整表插入;优化在 BS-4),但**移出主线程**。
- 管线:摄取 main→background;`StoreEvent` 单向回主线程增量更新。
- I/O 限制:沿用既有(blob/正则/富文本上限);`now` 注入避免库内系统时钟。
- 不变性:`A §7` 的"写入经后台 context 单事务""跨 actor 载荷 Sendable""主线程无重活"在本步达成(算法级优化除外)。

## Commit
`refactor(ingest): move pasteboard ingest to background actor, single-transaction writes, event-driven UI updates`

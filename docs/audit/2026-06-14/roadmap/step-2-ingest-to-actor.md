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
- [ ] **2.2 actor ClipboardIngestor 实现** — `ClipboardIngestor.swift`。
  - `init(bg: ModelContext, image: ImageProcessing, now: @escaping @Sendable () -> Date, onEvent: @escaping @Sendable (StoreEvent) async -> Void)`(`now` 注入便于测试,不在库内用 `Date.now`)。
  - `func ingest(_ req: IngestRequest) async -> IngestResult`:内部分两段——
    - `materialize(req) -> IngestPlan`(纯函数,见 `B §3`):类型过滤(`filteredTypes` 等价)、忽略规则(`shouldIgnore`)、富文本/HTML 解析(后台)、去重**沿用现有 fetch-all 比对**(行为不变,只是搬后台)、决定 `.create/.merge/.ignore`。
    - `commit(plan)`:在 **`bg.transaction { }` 单事务**内完成 insert + dup-delete + size-trim,**一次 save**;构建 `ItemSnapshotDTO` 与 `StoreEvent`;`await onEvent(event)`。
  - `metrics.bytesHashed/parseMs/dedupHits` 记入 `IngestResult`。
  - **拆分记录**:本步拆为 2.2a + 2.2b 以降低单步风险、提高可测性。**2.2a(已完成)**:把过滤/忽略规则抽成纯函数 `filterContents`(`Maccy/Ingest/IngestFilter.swift`,+ `IngestConfig` 注入配置);去重因依赖 `@Model`/`HistoryItemEngine`(`[HistoryItemContent]`)而留在 actor 侧(2.2b),偏离"materialize 含去重"的字面文本。证据:CI run `27499729026`(master、push)通过 SwiftLint/clean build/`MaccyTests`/`MaccyUITests`/日志扫描。两处审查修复:`filteredTypeSet` 改用 `subtracting(supportedTypes - enabledTypes)` 以保留自定义/非 supported 类型(与 `Clipboard.filteredTypes` 逐字节等价,原 `intersection(supported ∩ enabled)` 会误删);`IngestConfig` 字段改 `var` 以支持测试按字段覆写。**2.2b(待做)**:actor 本体 + 单事务 commit + `StoreEvent`。
- [ ] **2.3 History 事件消费** — `History.swift`。
  - `@MainActor func consume(_ event: StoreEvent)`:依 `event` 增量更新 `all`/`items`(本步沿用现有插入位置逻辑,BS-4 改 O(log n));`added`→装饰新项并插入;`merged`→更新计数/时间并位移;`removed/cleared`→清理。
  - 保留 `add(_:)` 供 `MainActorIngestorAdapter`(BS-1)与既有测试过渡;新路径走 `consume`。
- [ ] **2.4 [breaks compile] 拆除同步 hook** — `Clipboard.swift`。删除 `onNewCopyHooks`/`onNewCopy`/`clearHooks`(`:8,12,47-53`)与 `checkForChangesInPasteboard` 内的 `onNewCopyHooks.forEach`(`:214`)。`checkForChangesInPasteboard` 改为:`guard changeCount 变化` → 构建 `IngestRequest`(从 `PasteboardSource.snapshot()`)→ `Task { await ingestor.ingest(req) }`。
- [ ] **2.5 [restores compile] AppDelegate 接线** — `AppDelegate.swift`。构造 `ClipboardIngestor`(注入 `Storage.newBackgroundContext()`、`PassthroughImageProcessor`、`now: { Date() }`、`onEvent: { @MainActor ev in History.shared.consume(ev) }`);注入到 `Clipboard`;移除旧 `onNewCopy` 注册。此时编译恢复。
- [ ] **2.6 测试** — `ClipboardIngestorTests`:`PasteboardSimulator` 注入 → 断言 `StoreEvent.added`;重复内容→`merged`;超 `maxValueSize`→该 blob 丢弃不崩;`ContextSpy` 断言**单次 save**;`MainThreadProbe` 断言 ingest 期间主线程无 >16ms 占用。适配既有 `ClipboardTests`/`HistoryTests` 为 async。
- [ ] **2.7 验证** — `xcodebuild build` + test 通过;行为对照表(复制文本/图片/重复/超大)与改动前一致。

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

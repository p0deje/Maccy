> 📌 设计意图原始档案(2026-06-14,冻结)。完成度以 docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md 为准。
> 完成: BS-4(审计 2026-06-28:部分完成 — 4.4a/4.2/4.5/4.7 落地;4.3/4.6/4.8 延后;VisibleWindowLoader 仍为死代码)

# BS-4 — 数据管线加速

> **依赖**:BS-2(ingestor/事件流/单事务已就绪)。**编译边界**:小步骤 4.2(签名索引替去重)、4.3(`load` 新签名)、4.6(`sessionLog` 类型变更)各自会临时破坏既有调用点,**末尾全部恢复**;完成全部小步骤后可编译且既有测试全绿。

**目标**:把"冷开加载""复制去重""复制插入"三条主线程热点线从"全量"压到"按需/索引/二分";修复指纹两向非对称(内存缓存 lhs);定义弹窗预加载触发与管线。**行为正确性与 BS-2 后状态一致**(排序结果、去重合并、容量裁剪语义不变),只改算法与归属。
**依据**:`04`(load-fetch-all、findsimilar-full-table-refetch、add-resorts-whole-array、dedup-merges-by-copying-value-array、sessionlog-holds-strong-refs、decorator-init-side-effects、no-prefetch-on-popup-open、processpendingchanges-called-manually-and-redundantly、sorter-pinned-double-sort)、`01`(insertionindex-binsearchable、updateunpinned-double-pass)、`08-F-001`(V-2 确认,指纹非对称重哈希)。
**编译安全性**:核心变更是 `load()` 签名、`findSimilarItem` 内部实现、`add` 插入位置算法、`sessionLog` 元素类型;既有调用点(`ContentView.swift:55-57`、`History.swift:76-86,148-200` 等)在本步骤末尾全部对齐。

## 受影响文件
- 新:`Maccy/Ingest/SignatureIndex.swift`(BS-1 已新增纯值类型骨架,本步**填维护 API** + 与 ingestor 的接线契约)。
- 新:`Maccy/Persistence/VisibleWindowLoader.swift` — 后台分批 fetch + 仅装饰可见窗口的纯函数(可单测)。
- 新:`Maccy/Persistence/BinaryInsert.swift` — 已排序 `Collection` 的 O(log n) 插入索引计算(纯函数,可单测)。
- 改:`Maccy/Observables/History.swift:106-119`(`load` 重构:返回可见窗口 DTO,后台续预取)、`:122-128`(`limitHistorySize` 改批量,残留依赖 BS-2 已落单事务)、`:148-200`(`add` 改二分插入;`:151-153` 去重合并不再复制 `contents`)、`:455-470`(`findSimilarItem` 改查 `SignatureIndex`,全表 fetch 删除)、`:60-61`(`sessionLog` 改 `[Int: ItemID]`)、`:516-527`(`updateUnpinnedShortcuts` 双遍过滤改 diff)。
- 改:`Maccy/Observables/Popup.swift:113-123`(`handleFirstKeyDown` 触发预加载)、`Maccy/Observables/AppState.swift`(新增 `prewarmVisibleWindow()` 入口)、`Maccy/Views/ContentView.swift:55-57`(`task` 改为消费已预取数据或回落 `load`)。
- 改:`Maccy/Engine/HistoryItemEngine.swift:122-165`(`ContentIndex` 缓存 lhs 指纹;`contains` 两向传指纹)、`Maccy/Core/ClipboardDataProcessor.swift:31-60`(`dataLikelyEqual` 默认参数 trap 收紧——本步**仅**给 lhs 一个内存缓存来源,持久化列仍留 BS-8)。
- 改:`Maccy/Ingest/ClipboardIngestor.swift`(BS-2 actor:去重改查 `SignatureIndex`,合并走就地更新而非复制 contents;ingest 节流/coalesce 接线)。

## 小步骤

- [ ] **4.1 `SignatureIndex` 维护 API + 构建契约** — `SignatureIndex.swift`。在 BS-1 纯值类型骨架(`lookup`/`register`/`remove`/`bulkRegister`)基础上补:
  - `init(from snapshots: [ItemSnapshotDTO])` —— 由 `ItemSnapshotDTO` 重建(本步 snapshots 尚未带 lhs 指纹时,落回对 `contents` 取签名;指纹列在 BS-8 后直接读列)。
  - `mutating func merge(_ event: StoreEvent, snapshot: ItemSnapshotDTO)` —— 消费 `StoreEvent`:`.added`→`register`;`.merged`→`remove(旧 id)` + `register(新 id)`(合并后语义上同一条目,签名不变但 `lastCopiedAt` 变;按 BS-4 的去重定义,**签名键不随时间变化**,故 `merged` 等价于 `remove + register` 同一签名);`.removed/.cleared`→`remove`。
  - `func candidates(for request: IngestRequest) -> [ItemID]` —— 给 ingestor 的 `materialize` 阶段做 O(命中数)而非 O(n) 的命中候选;`materialize` 拿到候选后再做精确 `supersedes` 确认(防指纹碰撞与多内容场景)。
  - **纯函数契约**:`SignatureIndex` 无 SwiftData/AppKit 依赖,仅持有 `[SignatureDTO: ItemID]`(key 由 type + size + fingerprint 组合的稳定哈希);新建/查询/合并全程可单测。
- [ ] **4.2 [breaks compile until 4.3] `findSimilarItem` 改查索引** — `History.swift:455-470`。删除全表 `FetchDescriptor<HistoryItem>()` fetch 与 O(n) 扫描;改为读取由 ingestor/`load` 维护的 `SignatureIndex`(`History` 持有 `@ObservationIgnored var signatureIndex: SignatureIndex`),命中候选后做精确 `supersedes` 确认。`add`/`clear`/`delete`/`clearAll` 调用点同步更新索引(本步暴露 `signatureIndex` 为可空:未构建时回落旧路径——`History` 末尾 4.8 保证运行时非空)。`findSimilarItem` 在 `add`(`History.swift:149`)被调用前必须保证索引已构建。
- [ ] **4.3 [breaks compile until 4.8] `load()` 改后台分批 + 可见窗口装饰** — `History.swift:106-119`,新增 `VisibleWindowLoader.swift`。
  - `History.load()` 新签名:`@MainActor func load() async throws -> [HistoryItemDecorator]`(返回**已装饰的可见窗口**),内部:
    1. 在**后台 context**(`Storage.newBackgroundContext()`,BS-1 工厂)上构 `FetchDescriptor<HistoryItem>` 并设:`sortBy = [SortDescriptor(\.lastCopiedAt, order: .reverse)]`(由 `Defaults[.sortBy]` 驱动切换 `firstCopiedAt`/`numberOfCopies`)、`fetchLimit = max(historySizeLimit, visibleWindowHint)`、`propertiesToFetch` 排除大 blob 列、`relationshipKeyPathsForPrefetching = [\.contents]`。
    2. 后台投影为 `[ItemSnapshotDTO]`(BS-1 投影函数,跨边界 Sendable);**仅可见窗口**回主线程经 `HistoryItemDecorator` 装饰;其余快照存为待预取队列。
    3. 主线程赋值 `items = all = 可见窗口装饰`;`signatureIndex = SignatureIndex(from: 全部快照)`(索引基于**全部**,不只是可见窗口——后续 ingest 去重要覆盖整库)。
    4. 触发**后台续预取**(对超出可见窗口的快照,在低优先级 `Task` 上逐批装饰并 append 进 `all`,避免阻塞首屏);`limitHistorySize` 已在 BS-2 单事务裁剪,本步不重复。
  - `VisibleWindowLoader.swift`:`enum VisibleWindowLoader { static func fetchWindow(...) async throws -> ([ItemSnapshotDTO], [ItemSnapshotDTO]) }` 返回 `(visible, tail)`;纯函数 + 注入 context,可单测分批边界。
- [ ] **4.4 `add` 改二分插入 + 合并不复制 contents** — `History.swift:148-200`。
  - 插入位置(`:191-194`)由 `sorter.sort(all.map(\.item) + [item])` 改为 `BinaryInsertion.index(for: item, in: all, by: sorter.comparator)`(O(log n));新增 `BinaryInsert.swift`:`enum BinaryInsertion { static func index<C: RandomAccessCollection>(for element, in sorted: C, by areInIncreasingOrder) -> Int }`。**pinned 分区**:`byPinned`(`Sorter.swift:43-49`)视为前缀/后缀分区,二分先定位分区(由 `pin != nil` 与 `Defaults[.pinTo]` 决定),再在分区内按 `bySortingAlgorithm` 二分。
  - `togglePin`(`:439-444`)同样改 `BinaryInsertion.index`(同一辅助);同时消除 `Sorter.sort` 的双稳定排序(`sorter-pinned-double-sort`,`Sorter.swift:26-30`)的调用点。
  - 去重合并(`:151-153`):`item.contents = existingHistoryItem.contents.map { HistoryItemContent(type:value:) }` 改为**就地更新** `existingHistoryItem`(`lastCopiedAt`/`numberOfCopies += item.numberOfCopies`/`application`/`pin`/`title`/`firstCopiedAt`),**不再新建 `HistoryItemContent` 行、不复制 blob**(配合 BS-2 的单事务;签名键不变故 `SignatureIndex` 无需重注册)。`isModified(item) != nil` 的分支(`:150`)保留语义:仅当确实 modified 才需替换 contents——此时仍走新建,但在同一事务内删旧行(`dedup-merge-orphans-inverse-not-rewired`)。
- [ ] **4.5 指纹两向对称(内存缓存 lhs)** — `HistoryItemEngine.swift:122-165` + `ClipboardDataProcessor.swift:31-60`。修 `08-F-001`(V-2 已确认):
  - `ContentIndex`(`:123,137`)由 `[String: [Data]]` 改为 `[String: [(Data, UInt64?)]]`,构建时对每个 lhs blob 调一次 `ClipboardDataProcessor.fingerprintIfLarge` 并缓存(每个现有项的 `ContentIndex` 在 `load`/`add` 时建一次,而非每次 `contains`)。
  - `ContentIndex.contains(type:value:fingerprint:)`(`:153-165`)对每个 lhs 元素把缓存的 lhs 指纹与候选 rhs 指纹**两向**传入 `ClipboardDataProcessor.dataLikelyEqual`,消除 `dataLikelyEqual` 内 `lhsFingerprint ?? MaccyTextProcessor.fingerprint(for: lhs)`(`ClipboardDataProcessor.swift:53`)的重算路径。
  - **本步只缓存到内存**(`ContentIndex` 生命周期);`HistoryItemContent.fingerprint` 持久化列仍留 BS-8(O-007)。`dataLikelyEqual` 的两参默认值 trap(`:31-37` 死代码 + `:39-44` 双默认)本步**不动 API**,只保证调用点两向传值;BS-8 替换 FNV 时一并按 `08` F-009 收紧为 `MaccyFingerprint` DTO。
  - `SignatureIndex` 的 key 仍用候选(rhs)指纹 + size + type 组合;lhs 命中候选后由 `materialize` 走精确 `supersedes`,碰撞由最终 `lhs == rhs` 兜底(`ClipboardDataProcessor.swift:59`,正确性不变)。
- [ ] **4.6 [breaks compile until 4.8] `sessionLog` 改存 ItemID + `updateUnpinnedShortcuts` diff** — `History.swift:60-61, 179, 227, 260, 289, 516-527`。
  - `@ObservationIgnored private var sessionLog: [Int: HistoryItem]`(`:60-61`)改为 `[Int: ItemID]`(`ItemID` 为 BS-1 DTO 的 UUID/PersistentIdentifier 别名),不再持 `@Model` 引用;`isModified(item)`(`:472-478`)与所有读写点(`:179,227,260,289`)同步改类型。`isModified` 命中后回查 `all`/`items` 拿 decorator(由 id 反查,O(visible) 但调用频次低)。**本步为 `sessionLog` 迁移的唯一落地点**;BS-6 6.5 不再重复此迁移(仅核对 + 加 `HistoryRef`),消除原两步重复声明。
  - `updateUnpinnedShortcuts`(`:516-527`)双遍过滤(`:518-520` 清空、`:521-526` 重赋)改为**diff**:对每个可见 unpinned 项计算新 shortcut,仅在 `shortcuts != 新值` 时赋值(消除不变项的 SwiftUI 观察通知)。`updateShortcuts`/`refreshVisibleItems` 调用链不变。
- [ ] **4.7 摄取 coalesce/节流 + 预加载触发** — `ClipboardIngestor.swift` + `Popup.swift:113-123` + `AppState.swift`。
  - **coalesce**:ingestor 内对 pasteboard `changeCount` 抖动(同源连击,见 `04 no-coalesce-of-ingest-writes`)用 leading + trailing 节流(沿用 `Throttler` 原语或扩 trailing edge,`C-complexity-and-limits` 管线时延:复制文本→列表可见 < 16ms 主线程预算);coalesce 键用 `SignatureIndex.candidates` 的候选 id 命中——同候选命中即在 trailing 边合并为一次 `StoreEvent.merged`。**搜索的 `Throttler`(`History.swift:57`)保持独立**。
  - **预加载(pre-warm)**:`Popup.handleFirstKeyDown`(`:113-123`)在 `open(height:)` 之前调用 `AppState.shared.prewarmVisibleWindow()`(后台 `Task`);`AppState` 新增 `@MainActor func prewarmVisibleWindow()`,内部:若 `History.items` 为空或陈旧则触发后台 `VisibleWindowLoader.fetchWindow` + 主线程装饰,把就绪数据塞进 `History.items`;同时对可见窗口的前 N 项(默认 10)调 `ImageProcessor.thumbnail`(`02-IMG-002`,缩略图实现在 BS-3,本步**只定义触发与管线**:经 `ImageProcessor` 协议调用,BS-3 Passthrough 期间行为不变)。`ContentView.task`(`:55-57`)改为消费预取结果(`History.items` 已就绪则直接 diff,否则回落 `await load()`),首屏拿到的就是已装饰数据。
- [ ] **4.8 残留清理 + 恢复编译** — `History.swift` 全文。
  - 删除 `processPendingChanges()` 的残留手动调用(`:134, 240, 264, 283` 中 BS-2 后仍可能存在的点;BS-2 单事务后这些已无副作用,本步确认全部移除——`save()` 内部已处理,见 `04 processpendingchanges-called-manually-and-redundantly`)。
  - `withLogging`(`:204-214`)的两次 `fetchCount`(`dataCounts()`)用 `#if DEBUG` 包裹(或 logger level 门控),release 跳过 4 次诊断 round-trip(`04 fetchcount-withLogging-on-every-mutation`)。
  - `macOS 15` insert 分叉(`:141-146`):BS-2 已统一进 actor 单事务;本步核对 `Clipboard.swift:204-209` 的 `#unavailable` insert 已删,确认无双重 insert。
  - `limitHistorySize`(`:122-128`)残留的 `forEach(delete)` 调用链核对:BS-2 已改批量;本步核对 `unpinned[maxSize...]` 经批量 delete(单事务)而非逐项 save。
  - 恢复编译:确认 `load()` 新签名调用点(`ContentView.swift:55-57`、`History.swift:76-86` 的 `Defaults.updates(.sortBy/.pinTo)`)全部 `await` 并消费返回值;`findSimilarItem` 调用点(`:149`)在索引已构建路径下走索引;`sessionLog` 类型对齐;`updateUnpinnedShortcuts` 调用链不变。
- [ ] **4.9 测试 + 验证** — `xcodebuild build` + test 通过;`SignatureIndexTests`(查/注册/合并/批量/`candidates` 命中数)、`BinaryInsertionTests`(已排序数组二分索引正确性、pinned 分区边界、空数组/单元素)、`VisibleWindowLoaderTests`(分批边界、propertiesToFetch 投影、tail 队列长度)、`HistoryLoadTests.incremental`(后台续预取最终 `all.count` 等于全表)、`IngestCoalesceTests`(连击合并为单 `StoreEvent`)。性能闸门:`G-popup-open`(history=1000,主线程 < 16ms/首屏)、`G-copy-text`(主线程 < 16ms;`bytesHashed` 较 BS-2 下降——lhs 内存缓存生效,但未持久化故仍非 0,BS-8 后趋 0)。

## 关键签名

```swift
// Maccy/Ingest/SignatureIndex.swift(BS-1 骨架 + BS-4 维护 API)
struct SignatureIndex: Sendable {
  init()                                // 空
  init(from snapshots: [ItemSnapshotDTO])     // 4.1: load 后构建
  func lookup(_ signature: SignatureDTO) -> ItemID?                 // O(签名数) 哈希
  func candidates(for request: IngestRequest) -> [ItemID]           // 4.1: ingestor materialize 用
  mutating func register(_ signature: SignatureDTO, id: ItemID)
  mutating func remove(id: ItemID)
  mutating func bulkRegister(_ entries: [(SignatureDTO, ItemID)])
  mutating func merge(_ event: StoreEvent, snapshot: ItemSnapshotDTO)  // 4.1: StoreEvent 驱动
}

// Maccy/Observables/History.swift
@MainActor func load() async throws -> [HistoryItemDecorator]   // 4.3: 返回可见窗口;后台续预取 tail

// Maccy/Persistence/VisibleWindowLoader.swift
enum VisibleWindowLoader {
  static func fetchWindow(
    in context: ModelContext,
    sortBy: Sorter.By,
    fetchLimit: Int,
    visibleHint: Int
  ) async throws -> (visible: [ItemSnapshotDTO], tail: [ItemSnapshotDTO])
}

// Maccy/Persistence/BinaryInsert.swift
enum BinaryInsertion {
  static func index<C: RandomAccessCollection>(
    for element: C.Element,
    in sorted: C,
    by areInIncreasingOrder: (C.Element, C.Element) -> Bool
  ) -> Int where C.Index == Int
}
```

## 复杂度(前→后)

| 操作 | 前(file:line) | 前复杂度 | 后复杂度 | 落点 |
|---|---|---|---|---|
| 冷开 load | `History.swift:106-119` | O(n) fetch + O(n log n) 排序 + O(n) 装饰(全 main) | **O(visible)** 主线程装饰;O(n) 后台分批预取(低优先级) | 4.3 |
| 复制去重 | `History.swift:455-470` | O(n) 全表 fetch + 每项 lhs 重哈希(`08-F-001`) | **O(签名命中数)** 索引查询 + 命中候选精确确认(lhs 内存缓存→无重哈希) | 4.2, 4.5 |
| 复制插入 | `History.swift:191-194` | O(n log n)(`sorter.sort(all+[item])` + 双稳定排序) | **O(log n)**(二分插入,pinned 分区 + 算法内二分) | 4.4 |
| 去重合并内存 | `History.swift:151` | blob 全复制(瞬时双份) | **O(1)** 就地更新(无新建 `HistoryItemContent`) | 4.4 |
| shortcut 刷新 | `History.swift:516-527` | O(visible) 双遍(清空 + 重赋,每项观察通知) | O(visible) 单遍 diff(仅变更项赋值) | 4.6 |
| 哈希调用 | `ClipboardDataProcessor.swift:53` | 每比对重算 lhs FNV | **0**(lhs 缓存在 `ContentIndex`) | 4.5 |

## 管线估计

- 弹窗冷开→首屏可交互:主线程从"全量 fetch+排序+装饰"压到"装饰可见窗口" → 满足 `G-popup-open` < 16ms/首屏(目标);tail 后台续预取不阻塞交互。
- 复制文本→列表可见:去重不再全表 fetch,索引查询 O(命中数);插入 O(log n);合并无 blob 复制 → 主线程仅追加单行 diff,满足 `G-copy-text` < 16ms。
- 预加载:hotkey-down 触发 `prewarmVisibleWindow`,首屏拿到已装饰数据 + 前 N 缩略图管线(BS-3 实装后到位)。

## I/O 限制

- `FetchDescriptor.fetchLimit` = `max(historySizeLimit, visibleWindowHint)`,不再无界全量(`C §1`)。
- `propertiesToFetch` 排除 `value`(blob)列;`relationshipKeyPathsForPrefetching = [\.contents]` 仅对可见窗口批量 fire fault(`04 load-no-relationship-faulting`)。
- 合并不复制 `value`(`:151` 修复);`sessionLog` 不持 blob(`:60-61` 修复,`05 sessionlog-keeps-historyitem`)。
- 哈希阈值 `16 KiB`(`ClipboardDataProcessor.swift:4`)不变;lhs 缓存仅命中此阈值以上,小内容仍走 `lhs == rhs`。

## 闸门

- **`G-popup-open`**:history=1000,弹窗打开→首帧,主线程占用 < 16ms(目标;BS-2 前 > 50ms)。测量:`MainThreadProbe` + `OSSignposter` 标 `load` 与 `prewarmVisibleWindow` 区间。
- **`G-copy-text`**:复制 `heavy_text.txt`,主线程 < 16ms;`bytesHashed` 较 BS-2 下降(lhs 内存缓存生效),**本步未持久化故仍非 0**(BS-8 持久化指纹列后趋 0)。`IngestResult.metrics.bytesHashed` 由 ingestor 记录并断言。

## 测试

- 引用:`B §2`(`HistoryBuilder`、`FixtureLoader`、`IngestorSpy`、`MainThreadProbe`)、`§3`(数据流抽象:`IngestPlan`/`metrics`)、`§4`(`G-popup-open`、`G-copy-text`)。
- 新增/扩充:`SignatureIndexTests`(merge 各分支、`candidates` 命中数)、`BinaryInsertionTests`、`VisibleWindowLoaderTests`、`HistoryLoadTests.incremental`(tail 预取最终一致)、`IngestCoalesceTests`(连击→单 `StoreEvent.merged`)、`FingerprintSymmetryTests`(多同型 lhs blob 下 `bytesHashed` 不随 lhs 数线性增长——覆盖 `08-F-001`)。

## 验收标准

- 功能:`load` 返回的可见窗口与改前首屏排序一致;tail 预取最终 `all.count` == 全表;去重命中/合并语义与改前一致(相同内容→`.merged`,`isModified` 分支行为不变);二分插入位置 == `sorter.sort` 结果中该项 index(逐项属性测试);shortcut diff 不改变最终赋值。
- 复杂度:见上表(load `O(n)全量装饰`→`O(visible)`;dedup `O(n) fetch + lhs 重哈希`→`O(命中数)`;insert `O(n log n)`→`O(log n)`)。
- 管线:见上(主线程 < 16ms/首屏与 < 16ms/复制)。
- I/O 限制:`fetchLimit`/`propertiesToFetch`/prefetch 就位;合并无 blob 复制;`sessionLog` 改 `ItemID`。
- 不变性:`A §7` 的"主线程无 >16ms 同步重活""跨 actor 载荷 Sendable"在本步对 load/dedup/insert/预加载达成;"单一可变源"由 `SignatureIndex` 与 ingestor 单事务协同保证(索引是 store 的投影,不持有真相)。

## Commit
`perf(data-pipeline): batched background load, signature-index dedup, binary insert, symmetric in-memory lhs fingerprint, popup pre-warm, sessionLog→ItemID`

---

## 2026-06-21 复核与改写(recorded deviation)

**触发**:P0/P1/P2/P3 渲染止血收尾后(均 CI 绿,`1179b19` / run `27907591119`),
harness 给出诚实基线(1000× bug 已修),复核 step-4 原文与 BS-2 后的**实时**架构
发现原文部分小步骤瞄准的是 BS-2 之前的旧代码,已于 BS-2 作废。按 CLAUDE.md
"先在审计文档记录偏差再提交"的要求,本节改写受影响小步骤的落点。

### 实时基线(2026-06-21, run `27907591119`, 1000× 修复后)

| 场景 | 指标 | 值 | BS-4 目标 |
|---|---|---|---|
| 冷开 `load()` image-many-200 | `mainThread_maxGap_s` | **0.999s** | < 16ms 首屏 |
| 冷开 `load()` mixed-200 | `mainThread_maxGap_s` | 0.460s | < 16ms 首屏 |
| 冷开 `load()` text-many-200 | `mainThread_maxGap_s` | 0.431s | < 16ms 首屏 |
| 复制 `consume`→reconcile (text, N=20) | `perCopyMaxMs` | **14.22ms** | < 16ms/复制 |
| 复制 `consume`→reconcile (text, N=20) | `perCopyAvgMs` | 8.88ms | — |
| 复制 `consume`→reconcile (text, N=20) | `mainThread_maxGap_s` | **0.324s** | 消除全表 refetch |

`load()` 的 ~1s 主线程块 = 全表 `context.fetch` + `sorter.sort` + 装饰全表(均在
`@MainActor`,`History.swift:201-214`)。复制路径的 0.324s maxGap =
`reconcileWithStore`(`History.swift:291-324`)**每次复制都全表 refetch + 全表
resort**(`:294`)。

### 已作废的旧落点(4.2 / 4.4 原文瞄准 BS-2 前代码)

BS-2 把实时摄取迁到 `@ModelActor BackgroundClipboardIngestor`,通过 `StoreEvent`
驱动 `History.consume`→`reconcileWithStore`(`AppDelegate.swift:76` 接线)。复核
调用点:

- **`History.add`(`History.swift:233`)** 唯一调用者是
  `ClipboardIngestor.swift:15` 的 `MainActorIngestorAdapter` —— 这是 BS-1 留下的
  **遗留适配器,生产已不用**(实时路径走 `BackgroundClipboardIngestor`)。
  `findSimilarItem`(`History.swift:640`)仅被 `add`→`mergeDuplicateIfNeeded`
  (`:328`)调用,随 `add` 一并作废。
- 因此**原 4.4(`add`→二分插入)与原 4.2(`findSimilarItem`→索引)瞄准的是死代码**。
  实时去重已在 actor 内:`BackgroundClipboardIngestor.findDuplicate`
  (`ClipboardIngestor.swift:221`)做 `existing.first { $0.supersedes(signature) }`
  的**线性扫描**,且 `SignatureIndex` 尚未接入实时去重。

### 改写后的落点

- **4.2(retarget)** — 索引去重的真实落点改为 `BackgroundClipboardIngestor`
  而非 `History.findSimilarItem`:
  - ingestor 在 `@ModelActor` 内维护 `SignatureIndex`(Sendable;`init(from:)` 已就绪),
    `findDuplicate` 改查索引(`candidates(for:)` → 命中候选后精确 `supersedes` 确认),
    从 O(n) 线性降为 O(命中数)。
  - 索引构建:ingestor 在初始化/首摄取时由后台 context 投影 `[ItemSnapshotDTO]` 构建
    (`SignatureIndex.init(from:)`),`merge(_:)` 消费每次 `StoreEvent` 增量维护。
  - `History.findSimilarItem` / `add` / `mergeDuplicateIfNeeded` 是死代码,本步**不
    改其实现**(避免给死代码投入);BS-4 末尾 4.8 评估是否直接删除(连同
    `MainActorIngestorAdapter`),需确认无测试/特性开关依赖。
- **4.4(retarget,新增 4.4a reconcileWithStore 增量化)** — 实时每复制一次的
  `reconcileWithStore` 全表 refetch+resort 是测得的 0.324s maxGap 来源,**原 step-4
  无任何小步骤覆盖它**,这是原文的缺口。新增:
  - `consume(.added/.merged)` 不再全表 refetch:由 `StoreEvent` 携带的
    `ItemSnapshotDTO`(已是 Sendable)在主线程**增量**插入/移动到 `all`/`items` 的
    正确位置,复用既有 decorator(按 `persistentModelID`),仅对新增/变更项装饰。
    插入位置用 `BinaryInsertion.index`(`4.4` 仍提供此纯函数,pinned 分区 + 算法内
    二分),`O(log n)`。
  - `.removed`/`.cleared` 走增量删除(按 id)而非全表重建。
  - 全表 refetch 仅保留为兜底(索引/事件丢失或 `Defaults` 排序变更时)。
  - 语义不变:最终 `all` 的排序结果 == 改前全表 sort 的结果(逐项属性测试保证);
    decorator 复用使已解码缩略图幸存(与现 `reconcileWithStore` 一致)。
  - **4.4 的二分插入纯函数 + pinned 分区**仍按原文实现(`BinaryInsert.swift`),只是
    主消费者从死掉的 `History.add` 改为 `History.consume`。
- **4.3** — 不变,仍是最高价值(`load()` 的 ~1s→<16ms)。`VisibleWindowLoader` 后台
  分批 + 仅装饰可见窗口 + tail 低优先级续预取;`signatureIndex` 由全部快照构建
  (供 4.2 ingestor 共享,或独立构建——4.1 契约已允许多实例)。
- **4.5 / 4.6 / 4.7 / 4.8 / 4.9** — 仍相关,执行到时逐一复核:
  - 4.5(指纹对称)落点 `ContentIndex`/`ClipboardDataProcessor` 仍为实时去重服务;
  - 4.6(`sessionLog`→`ItemID`)落点不变(`History.swift:60-61`),但需确认
    `sessionLog` 是否仍被实时路径读(`isModified` 仅 `mergeDuplicateIfNeeded` 用→随
    `add` 作废?复核);
  - 4.7(coalesce + prewarm)落点 `Popup`/`AppState`/`ClipboardIngestor` 不变;
  - 4.8 残留清理增加"评估删除 `add`/`findSimilarItem`/`MainActorIngestorAdapter`"。

### 复杂度表更新

| 操作 | 前 | 后 | 落点 |
|---|---|---|---|
| 冷开 load | O(n) fetch+sort+装饰(全 main),maxGap 0.999s | **O(visible)** 主线程装饰;O(n) 后台分批 | 4.3 |
| 复制去重(actor) | O(n) 线性 `supersedes` 扫描 | **O(命中数)** 索引查询+精确确认 | 4.2(retarget) |
| 复制 reconcile | **O(n) 全表 refetch+resort/次**(maxGap 0.324s) | **O(log n)** 增量二分插入/移动 | 4.4a(新增) |
| shortcut 刷新 | O(visible) 双遍 | O(visible) 单遍 diff | 4.6 |
| 哈希调用 | 每比对重算 lhs FNV | 0(lhs 内存缓存) | 4.5 |

### 执行顺序(改写后)

4.1(已就绪)→ **4.3(load,最高价值,先止血冷开)** → **4.2(retarget ingestor
索引去重)** → **4.4 + 4.4a(BinaryInsertion 纯函数 + reconcile 增量化)** →
4.5 → 4.6 → 4.7 → 4.8(含死代码删除评估)→ 4.9。每小步 TDD + 提交 + CI(≥2min
轮询),BS-4 末尾整步编译+全绿后推送。

### 不变量(改写后仍守)

- `A §7`:"主线程无 >16ms 同步重活""跨 actor 载荷 Sendable" —— 对 load / dedup /
  reconcile / 预加载达成。
- "单一可变源":`SignatureIndex` 是 store 的投影,ingestor 单事务写 + 事件驱动增量维护;
  `History.all`/`items` 的真相仍是 SwiftData,增量 reconcile 是其投影。
- 行为正确性与 BS-2 后状态一致(排序/去重合并/容量裁剪语义不变)。

---

## 2026-06-22 增补:4.10 渲染链去风暴(D2 域)

**触发**:固定行高 + 悬停不滚 + 预览取消等 P0/P1/P2/P3 止住灾难性
LazyVStack 反馈风暴后,对常驻 app 重新 `sample` 仍看到弹窗打开路径数十 ms 级主线程
同步工作。完整诊断见 `docs/audit/architecture-and-root-causes.md` §2.5(UI/渲染)。

**关键认知**:路标把 `G-popup-open` 定义为 `load()`(冷启动数据,D1 域),但用户
`sample` 反映的是**常驻打开渲染链(D2 域)**——这两条路径不同。`ContentView.task`
(`ContentView.swift:55-57`)只在启动跑一次,常驻打开不 reload。D2 域此前**无闸门、
无整体优化**,本步收编。

**性质**:4.10 全部是**纯主线程 UI 改动**,不跨 actor、不碰 SwiftData、不改数据语义
——落在 BS-4 编译边界内,与 4.3/4.4a(D1)互补。行为正确性与改前一致(选择/预览/排序
结果不变),只减冗余触发与渲染抖动。

### 小步骤

- [ ] **4.10a 打开路径去冗余** — `Popup.swift:75-80` + `HistoryListView.swift:115-128` +
  `FloatingPanel.swift:180-186`。打开时 `select(first)` 与 preview auto-open 各被触发
  **两次**(`Popup.open` + scenePhase.active;`windowDidBecomeKey` + scenePhase.active)。
  合并:scenePhase `.active` 复用 `Popup.open` 已建立的选择(或反之),preview auto-open
  只武装一次。语义不变(打开仍选中首项、仍按 `previewDelay` 自动开预览),只消除重复的
  selection 重建与 `scrollTarget` 周期(审计 S2/S3)。
- [ ] **4.10b 复制期 resize 去抖** — `History.swift:323` + `HistoryListView.swift:133-141` +
  `FloatingPanel.swift:89-99`。`reconcileWithStore` 每次复制设 `popup.needsResize=true`
  → 触发 `panel.verticallyResize`(0.2s `NSAnimationContext` CA 事务),**即使窗口高度
  未变**。改为:resize 仅在「可见行数真的跨过高度阈值(首屏可见行数变化)」时触发动画;
  高度不变只标 dirty、不开 CA 事务。配合审视 `ContentView.swift:35`
  `.animation(.default.speed(3), value: items)` 在复制期是否必要(审计 S9/S10)。
- [ ] **4.10c hover 抖动收敛** — `NavigationManager.swift:14-19,31-61`。hover 越行时
  `selection.willSet` 逐行写旧/新项 `selectionIndex`(行重渲染),`leadHistoryItem.didSet`
  每次 id 变都 `Task{ cancelPreviewGeneration }` + `startAutoOpen`。收敛:`selection` 重建
  时 `selectionIndex` 已是批量赋值(现状),重点对 `leadHistoryItem.didSet` 的连续变化做
  leading-edge 节流(沿用 `Throttler` 原语),只在 hover 停留稳定后才武装 preview
  auto-open/cancel(scrollTo 风暴已由 P1 止住,本步处理残留 selectionIndex/lead 抖动;
  审计 S12)。
- [ ] **4.10d 列表分配 + 行 body 搬计算** — `MultipleSelectionListView.swift:9-15` +
  `HistoryItemView.swift:40`。`ForEach(Array(items.enumerated()))` 每次 body 全量分配
  O(n) 元组数组(审计 S13);改 `ForEach(items, id:\.id)` + content 内按 index 取
  neighbor(或 `zip(indices, items)`)。同时把 `ColorImage.from(item.title)` 的深治
  (S14)落在这里:把 color accessory image 提到 decorator 缓存(title 变更时失效),
  行 body 只读缓存,消除每帧计算(本批 S14 先用 `ColorImage` 内 NSCache 兜底,深治在此)。
- [ ] **4.10e `.drawingGroup()` 精细化** — `ListItemTitleView.swift:18-20`。每可见行标题
  `.drawingGroup()` 各开一个 Metal backing store(macOS 26 翻转 workaround)。评估能否
  仅对「会触发翻转的分支」保留、纯文本短标题去掉,减首帧 CA backing store 数(审计 S7)。
  需 UI 测试覆盖 `p0deje/Maccy#1113` 翻转回归。
- [ ] **4.10f 列表标题测量削减(#2,2026-06-22 据 sample 新增)** — `HistoryItem.swift:9` +
  `ListItemTitleView.swift:12,17` + `HistoryItemView.swift:47`。原始 `sample`(发布版
  2.6.1,见 `docs/audit/architecture-and-root-causes.md` §2.5)证明主成本是 CoreText 文本
  测量,放大器是:行标题展示上限 `titlePreviewLimit = 1_000` + `.truncationMode(.middle)`
  → **middle 截断要求 CoreText 测整个字符串**定中点,每可见行测 ~1000 字符(单行只显
  ~60–80)。改进:(a) 给**列表展示**单独的更短上限(~150–200 字符,完整标题仍用于预览/
  tooltip);(b) 评估 `.tail` 替 `.middle`(tail 增量早退;middle 是产品意图需权衡)。把每行
  CoreText 工作砍数倍。需测试覆盖超长标题/UI 的可见性。

### 优先级(2026-06-22 据 sample 重排)

据原始 `sample`(`§7`),4.10 真实影响序:**4.10b(S9/S10 动画 resize→每帧全树布局,#1) →
4.10f(标题测量,新增,#2) → 4.10e(drawingGroup) → 4.10a/4.10c/4.10d**。S6(窗口操作)只评估
不动。`G-resident-open` 闸门量化每步收益。

### 先行落地(零行为变更,本批独立小步)

- **S11** `Sorter.byPinned` 把 `Defaults[.pinTo]` 提到 `sort(_:)` 顶部读一次,比较器闭包
  捕获 —— 消除 O(n log n) 次/sort 的 Defaults 读(load + 每复制 reconcile 都受益)。
- **S14** `ColorImage.from` 加 `NSCache<NSString, NSImage>` —— color-code 标题的
  `lockFocus`/`drawSwatch` 位图生成只做一次(非 color 标题本就走 `NSColor(hexString:)`
  早返回,代价低;深治「提到 decorator」见 4.10d)。

### S6(窗口 `makeKey`/`orderFront` 的 WindowServer IPC)— 仅评估,不改

`FloatingPanel` 用 `.nonactivatingPanel`+`canBecomeKey=true`,`orderFrontRegardless()`+
`makeKey()`(`FloatingPanel.swift:78-79`)是 panel 同步成 key 以接收 cycle 模式后续按键
的最小必要集。延后 `makeKey` 会破坏热键 cycle 交互;`sample` 里的
`_stealKeyFocusWithOptions`/`SLPS*` 是 `makeKey` 在 SkyLight 的固有下沉。**记为固有成本,
不动。**(详见审计 §6。)

### 闸门(新增 `G-resident-open`)

- **`G-resident-open`**(D2 域,新增):app 已 warm(history 已 `load`),驱动一次
  `Popup.handleTestingHotKeyDown` 等价路径(走 DEBUG 分布式通知桥,与 `PerfRenderUITests`
  一致)→ 首帧,`MainThreadProbe.maxGap` 主线程 **< 16ms**。测量 `load` 区间外、纯打开
  渲染链。**这是补 `G-popup-open`(=load)测不到的 D2 缺口**(审计 S17)。
  - 实现随 harness rework(见 memory `perf-harness-rework-state` Step 3-5)落地;UI 计时
    在严重竞争的 runner 上有 flake 风险(`testClear`/`testPin` 同源),闸门定义先于此确立。
- **`G-popup-open`**(D1 域,既有):history=1000,`load()` 主线程 < 16ms/首屏(不变,
  4.3 驱动)。

### 复杂度(前→后)

| 操作 | 前 | 后 | 落点 |
|---|---|---|---|
| 打开首帧主线程 | 重复 select×2 + 重复 preview 武装×2 + 多 GeometryReader + 全量 filter/分配,数十 ms | 单次 select + 单次 preview 武装 + 合并 layout pass | 4.10a/d |
| 复制期 CA | 每次复制动画 resize(即使高度不变) | 仅高度真变才动画 | 4.10b |
| hover 越行 | 逐行 selectionIndex + lead didSet 抖动 | lead 节流,稳定后才武装 preview | 4.10c |
| Sort 排序 | O(n log n) 次 Defaults[.pinTo] 读/sort | **1** 次 | S11(先行) |
| color 行渲染 | 每帧 `lockFocus` 位图生成 | 缓存命中 0 | S14(先行)→4.10d 深治 |

### Commit

- S11:`perf(bs4.10): hoist Defaults[.pinTo] out of Sorter comparator (S11)`
- S14:`perf(bs4.10): cache ColorImage by title (NSCache) (S14)`
- 4.10a–e:每小步 `perf(bs4.10x): ...` + TDD(UI 行为测试覆盖选择/预览/翻转回归)。
- 末尾整步编译 + 全绿后推送(BS-4 编译边界)。

---

## 2026-06-22 BS-4 总进度复盘(已完成 / 已推迟 / 未做 / 困境)

> 阶段性盘点,把这一轮的 done / deferred / not-done / dilemmas 整理清楚,供后续接续。

### ✅ 已完成(CI 绿)

| 小步 | commit | 收益 / 说明 |
|---|---|---|
| 4.1 SignatureIndex 维护 API | (BS-1 已就绪) | `init(from:)`/`merge`/`candidates` 齐备 |
| 4.3.1 `VisibleWindowLoader` 原语 | `2fa470f` | 有界 fetchLimit + algorithm sortBy + visible/tail 拆分;colocate 在 `Storage+Background.swift`(pbxproj 非同步)。喂 4.2/4.5 的 offmain signatureIndex,**非** load() 提速关键路径 |
| 4.4 `BinaryInsertion` 纯函数 | `a1411c8`(随 4.4a) | O(log n) 插入索引,落在 `Sorter.swift` |
| **4.4a 增量 reconcile** | `a1411c8` | **本轮最大收益**:per-copy 从全表 fetch+sort 改为 `model(for: persistentID)` 单点取 + 二分插 + `fetchIdentifiers` 同步。**G-copy perCopyAvg 9.34→0.99ms(9×),max 18.11→1.25ms**,n=1000 仍 <16ms |
| 4.7 预热 prewarm | `2e0b3a3` | `AppState.prewarmVisibleWindow()` 在 `Popup.handleFirstKeyDown` open 前触发;`ContentView.task` 仅 items 空才 load(不重复) |
| 4.10b 动画 resize 移除 | `c3802e9` | `verticallyResize` 即时 setFrame(原 0.2s animator 每帧全树 layout) |
| textPreviewLimit 10k→3k | `8700a5a` | 预览栏 CoreText 上限 |
| previewMaxPixels 1600→800 | `545d4d4` | 预览图解码/渲染(slideout 显示尺寸远小于 1600) |
| S11 Sorter hoist Defaults | `6eedbe4` | O(n log n)→1 次 `Defaults[.pinTo]` 读/sort |
| S14 ColorImage NSCache | `27f9b51` | color 行 `lockFocus` 位图缓存 |
| (关联,BS-6) blob-deferral | `0be3e20` | `imageData` 懒加载;**load() image-many 1.14s→~0.8s(load() 的真正大头)** |

### ⏸ 已推迟(含理由)

| 小步 | 理由 |
|---|---|
| **4.3 load() 重写(visible + 异步 tail)** | 唯一能再砍 load_avg(~50ms post-BS-6)的写法是"只装饰可见窗口 + 异步 tail",但这**改变 load() 同步契约**(`await load()` 返回时 all=可见而非全量 → G-copy 等"load 后 all==全量"的测试需 await tail,有测试改动),且 **gate 收益不明**(tail 仍在主线程装饰、每批 `items=all` 重渲染,末批渲染全量 → maxGap 可能不降)。叠加 BS-6 已砍 load()(1.14→0.8s)、gate 是 render-bound → 4.3(数据)不动 gate。故选 **4.7 prewarm**(更安全、无契约改动)替代 |
| **4.10 渲染(gate)** | 4.10b / textPreviewLimit / previewMaxPixels 已落。残余 gate(~0.8s 测试 / ~0.27s 真实每次冷开)主要是 items=200 的 SwiftUI 渲染,**不大改结构(虚拟化装饰 / 增量 items)基本不可再降**。4.10f(列表标题截断)是唯一未试杠杆(有 UX 取舍)。**items-animation 移除已回滚**——它在"抹平"渲染尖峰,移除后 maxGap 0.624→1.200(更差)|

### ❌ 未做(剩余,优先级低)

| 小步 | 状态 / 为何低优先 |
|---|---|
| 4.2(retarget)ingestor 索引去重 | ingestor 的 O(n) 线性 supersedes → SignatureIndex O(命中)。**offmain**(非主线程);per-copy 已 1ms(post-4.4a),主线程收益小 |
| 4.5 指纹对称(ContentIndex lhs 缓存) | offmain;主线程收益小 |
| 4.6 sessionLog→ItemID + updateUnpinnedShortcuts diff | 内存/正确性;低风险。sessionLog 在实时 ingest 路径下可能已死(需复核) |
| 4.8 残留清理(processPendingChanges 去重、fetchCount 日志门控) | 低风险低收益的清理 |
| 4.9 全量测试 + 闸门验证 | 4.4a 测试已落;完整 gate 验证待 harness |

### 困境与关键发现

1. **`G-popup-open` 闸门是 render-bound,不是 data-load-bound。** load_avg(~50ms post-BS-6)是数据活;maxGap(~0.8s 测试)是 items=200 落到被观察的 `History.shared`→ContentView 的 SwiftUI 渲染。**load 侧工作(4.3)不动 gate;渲染(4.10)才动。**
2. **闸门噪声大(±50%)。** image-many 在 0.624/1.200/0.801 间跳。**无法干净测量 <2× 的变化**(曾用 logic-verified 策略;#2 perf 测试稳定化后基本解除)。
3. **动画不总是浪费——有的在"抹平"尖峰。** 4.10b(窗口 resize 动画 = 每帧全树 layout,**浪费**)有效;但 items-transition 动画移除**变差**(它把列表渲染摊到多帧,移除后集中成一帧 → maxGap 0.624→1.200),已回滚。**判据:每帧全树 layout = 浪费;每帧部分行 layout = 抹平器。**
4. **per-copy 已解决(4.4a:1ms)。** G-copy 闸门达标,9× 余量,n=1000 仍 <16ms。
5. **load() 已基本解决(BS-6:blob-deferral)。** image 1.14→0.8s。再砍 load_avg(4.3)收益小 + 风险高。
6. **渲染残余(~0.8s 测试 / ~0.27s 真实)基本不可再降**,除非大改(虚拟化装饰 / 增量 items)。测试的 3 次 load 迭代把数字放大 ~3×。

### 闸门现状

| 闸门 | 现状 | 目标 |
|---|---|---|
| `G-popup-open`(= load) | maxGap ~0.8s(噪声大,render-bound);load_avg ~50ms | <16ms(未达;渲染是阻塞) |
| `G-copy` | per-copy ~1ms(post-4.4a) | <16ms(**达标**,9× 余量) |
| `G-resident-open` | 未实现(harness rework Step 3-5) | <16ms |

### 下一步(建议优先级)

1. **perf-harness rework(Step 3-5)** —— 让闸门(尤其 G-popup-open、G-resident-open)可靠 + 能干净测渲染。
2. **4.10f**(列表标题展示截断)—— 唯一未试的渲染杠杆(UX 取舍:长标题尾)。
3. **4.8 + 4.6** —— 安全收尾(清理 + sessionLog)。
4. **4.3 load() 重写** —— 仅当 load_avg(~50ms)成为体感问题(当前相对渲染是次要)。

---

## 2026-06-24 BS-4.2 + 4.5 完成(per-entry 包含索引去重 + 指纹对称)

> 本轮把 4.2(retarget:ingestor 索引去重)与 4.5(指纹两向对称)落地,CI 绿。
> 此后本 session 停止;下一 session 做 BS-6(内存,用户反映占用过大)。

### 落地内容

- **4.2 — `SignatureIndex` 改 per-entry 包含索引并接入 ingestor。** 关键认知:实时去重
  `existing.supersedes(newSig)` 是**包含**语义(existing 是 new 的超集),不是精确相等。
  原 `candidates(for:)` 是 full-signature 精确匹配,既漏掉子集情况(纯文本复制命中更富
  的既有项应合并却不合并→产生重复条目),也对"全新内容"复制无帮助。故改为**逐 entry 索引**:
  `[ContentSignatureEntry: Set<ItemID>]`,`candidates(forEntries:)` 返回与 new 共享任一
  entry 的候选;`supersedes` 精确确认兜底(同 size 小内容碰撞、指纹碰撞)。全新内容 0 候选
  → O(1) 插入不扫表(常见复制路径的最大收益)。
- **桥接 `persistentIDByItemID`**:`SignatureIndex` 键是 `ItemID`(UUID,易单测),但
  `modelContext.model(for:)` 要 `PersistentIdentifier`。故 ingestor 维护
  `[ItemID: PersistentIdentifier]`(由 `snapshot(of:)` 同时给出 `.id` + `.persistentID`
  填充)。`findDuplicate`:候选 ItemID → 桥 → `model(for:)` → `supersedes` 确认。
- **惰性构建 + 增量维护**:首次 ingest 时 `ensureDedupIndexInitialized()` 一次 O(n) fetch
  构建索引(替换原来**每次复制**都全表 fetch + O(n) 扫描);之后每次 commit 增量维护
  (`commit` 现返回被删 ItemID:dup + 容量裁剪淘汰项;`maintainDedupIndex` 注销删除项 +
  注册插入项,save 后取最终 `persistentModelID`/`ItemID`)。
- **4.5 — 指纹对称**:lookup entry 由 `@Model.contents` 经 `fingerprintIfLarge` 构建
  (≥16KiB 取真实指纹),与索引构建方式一致——大内容重复制能命中合并,而非 nil-vs-hash
  失配漏判。

### 复杂度(前→后)

| 操作 | 前 | 后 |
|---|---|---|
| 复制去重(actor) | 每次全表 fetch + O(n) `supersedes` 扫描 | **O(命中数)** 索引查询 + 精确确认;全新内容 O(1) |

### 测试

- `SignatureIndexTests` 新增 per-entry 包含用例:超集命中、精确命中、全新内容空、去重、
  多项共享、move+remove 清理、`init(from:)`/`merge` 维护。
- `BackgroundClipboardIngestorTests` 新增:子集复制合并(包含情况,精确索引会漏)、
  大文本(>16KiB)重复制经指纹合并(4.5 对称守卫)。既有去重/裁剪/原子性测试不变(语义一致)。

### Commit

- `f6e4f22` — `feat(bs4.2)`: SignatureIndex per-entry 包含索引(纯值类型 + 测试)
- `5189152` — `feat(bs4.2)`: 接入 ingestor(O(hits) 去重 + 桥 + 惰性构建/增量维护 + 4.5 对称)
- `5288b4a` → 被 `a8365fa` 取代:初版用 per-file `file_length`/`type_body_length` 禁用,
  但触发 `blanket_disable_command`。按用户要求改把 `file_length`/`type_body_length`/
  `function_body_length` 阈值提到 1000(`a8365fa`),并删除全仓随之 superfluous 的长度禁用
  (`a8365fa` 含 12 个生产/测试文件 + `073e687` 补 MaccyUITests)。CI 绿(run `28104358265`)。

### 仍 deferred(同 2026-06-22 复盘)

4.6(`sessionLog`→ItemID;实时路径下 `History.add`/`findSimilarItem`/`sessionLog` 已死,
仅测试可达——删除是大测试重写而非迁移)、
4.8 残留清理、4.9 全量闸门、4.10f 渲染杠杆、perf-harness rework Step 3-5。


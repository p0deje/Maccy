# 架构与根因总览(单一权威参考)

本文档是 Maccy 当前架构、瓶颈、数据安全、内存、路线图完成度的**单一权威参考**,由 ~30 份历史审计文档(2026-06-14 深度审查 / 2026-06-25 模块分析 / 2026-06-27 内存实测 / 2026-06-28 路线图缺口审计)蒸馏而成,反映 **2026-06-29 真相**。完成度细节见 `docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/`,内存实测见 `docs/audit/2026-06-27-memory-floor-and-retention/`。`finding-id` 词汇表见本文末尾。

> 代码标识符保留英文;行号以 HEAD `b6653fc` 为准。

---

## 1. 架构总览

### 1.1 单一根因(原始诊断,至今仍是设计的出发点)

> **整条数据管线曾经全部 `@MainActor` 隔离、且只用 SwiftData 的 `container.mainContext`。没有后台 context、没有 actor、没有任何重活被搬离主线程。**

证据(`Storage.swift:5,10`):
```swift
@MainActor class Storage {
  static let shared = Storage()
  var context: ModelContext { container.mainContext }   // 唯一入口,绑死主队列
}
```

BS-1~BS-4 已围绕此根因重构管线(copy 路径已离主线程),**但 `Storage` 的 `mainContext` 仍是 `History.load()` / `reconcile` / `delete` / `pin` 的唯一上下文**,内存态与读取侧的根因未消除(见 §2、§4)。

### 1.2 两域隔离模型(目标态,部分已落地)

```
┌──────────────── Main(UI 线程)─────────────────┐   ┌──────────────── Background(actor)────────────────┐
│ SwiftUI Views (HistoryListView/ListItemView/      │   │ actor ClipboardIngestor 【BS-2 已接入 live】       │
│  PreviewItemView)——仅绑定 @Observable 状态        │   │  ├─ 读 NSPasteboard(后台)                         │
│                                                    │   │  ├─ 过滤(filterContents)+ 标题(title(for:),       │
│ @Observable History(瘦视图模型,持有 items/all)     │   │  │   仍回主线程:Defaults + NSAttributedString)     │
│  ├─ consume(StoreEvent) 增量更新(二分插入)        │◄──┤  ├─ 去重(SignatureIndex 内存索引,O(h))            │
│  ├─ reconcileWithStore / insertIncrementally 【4.4a】│ DTO│  ├─ 单事务写(background context)                  │
│  └─ mainContext 读:可见窗口 + delete/pin(仍主线程) │   │  └─ 发出 StoreEvent.added/merged/removed/ignored   │
│                                                    │   │ actor ImageProcessor 【BS-3 已接入】               │
│ @Observable HistoryItemDecorator(UI 状态)          │   │  ├─ ImageIO 降采样(CGImageSourceCreateThumbnail)   │
│  ├─ thumbnailImage/previewImage(就绪位图)          │   │  └─ 后台解码 + 缩略图/预览(预览封顶 800px)         │
│  └─ applicationImage(NSCache 限界 128)             │   │                                                    │
└────────────────────────────────────────────────────┘   └────────────────────────────────────────────────────┘
                  ▲                                                          │
                  │ AsyncStream<StoreEvent> → History.consume 增量更新       │
                  │ (不全量重排/重装饰)                                       │
```

### 1.3 隔离规则(全流程不变性)

- **跨 actor 载荷必须是 `Sendable`**(DTO/值类型/`Data`/`UUID`)。`@Model HistoryItem` / `HistoryItemContent` **不跨 actor**——跨边界前投影为 DTO(`ItemSnapshotDTO` 等,见 `Maccy/Ingest/Dtos.swift`)。
- **上下文线程归属**:`mainContext` 仅 main;`Storage.newBackgroundContext()`(`Storage+Background.swift:17`)仅所属 actor。**禁止跨域共用同一 context**。
- **单一真相源**:数据真相是 SwiftData(后台 context 单事务写);主线程 `@Observable` 是其投影。
- **主线程禁做重活**:`NSImage(data:)` 解码、resize、`NSAttributedString(rtf:/html:)`、SwiftData 重 fetch/save、正则、去重比对——禁止在 main(标题/富文本解析目前仍违反此规则,见 §2.1)。

### 1.4 已落地的 scaffolding(部分已接线)

| 文件 | 状态 |
|---|---|
| `Maccy/Ingest/Dtos.swift` | ✅ DTO 目录(`ContentDTO`/`ClipboardItemDTO`/`SignatureDTO`/`ItemSnapshotDTO`/`StoreEvent` 等)+ 投影函数 `snapshot(of:)` / `contentDTOs(of:)` |
| `Maccy/Ingest/SignatureIndex.swift` | ✅ 纯值去重索引 `[SignatureDTO: ItemID]`,接入 ingestor(BS-4.2) |
| `Maccy/Ingest/ClipboardIngestor.swift` | ✅ 已接入 live copy 路径(BS-2) |
| `Maccy/ImageProcessing/ImageProcessing.swift` + `ImageProcessor.swift` + `ImageDownsampler.swift` + `ThumbnailCache.swift` | ✅ ImageIO 降采样已接入(BS-3) |
| `Maccy/Persistence/Storage+Background.swift` | ⚠️ `newBackgroundContext()` 已用;**`VisibleWindowLoader.fetchWindow`(`:47`)是死代码——只有测试调用,从未接进 `History.load()`** |

---

## 2. 当前管线与瓶颈(逐模块)

> 标注:[已修]=已落地并 CI 绿;[部分]=核心做、收尾/测试缺;[未修]=未触碰;[死代码]=代码存在但零调用方。finding-id 见 §6 词汇表。

### 2.1 Clipboard / Ingest(复制摄取)

| 项 | 状态 | 说明 |
|---|---|---|
| pasteboard poll Timer 同步跑整条管线 | [已修] | `pasteboard-polling-callback-heavy`:Timer 现仅触发 `Task { await ingestor.ingest() }`,重活在 actor(`ClipboardIngestor.swift`) |
| 富文本/标题解析回主线程 | [未修] | `richtext-sync-decode-on-ingest` / `ClipboardIngestor.swift:144-150,225-235` 仍 `await MainActor.run { filterContents / title(for:) }`(Defaults + `NSAttributedString` 主线程亲和)。**这是 copy 路径上最后的主线程阻塞** |
| 去重全表 fetch | [已修] | `findsimilar-full-refetch`:live 路径改走 `SignatureIndex`(`O(h)` 命中候选数,非 `O(n)`)。legacy `History.findSimilarItem` / `History.add` **已不在生产路径**(死代码,见 §2.2) |
| 单复制多次 save | [已修] | `add-does-3-pending-changes-saves`:ingestor 单事务写后台 context |
| copy 风暴无合并 | [未修] | `no-coalesce-of-ingest-writes`:每个 `changeCount` 变化跑一次完整管线 |
| `shouldIgnore` 正则全在主线程 | [部分] | 正则缓存已 NSCache 限界(M5);匹配仍在 `filterContents` 主线程块 |
| Timer 无 tolerance / 非 common mode | [未修] | `timer-no-tolerance-mode` |

**live 摄取路径**(`ClipboardIngestor` → `History.consume` → `reconcileWithStore`):BS-4.4a 已增量(`model(for:)` + 二分插入),G-copy 实测 9.34→0.99ms。

### 2.2 History / Storage(加载与状态)

| 项 | 状态 | 说明 |
|---|---|---|
| `load()` 全表 fetch+排序+装饰在主线程 | [未修] | `load-no-pipeline-offload` / `load-fetch-all-no-predicate-limit-sort`:**`History.swift:218-219` 仍是裸 `FetchDescriptor<HistoryItem>()`**(无 `fetchLimit`/`sortBy`/`propertiesToFetch`/`returnsObjectsAsFaults`)。冷开 load() 实测 ~44–55ms。`VisibleWindowLoader` 已存在但**未接线**(最高 ROI 的 Swift 改动) |
| 插入时整表重排 | [已修] | `insert-resorts-whole-array`:增量 consume 用二分插入(`Sorter.BinaryInsertion.index`,`O(log n)`) |
| 容量裁剪多 save 风暴 | [部分] | `limit-multi-save-storm`:`limitHistorySize` 仍逐条 `delete()`(主上下文) |
| `withLogging` 每次 clear/delete 双 fetchCount | [未修] | `fetchcount-withLogging-on-every-mutation`:release 也跑 4 次 DB round-trip 纯诊断 |
| 模型索引缺失 | [未修] | `no-indexes-on-predicate-columns`:`pin`/`lastCopiedAt` 等高频列无索引 |
| legacy `findSimilarItem` / `History.add` | [死代码] | 已被 ingestor + `reconcileWithStore` 取代,但仍在源码中(应删/标 deprecated) |
| `Storage.mainContext` 从不 reset/refresh | [未修] | **内存滞留的结构性根因**(见 §4.2);不能直接 `reset()`(见 §4.3 陷阱) |

### 2.3 Search(文本搜索)

| 项 | 状态 | 说明 |
|---|---|---|
| 搜索 actor 化(off-main) | [已修] | `actor SearchActor`(`SearchActor.swift:31`)+ `searchGeneration` 生成代 guard + equality guard + destructive 失效(BS-5.6)。设计扎实、正确 |
| **07-F-010 高亮 UTF-16/grapheme 错位** | [未修] | commit `4fa4946` 声称 "bug-2 fix",但 `toGrapheneRange(in:)` **从未编写**;actor fuzzy-range 处理(`SearchActor.swift:132-135`)与 legacy `Search.swift:89-95` **逐字节相同** |
| **07-F-013 搜索/高亮截断不一致→静默丢高亮** | [未修] | 搜索截断 5000(fuzzy)/1000(regex),高亮截断 500(`AttributedString(title.shortened(to: 500))`),不同源无 `TextLimits`。正则命中在 600–1000 字符区间,`AttributedString.Index(within:)` 返回 nil 静默丢 |
| mixed 三遍无短路 | [未修] | `LT-SEARCH-02`:`mixedSearch` 仍 `simple→regexp→fuzzy` 三遍 |
| resize 在搜索热路径 | [未修] | `LT-MAIN-05`:`History.swift:824`/`:875` 同步 `needsResize = true` |
| `showSpecialSymbols` 全量重生成标题 | [未修] | `LT-MAIN-02`:`History.swift:192-198` 仍对全 `items` 调 `generateTitle()` |
| 截断单位不统一(grapheme vs byte) | [未修] | `LT-UTF8-01` / 07-F-012 |
| G-search 闸门 | [部分] | `TextSearchPerformanceTests` baseline-only、**直接测 legacy `Search()` 而非新 actor**,off-main 收益未被 CI 证明 |

### 2.4 Image(图片管线)

| 项 | 状态 | 说明 |
|---|---|---|
| 解码/缩略图/预览在主线程 | [已修] | `IMG-001/002/003/004`:BS-3 已用 `ImageProcessor` actor + `CGImageSourceCreateThumbnailAtIndex` 降采样,off-main |
| 预览封顶 800px | [已修] | BS-4.10(原 `visibleFrame` ~50MiB/张) |
| `imageData` 全表 fault | [部分] | `img-fullres-dup-storage`:BS-6 已 lazy(`HistoryItemDecorator.imageDataCache`),但**冷开仍会因 `load()` 全表 fault 而触发**;双份(blob+位图)问题在 `imageDataCache` 仍存 |
| `DecodedImageCache` | [死代码] | `MemoryGovernance.swift:61`:`setImage/image(for:)` **零调用方**,只有 `evict`/`purgeAll` 被调。"解码位图按可视区限界"核心目标**从未实现**,preview 位图仍 per-decorator 持有 |
| `releaseTransientImages(.previewHidden)` | [死代码] | 枚举 case 零调用方;`FloatingPanel.close()` 从不调 |
| `ApplicationImageCache` 无界字典 + fd DispatchSource | [已修] | `IMG-010/011`:NSCache 限界 128 + fd guard(M4) |
| `ColorImage` 主线程合成 | [已修] | `IMG-019`:NSCache 限界(M9) |
| 缩略图缓存键 FNV-1a | [部分] | `IMG-caching-key`:`ImageProcessor.thumbnail` 用 FNV;待统一 xxh3_64(已接入去重热路径,缓存键未切) |

> 已删除项:Vision OCR(图片项用空标题 `""`,2026-06-14)——`IMG-005/014/015/036` 与 `07-F-008` 全部 WONTFIX。

### 2.5 UI / 渲染

| 项 | 状态 | 说明 |
|---|---|---|
| 渲染风暴(动画→每帧 layout+CoreText 重测) | [已修] | 2026-06-26 修复:`titlePreviewLimit=1000` + `.middle` 截断放大;固定行高 + hover-no-scroll + preview cancel + 即时 snap+淡入 |
| 混合列表 layout 反馈风暴 | [已修] | `LazyVStack` layout-feedback(perf-mixed 394s hang)已修:固定行几何 + hover-no-scroll + preview cancel |
| `@unchecked Sendable` on HistoryItemDecorator/AppDelegate | [已修] | `IMG-035`/`historyitem-unchecked-sendable`:BS-7 实际归零(grep 0 标注),complete 模式 CI 绿 |
| `WrappingTextView` 双次 sizeThatFits | [未修] | `LT-RENDER-02` |
| `.drawingGroup()` 每行每重绘栅格化 | [部分] | `LT-RENDER-03`:依赖 `attributedTitle` 仅在 ranges 变时改(高亮 memoize 未做) |
| `updateUnpinnedShortcuts` 双遍赋值 | [未修] | `updateunpinned-double-pass` |

---

## 3. 数据安全

### 3.1 SwiftData pending-vs-saved 不对称(关键)

- **`fetch` 遵守 pending 改动**:带未保存改动的 fetch 会读到 in-memory 态。
- **`delete(model:where:)` 仅匹配已提交 store 状态**:predicate delete 不看 pending。
- **规则:任何 predicate delete 之前必须先 `save()`**,否则 predicate 与可见态不一致。`clear()` 的 `transaction { try? delete... }` 模式因内层 `try?` 吞错而**语义上不算事务**(07-F-014)。

### 3.2 单事务摄取

ingestor 一次复制只发**一个**后台 context 事务(insert + 去重合并 + 容量裁剪在同一事务)。失败的旧形态是单次复制最多 3 次独立 `processPendingChanges + save`(`add-does-3-pending-changes-saves`)。

### 3.3 仍未修的高危数据安全项

| finding-id | 位置 | 问题 |
|---|---|---|
| 07-F-001 | `Storage.swift:37-72` | `recoverContainer` 容器加载失败即**删 SQLite/WAL/SHM**(`removeStoreFiles`)——不可逆丢全部历史 |
| 07-F-002 / 07-F-003 | `History.swift` 多处 | 全局 `try?` 吞所有 save/delete/fetch 错误,内存态与磁盘态可能分叉 |
| 07-F-017 | `HistoryItem.swift:260-267` | `dataFromFileIfAllowed`:`try?` 取 fileSize 失败→`(fileSize ?? 0) <= cap` 恒真→无界文件 `Data(contentsOf:)` 可 OOM |
| 07-F-032 | `Collection+Surrounding.swift:18-32` | `item(before:)` 首元素 `offsetBy: -1` **运行时 trap**(可达:首项按 ↑) |
| 07-F-013 / 07-F-010 | `Search.swift` / `HistoryItemDecorator.swift` | 见 §2.3(正确性) |

### 3.4 正确代码(勿改)

`validUTF8PrefixLength`(`ClipboardByteProcessor.cpp:19-76`,完整 UTF-8 校验含 overlong/代理对/`>0x10FFFF` 拒绝);`fnv1a64`/`xxh3_64`(常数时间、无溢出);`dataLikelyEqual` 指纹命中后**仍跑 `lhs == rhs` 全比较**(碰撞安全,07-F-029);`@Relationship(deleteRule: .cascade)` 正确级联删 contents;`HistoryItemContent.maxValueSize` 在 ingest 封顶单 blob;`Search.isLikelyUnsafeRegularExpression` 拒嵌套量词正则。

---

## 4. 内存(2026-06-27 实测真相)

### 4.1 判定

| 目标 | 判定 | 依据 |
|---|---|---|
| **50 MB** | ❌ 不可能 | 框架不可压缩地板 ≈ **62 MB**(任何剪贴板内容之前)。50 MB 在地板之下 |
| **100 MB** | ❌ 不可达 | 地板 62 + 内容 blob + AG 图 + 缓存 + 窗口开 ~110–130MB 框架成本 |
| **现实稳态** | ~85–100 MB | 当前 6h dump=135MB,可再榨 ~20–35MB |

> 06-25 短启动(2 分钟)= 102MB 是**假信号**——掩盖了滞留斜率;6h 才暴露真实稳态 135MB 且仍在涨。leaks 仅 19KB(**不是泄漏**)。

### 4.2 滞留根因:`mainContext` 是进程级累积器,从不回收

机制(`docs/audit/2026-06-27-memory-floor-and-retention/03-retention-root-cause.md`):
1. `History.load()`(`History.swift:218`)裸 fetch 全表 → fault + 物质化全部 `HistoryItem`。
2. 读 `item.contents`/`item.imageData` 进一步 fault 每项的 `HistoryItemContent` 行 + `__DataStorage._bytes` blob。
3. **物质化后 `mainContext` 的行缓存(`_KKMDBackingData`)永久持有**——删除项的 `@Model` 从 store 移除了,但活动 `mainContext` 里物质化的行缓存**从不清理** → 单调增长。

heap 证据:624 个 `HistoryItemContent` + 624 个 `_KKMDBackingData`(对应 556 个 `__DataStorage._bytes` blob = **17.5 MB**);624/185 ≈ 3.4 内容/项,符合多类型结构(**不是孤儿,是全表 fault**)。Maccy 自己的模型对象仅 ~0.15MB——135MB 里 ~95% 是框架工作集 + 内容 blob + 视图图深度。

### 4.3 两个反直觉的坑

1. **`mainContext.reset()` 是陷阱**:会重新 fault 全表,直接退回冷开卡顿,并破坏增量 `consume` 路径(`decorator.item` 失效)。**别走这条捷径**回收 blob。
2. **SwiftData 没有单行 fault-out API**:`refresh` 是从 store 重填(更满),非清空。→ 光把 decorator 窗口化(C5)**释放不了底层 blob**。**F1(把大内容移出 SwiftData,独立 blob 存储按 id 索引)从"可选"升为"可能强制项"**——是唯一能在保持 `@Model` 身份的同时逐项回收 blob 的 sound 路径。

### 4.4 已落地(别再做)

`sessionLog`→`PersistentIdentifier`(M3,不再持 `@Model`);5 个无界缓存全 NSCache(ApplicationImageCache 128 / ignoredRegexps 64 / ColorImage 64+cost / ThumbnailCache 两层);`imageData` lazy(BS-6);HotKey + TIS 泄漏已修(M1/M2);`autoreleasepool`(M6);`MemoryGovernance` + `VisibilityTracker` + `releaseTransientImages`(C1/C2/C3);preview 系统改造(可配置尺寸/文本上限、即时 snap+淡入、previewed item 与 lead 选择解耦);U1 `.help` gate(唯一 UX-safe 内存 win)。

### 4.5 地板构成(为何 62MB 硬)

框架 `__TEXT`(首次触碰 COW 进程私有页,~45MB,**无法 evict**)+ 框架可写状态(~10MB)+ AttributeGraph 最小图(~5MB)+ libmalloc/zone/page table/Stack/IOAccelerator(~2MB)。41.7MB `non-object` 盲区主要(推断 ~66%,AG zone 占 109K 分配的 72K)是 **AttributeGraph 视图图节点体**——随已实现视图节点数线性增长,可减 ~30–45% 但留 ~17–20MB AG 不可减核。

### 4.6 待做(去重后真实 ~20–35MB,C5/C7/F1 共享 17.5MB blob 池**不能相加**)

1. 接入 `VisibleWindowLoader`(C5,load 全表→可见窗口):6–13MB,主杠杆(但见 §4.3 坑 2)
2. 延迟 `HistoryItem.contents` fault(C7):3–8MB
3. AttributeGraph 视图树瘦身:3–8MB(需 MallocStackLogging 实证 AG 占比)
4. 接通 `releaseTransientImages(.previewHidden)`(C6,代码已存在零调用):1–2MB(免费)
5. F1 独立 blob 存储(BS-8):把 blob 池压到 ~3–5MB 再省 ~8–12MB

**前置**:`MallocStackLogging=1` 重抓(D1,零代码),把 41.7MB 盲区从推断变实测。

---

## 5. 完成度一览(BS-0 → BS-8)

> 完成度以**源码现状**为准,非 commit message。**"路线图完成"是假象**——50 个小步骤勾选框全 `[ ]`,CI 绿 ≠ 规范做完。详见 `docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/`。

| 大步骤 | 完成度 | 状态 | 核心目标 | headline 缺口 |
|---|---|---|---|---|
| **BS-0** 安全 | 完成 | — | 数据安全基线 | — |
| **BS-1** 并发脚手架 | 完成 | — | DTO/actor/context 模型 | — |
| **BS-2** 摄取→actor | 完成 | — | copy 路径离主线程 | 标题/富文本仍回主线程 |
| **BS-3** 图片管线 | 完成 | — | ImageIO 降采样 off-main | 缩略图缓存键未切 xxh3 |
| **BS-4** 数据管线 | 部分 | ⚠️ | 增量 consume/reconcile | `load()` 仍全表 fetch;`VisibleWindowLoader` 死代码;`findSimilarItem`/`History.add` 死代码未删 |
| **BS-5** 文本搜索 | **2/13** | ❌ | off-main ✓(已达成) | **07-F-010 高亮错位 commit 夸大("bug-2 fix" 是空描述);07-F-013 静默丢高亮未修**;5.1/5.2/5.5/5.7/5.8/5.9/5.10 跳过;G-search 测 legacy 非 actor |
| **BS-6** 内存治理 | **5/12** | ❌ | decoded-image bounded to visible | **`DecodedImageCache` 死代码**(`setImage/image(for:)` 零调用);`.previewHidden` 死枚举;G-memory 闸门未建;6.11 测试套件 0/6 |
| **BS-7** Swift 6 | **13/17** | ⚠️ | complete 模式 CI 绿、零 @unchecked ✓(达成) | **7.13(唯一行为级改动)跳过**:`synchronizeItemPin/Title` 仍 recursive `withObservationTracking`+`DispatchQueue.main.async`;4 个测试文件缺;`Sorter`/`Throttler` 仍裸 class |
| **BS-8** C++/指纹 | **4/8** | ⚠️ | xxh3 接入 live 去重 ✓(达成) | **8.5 旧数据行 lazy backfill 缺失**(老行永远 nil,落回全量 `==`);8.3 桥加固丢弃(`enumerateByteRanges` 流式 08-F-004、UTF-8 防御 03-LT-CPP-01 未做);8.8 测试 0/4,FNV baseline 切换前未捕获 |

**系统性模式**:核心热路径做、外围正确性/限界/测试/文档勾选丢;偏差只记 commit message 或旁侧文档(违反 CLAUDE.md "记录偏差在 audit docs");规范要求 ~19 个新测试文件,实际只建 `SearchActorTests.swift` 一个。

### 5.1 优先级最高的补全(按价值/风险)

1. **BS-5 07-F-013**:对齐 highlight 与搜索截断到同一 `TextLimits`,越界改 clamp+log。
2. **BS-5 07-F-010**:写 emoji fuzzy 高亮落位断言,核实 Fuse 偏移语义;若 UTF-16 再补 `toGrapheneRange`,否则删夸大注释。
3. **BS-8 8.5 backfill**:补老数据行指纹回填。
4. **BS-6 `DecodedImageCache`**:要么接通要么删除死代码。
5. **BS-4 `VisibleWindowLoader` 接线**:load 全表→可见窗口(内存 §4.6 + load §2.2 双重收益)。

---

## 6. finding-id 词汇表

历史审计用三套 finding-id 前缀。下表给出含义 + 当前状态,供源码注释清理与未来读者解码。

### 6.1 `01-` / `04-`(并发/数据管线,kebab-case)

| finding-id | 含义 | 当前状态 |
|---|---|---|
| `load-no-pipeline-offload` | `load()` 全表 fetch+排序+装饰同步在主线程,无 limit/fault/batch | 未修(`History.swift:218`) |
| `findsimilar-full-refetch` | `findSimilarItem()` 每次复制重 fetch 全表 + O(n) 比对 | 死代码(live 走 SignatureIndex) |
| `pasteboard-polling-callback-heavy` | Timer 回调整条摄取管线同步在主线程 | 已修(actor) |
| `no-background-modelcontext` | 只有 mainContext,无后台 context/actor | 部分(后台 context 已用,load 仍 main) |
| `add-does-3-pending-changes-saves` | 单复制最多 3 次独立 save | 已修(单事务) |
| `limit-multi-save-storm` | 容量裁剪逐条 delete+save | 部分 |
| `insert-resorts-whole-array` | 插入时整表重排找插入点 | 已修(二分插入) |
| `search-throttle-still-runs-main` | 搜索 throttler 只合流,全量扫仍在主线程 | 已修(SearchActor) |
| `richtext-sync-decode-on-ingest` | `richText()` 同步 `NSAttributedString(rtf:/html:)` 在主线程 | 未修 |
| `decorator-init-main-decode-icon` | decorator init 同步解析 app icon | 已修(NSCache + lazy) |
| `historyitem-unchecked-sendable` / `appdelegate-unchecked-sendable` | `@unchecked Sendable` 掩盖可变状态 | 已修(BS-7 归零) |

### 6.2 `02-`(图片管线,IMG-###)

| finding-id | 含义 | 当前状态 |
|---|---|---|
| `IMG-001/002/003/004` | 解码/resize/预览超大/"async" Task 实为 @MainActor 全在主线程 | 已修(BS-3 ImageProcessor actor + ImageIO 降采样) |
| `IMG-005/014/015/036` | Vision OCR 主线程 | WONTFIX(OCR 删除) |
| `IMG-008` | 全分辨率 imageData + decodedImage + preview + thumbnail 同时持有 | 部分(imageData lazy;双份仍存) |
| `IMG-010/011` | per-bundle DispatchSource + 无界 ApplicationImageCache | 已修(NSCache 128 + fd guard) |
| `IMG-019` | `ColorImage.from` 每渲染合成 12x12 主线程 | 已修(NSCache) |
| `IMG-035` | `@unchecked Sendable` on decorator | 已修 |
| `img-fullres-dup-storage` | 全分辨率 imageData 在装饰器复制第二份(SwiftData 行内 + imageData) | 部分(lazy) |

### 6.3 `03-`(大文本,LT-###)

| finding-id | 含义 | 当前状态 |
|---|---|---|
| `LT-MAIN-01` | 同步去重扫 + 标题生成在主线程,per copy | 已修(live 走 actor) |
| `LT-MAIN-02` | `showSpecialSymbols` 切换重生成所有 item 标题(≥4 regex/replace 遍) | 未修 |
| `LT-MAIN-05` | resize 调度在搜索 throttle 块内 | 未修 |
| `LT-SEARCH-01` | 标题截断(5000/1000)静默藏匹配 + 截断点切 grapheme | 未修 |
| `LT-SEARCH-02` | mixed 三遍无短路 | 未修 |
| `LT-UTF8-01` | `shortened(to:)` 按 grapheme 切,与 byte 版 `stringPrefix` 单位不一致 | 未修 |
| `LT-CPP-02/03/07` | FNV-1a 慢 / 指纹非对称重算(lhs 每次重哈希)/ 哈希循环不可向量化 | 部分(BS-8 xxh3 + 持久化列修 03;缓存键未切) |
| `LT-CPP-01` | `index+width` 溢出 / `UInt(maxBytes)` 截断 | 未修(BS-8.3 丢弃) |
| `LT-RENDER-01/02/03` | AttributedString 逐键重建 / WrappingTextView 双测 / `.drawingGroup` 每行栅格化 | 部分/未修/部分 |

### 6.4 `07-`(数据安全,F-### / 07-F-###)

> 注:06-28 缺口审计用 `07-F-NNN` 前缀引用本组。下表是仍活跃的 finding。

| finding-id | 含义 | 当前状态 |
|---|---|---|
| `07-F-001` | `recoverContainer` 删 SQLite 文件丢数据 | 未修 |
| `07-F-002/003` | 全局 `try?` 吞 save/delete 错误 + save 失败仍保留 in-memory | 未修 |
| `07-F-008` | OCR Task fire-and-forget 改 `@Model` | WONTFIX(OCR 删除) |
| `07-F-010` | Fuse 返回 UTF-16 偏移,`index(offsetBy:)` 按 grapheme → emoji/CJK 高亮错位 | **未修(commit 夸大)** |
| `07-F-012` | `shortened(to:)` grapheme vs `stringPrefix` byte 单位不一致 | 未修 |
| `07-F-013` | highlight 截断 500 vs 搜索截断 5000/1000 → 匹配 >500 字符静默丢高亮 | **未修** |
| `07-F-014/015` | `clear()` 事务内 `try?` 吞错(非真事务)+ item/content predicate 不对称 | 未修 |
| `07-F-017` | `dataFromFileIfAllowed` fileSize `try?` 失败→恒真→无界文件 OOM | 未修 |
| `07-F-029` | FNV 非密码学哈希 | 安全(命中后仍跑全比较) |
| `07-F-032` | `item(before:)` 首元素 `offsetBy:-1` trap | 未修 |

### 6.5 `08-`(C++ interop,08-F-###)

| finding-id | 含义 | 当前状态 |
|---|---|---|
| `08-F-001` | lhs 指纹每次比对重算(非对称)→ dedup 优化失效 | 已修(BS-8.6 持久化列 + BS-8.5 懒回填 backfill,2026-07-03 CI 绿 run `28664372473`) |
| `08-F-004` | `data.bytes` 非连续 NSData 未流式(`enumerateByteRanges`) | 未修(BS-8.3 丢弃) |
| `08-F-009` | `dataLikelyEqual` 默认参数陷阱(lhsFingerprint 默认 nil) | 已修(BS-8.4 对称双指纹) |

### 6.6 缓存/内存杠杆代号(M/C/F/U/D 系列,06-27)

| 代号 | 含义 | 状态 |
|---|---|---|
| `M1/M2` | HotKey / TIS 泄漏 | 已修 |
| `M3` | `sessionLog` → `PersistentIdentifier` | 已修 |
| `M4/M5/M9` | ApplicationImageCache / ignoredRegexps / ColorImage NSCache | 已修 |
| `C1/C2/C3` | MemoryGovernance / VisibilityTracker / releaseTransientImages | 已修(框架) |
| `C5` | 接入 `VisibleWindowLoader`(load 全表→可见窗口) | **未做(死代码)** |
| `C6` | 接通 `releaseTransientImages(.previewHidden)` | **未做(死枚举)** |
| `C7` | 延迟 `HistoryItem.contents` fault | 未做 |
| `F1` | 大内容移出 SwiftData,独立 blob 存储(BS-8) | 未做(升为可能强制项) |
| `U1` | AttributeGraph 视图树瘦身 / `.help` gate | `.help` gate 已做;视图树瘦身未做 |
| `D1` | `MallocStackLogging=1` 重抓盲区归因 | 未做(前置) |

---

*本文档替代(非补充)2026-06-14 深度审查组(`00-overview`~`09-roadmap`)与 2026-06-25 模块分析组(`03-`~`07-module-analysis-*`)作为当前架构权威;两者将被删除。逐小步规范仍在 `2026-06-14/roadmap/step-X-*.md`,完成度审计在 `2026-06-28-roadmap-bs5-bs8-gap-audit/`,内存实测在 `2026-06-27-memory-floor-and-retention/`。*

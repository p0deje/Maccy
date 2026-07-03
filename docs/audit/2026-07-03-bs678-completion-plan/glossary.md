# 词汇表 — BS-6/7/8 完成工作(2026-07-03)

> 实施/注释时统一引用的术语与 finding-id。源:`architecture-and-root-causes.md` §6、`B/C` spec、本计划。

## 路线图术语

- **BS-x / 小步骤 (x.Y)**:大步骤 = 编译边界;小步骤 = 单 commit 单元。spec-of-record 在 `2026-06-14/roadmap/step-x-*.md`。
- **G-* 闸门**:性能闸门(`G-copy-text`/`G-search`/`G-memory`/`G-popup-open`/`G-copy-large-image`/`G-resident-open`),见 B §4。按 ADR-004 作 `PerformanceTestCase` 子类。
- **两域隔离**:Main(SwiftUI/@Observable/mainContext 读)↔ Background actor(ingest/image/search,后台 context 写)。跨域载荷必 `Sendable`;`@Model` 不跨域。见 `architecture-and-root-causes.md` §1.3。
- **DTO**:`ItemSnapshotDTO`/`ContentDTO`/`SignatureDTO`/`StoreEvent`/`MaccyFingerprint`(`Maccy/Ingest/Dtos.swift`)。
- **enable-testing**:`Maccy.xctestplan` 注入的 **CommandLine 参数**(非 env var、非 `enableTesting`),`#if DEBUG` 下强制 in-memory store(`Storage.swift:42,49-53`)。两个 test target 共享。
- **`PerformanceTestCase`**:`MaccyTests` 中 perf 测试基类(@MainActor;in-memory store;`Defaults[.size]=200`;持 `MainThreadProbe`;setUp/tearDown `clearAll()`)。
- **`MainThreadProbe`**:后线程发主线程 `sync` 探针,采样主线程占用;经 `withCheckedContinuation` sentinel 排空主队列(非 `Task.yield`/`RunLoop.run`)。

## finding-id(实施注释引用)

### 数据安全(07-F-###)
- `07-F-001`:lhs 指纹每次比对重算 → dedup 优化失效。**已修(8.6 持久化列)**;8.5 backfill 补旧行。
- `07-F-009`:`dataLikelyEqual` 默认参数陷阱(lhsFp 默认 nil)。**已修(8.4 对称双指纹)**。
- `07-F-012`:`shortened(to:)` grapheme vs `stringPrefix` byte 单位不一致(BS-5 范畴)。
- `07-F-013`/`07-F-010`:搜索/高亮截断不一致 / Fuse UTF-16 错位(BS-5 范畴,本计划不涉)。
- `07-F-017`:`dataFromFileIfAllowed` fileSize `try?` 失败→恒真→无界 OOM(不在 BS-6/7/8)。
- `07-F-029`:FNV 非密码学哈希 → 命中后仍跑全比较(安全)。**正确,勿改**。
- SwiftData pending-vs-saved:`fetch` 遵 pending;`delete(model:where:)` 仅匹配 committed → predicate delete 前必 `save()`。**8.5 backfill 必守**。

### C++ interop(08-F-###)
- `08-F-001`:同 07-F-001。**已修**。
- `08-F-002`/`08-F-003`:FNV 弱雪崩 / 串行不可向量化。**已修(8.2 xxh3)**。
- `08-F-004`:桥 `data.bytes` 非连续 NSData 未流式(`enumerateByteRanges`+`XXH3_64bits_update`)。**未修(8.3,记 accepted-risk)**。
- `08-F-008`:桥空/连续性契约。**部分(8.3 加防御 guard)**。
- `08-F-009`:同 07-F-009。**已修**。
- `08-F-012`:UTF-8 状态机(`validUTF8PrefixLength`,`.cpp:19-76`)全边界验证正确。**勿改**(8.3 仅防御性重写 `.cpp:70`)。
- `03-LT-CPP-01`:`index+width>limit` → `width>limit-index` 防御重写。**8.3 做(cosmetic)**。

### 内存杠杆(M/C/F/U/D 系列,06-27)
- `M3`/`M4`/`M5`/`M9`:sessionLog→PersistentIdentifier / ApplicationImageCache NSCache / ignoredRegexps NSCache / ColorImage NSCache。**已修**。
- `C1`/`C2`/`C3`:MemoryGovernance / VisibilityTracker / releaseTransientImages。**框架已落地**。
- `C5`:接入 `VisibleWindowLoader`(load 全表→可见窗口)。**未做(死代码,06-27 DROPPED as 内存杠杆)**。
- `C6`:接通 `releaseTransientImages(.previewHidden)` / DecodedImageCache。**ADR-001 = 接通 DecodedImageCache;`.previewHidden` 在 6.7 接线**。
- `C7`:延迟 `HistoryItem.contents` fault。未做(不在 BS-6/7/8 补全范围)。
- `F1`:大内容移出 SwiftData 独立 blob 存储。未做(06-27 升为可能强制项,独立大步骤)。
- `U1`:`.help` gate AG 视图树瘦身。`.help` gate 已做。
- `D1`:`MallocStackLogging=1` 重抓盲区归因。未做(前置)。

### Swift 6(06-F## / 7.x)
- `06-F01`/`06-F02`:decorator/AppDelegate `@unchecked Sendable`。**已修(7.3)**。
- `06-F09`:递归 `withObservationTracking` 自重装。**7.13(ADR-003)目标**。
- `06-F17`:ApplicationImage `DispatchSource` 隔离。**7.4 目标(`.global()`→`.main`)**。
- `06-F26`-`06-F29`:Selection/KeyShortcut/Throttler/SearchResult Sendable。**7.11 目标**。

## 不变性(实施时勿违反)

- **跨 actor 载荷 Sendable**;**`@Model` 不跨域**。
- **主线程无 >16ms 同步重活**(解码/hash/正则/富文本/SwiftData 重 fetch)。
- **指纹 seed 固定**(`kMaccyHashSeed=0`):任何 per-process 随机 seed 会**使所有持久化指纹失效**。需加跨启动稳定测试。
- **`dataLikelyEqual` 末尾保留 `lhs == rhs`**(碰撞安全)。
- **`validUTF8PrefixLength` 算法不改**(08-F-012 正确);8.3 仅 `.cpp:70` 防御重写。

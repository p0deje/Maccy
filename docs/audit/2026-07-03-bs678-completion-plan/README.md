# BS-6/7/8 完成计划(2026-07-03,grill-with-docs 产物)

> **本文件是 BS-6/7/8 "补全到 spec" 的执行计划**,由 `/grill-with-docs` 会话产出。
> 基线:HEAD `8e0ba2c`。完成度判定以**当前源码**为准(4-agent 验证,非 commit message)。
> 配套:`decisions.md`(4 个 ADR)、`glossary.md`(术语/finding-id 词汇)。
> 上游权威:`docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/`(缺口)、`docs/audit/2026-06-14/roadmap/step-{6,7,8}-*.md`(冻结 spec)、`docs/audit/architecture-and-root-causes.md`(架构)。

## ⚠️ 代理决策声明(用户离席期间做出)

会话中提出 4 个真实决策叉点(`DecodedImageCache` connect/delete、8.5 backfill 方案、7.13 obs 收敛、perf target)。用户 60s 未回应,我按上下文最佳判断代为决定并记入 `decisions.md`。**实施前可推翻(改 ADR 即可);实施后推翻成本升高。** 用户回归后请优先复核 `decisions.md`。

代为结论:① DecodedImageCache **接通**(ADR-001);② 8.5 **惰性 signal-to-actor 回填**(ADR-002);③ 7.13 **computed-mirror,TDD 闸门**(ADR-003);④ perf 闸门 **按 perf-as-class 落到 MaccyTests,不建独立 target**(ADR-004)。

## 实时进度日志(Progress Log)

> 随每步 CI 绿实时追加;commit 历史是另一条真相源。逐步勾选见 step-X 文档。

- **2026-07-03** ✅ **BS-8.5 fingerprint 懒回填 backfill** — CI 绿(run `28664372473`,10/10)。`BackgroundClipboardIngestor.findDuplicate` 候选获取时于后台 context 回填 nil 列大行,搭 `commit` 单事务 save、幂等、按命中。设计比 ADR-002 预期简单(去重全在后台 context,无 mainContext refresh)。`FingerprintMigrationTests`(4 测试)覆盖。
- **2026-07-03** ✅ **BS-8.8(部分)`DataLikelyEqualContractTests`** — CI 绿,锁对称契约(08-F-009)+ 固定种子不变量。
- **2026-07-03** ✅ **BS-8.3 ObjC++ 桥防御加固** — `.cpp:70` UTF-8 bound check 改 overflow-safe(语义等价);`.mm` 两方法加 DEBUG `NSCAssert` 守 NSData 契约;`MaccyTextProcessorTests` 锁 UTF-8 边界回归(08-F-012 全用例)+ 空 fingerprint 稳定性。偏离:streaming(08-F-004 accepted-risk)、POD struct/deprecation N/A(UInt64 单方法设计)。
- **2026-07-03** ✅ **BS-8.7 残留清理(doc-only)** — modulemap 延后(bridging header 保留,记 step-7 待办);`@retroactive Sendable` N/A(UInt64 POD);deprecation N/A。
- **2026-07-03** ✅ **BS-8.8 测试补全** — `DataLikelyEqualContractTests`、`FingerprintMigrationTests`(4)、`MaccyTextProcessorTests`(10)、`FingerprintSymmetryTests`。`Xxh3ThroughputTests` **不单建**:xxh3 吞吐已由既有 `testFingerprintThroughputBenchmark`(1MiB+10MiB `measure`)覆盖;FNV baseline 不可恢复(fnv1a64 未桥接 Swift,合成会误导),记 accepted deviation。
- **2026-07-03** ✅ **BS-8 CI GREEN**(run `28666589524`,10/10)— BS-8 完成并验证。
- **2026-07-03** ✅ **BS-7.11/7.15 完成** — `SearchResult`/`Selection` `: Sendable`(Selection 条件 `Item: Sendable`);`Sorter`/`Throttler` `@MainActor final class`;删 36 冗余 per-method `@MainActor`(保留 17 load-bearing:type-level ×2 + 协议 8 + struct 8)。
- **2026-07-03** ✅ **BS-7.17 `SendableBoundaryTests`** — `[any Sendable.Type]` 数组编译期断言,锁跨 actor DTO 边界。`ClipboardIsolationTests`/`AppIntentDtoTests` 延后(低价值 characterization)。
- **2026-07-03** ✅ **BS-7 CI GREEN**(run `28667853065`,10/10)— BS-7 完成并验证。
- **2026-07-03** ⚠️→✅ **BS-6.2/6.4 DecodedImageCache — DELETE**(ADR-001 修订:深入分析显示接通会增加内存 vs 当前可视区限界,仅换边际 re-show,与 06-27 冲突;避免触及预览路径)— 删除 `DecodedImageCache` + 死 `.previewHidden` + 无操作 evict/purgeAll。保留 per-decorator previewImage + scrollOut 释放 + BS-3 封顶。
- **2026-07-03** ✅ **BS-6.3/6.11** — `handleMemoryWarning` 实际完成(thumbnail/regexp NSCache 自动 evict,显式 purge 冗余,记偏差);`ApplicationImageCacheTests`(缓存复用/fallback/purge)。`MemoryGovernanceTests`/`SessionLogReleaseTests` 延后(复杂 setup)。
- **2026-07-03** 🔄 **BS-6 pending CI + 6.12 G-memory 决定**(perf-as-class 或按 06-27 retire)。**注意**:DecodedImageCache 的 DELETE 是用户离席期间代为决定(易回退)。下一步 BS-6 收尾(#15)。
- **2026-07-03** ✅ **BS-6.12 G-memory gate retired per 06-27** — 实测框架底 ~62MB 使 <300MiB 近平凡;CI 内存测量噪声大,可靠 gate 难建;内存回归走 06-27 D1 MallocStackLogging 手动 profile 协议,不建 CI gate。

## 一、验证后真值(HEAD `8e0ba2c`,re-grep 后)

行号已因 `0318705`(注释标准化)整体下移;下列均为 `8e0ba2c` 当前值。

### BS-6 — 4 done / 6 partial / 2 skipped(审计称 5/12;**6.8 收紧 done→partial**)

| 步 | 状态 | 当前源码证据(`8e0ba2c`) | 缺口 |
|---|---|---|---|
| 6.1 VisibilityTracker | ✅ | `MemoryGovernance.swift:31-60`;`HistoryItemView.swift:51-58` 接线 | — |
| 6.2 DecodedImageCache | ⚠️ partial | `MemoryGovernance.swift:62-91`;`setImage(`/`image(for:` **0 调用方**;仅 `evict`(装饰器 :232,:245)+`purgeAll`(:138)被调 | **死代码**(ADR-001) |
| 6.3 MemoryGovernor | ⚠️ partial | `MemoryGovernance.swift:133-140` `handleMemoryWarning` 仅 3/5 步 | 缺 ThumbnailCache 内存清 + 正则缓存清 |
| 6.4 装饰器去双份 | ⚠️ partial | `HistoryItemDecorator.swift:79,95-103,339-373`;`imageData` 已 lazy、`decodedImage` 字段已删;预览位图**未进 NSCache**;`sizeImages()`(:280-284)未删 | 同 6.2 |
| 6.5 sessionLog | ✅ | `History.swift:159-161`(`[Int: PersistentIdentifier]`) | — |
| 6.6 ApplicationImageCache | ✅ | `ApplicationImageCache.swift:13-42`;fd guard `ApplicationImage.swift:62-106` | — |
| 6.7 接线/onDisappear | ⚠️ partial | `HistoryItemView.swift:51-58` scroll-out 已接;`.previewHidden`(**HistoryItemDecorator.swift:233**)**0 调用方** | 死枚举 |
| 6.8 RegexpCache | ⚠️ partial(**收紧**) | `Clipboard.swift:17-21,315-343` 内联 NSCache(countLimit=64)生效;**无 RegexpCache 类型、无 `Defaults.updates(.ignoreRegexp)` 重建、无 `purgeStale`** | 缺重建循环(陈旧 pattern 不立即 drop) |
| 6.9 ColorSwatchCache | ✅ | `ColorImage.swift:14-42` 内联 NSCache | — |
| 6.10 obs 重注册(minor) | ⏭️ skipped | `HistoryItemDecorator.swift:416-454` 仍递归 | 诚实延后(06-27 已记 C4 low-value) |
| 6.11 测试 | ⏭️ skipped | 6 个 spec 文件全缺 | 全补(见测试清单) |
| 6.12 验证/G-memory | ⚠️ partial | CI 绿;`MaccyPerformanceTests` target 不存在 | ADR-004 |

### BS-7 — 12 done / 3 partial / 1 skipped / 1 superseded(审计称 13/17)

| 步 | 状态 | 证据 | 缺口 |
|---|---|---|---|
| 7.1‑7.3 | ✅ | `project.pbxproj:1821-1822` 等 6 段 `6.0+complete`;grep `@unchecked Sendable\|nonisolated(unsafe)` 仅 5 处注释、**0 实际标注** | — |
| 7.4 ApplicationImage | ⚠️ partial | `ApplicationImage.swift:80`(`queue:.global()`)+`:83`(内层 `DispatchQueue.main.async`) | 改 `.main`、删内层 hop |
| 7.5‑7.10 | ✅/🔄 | sessionLog=`PersistentIdentifier`;AppIntent `@MainActor perform()`;`OnNewCopyHook` 已删;`SendableWrappers.swift` 合理未建(7.10 superseded) | — |
| 7.11 值类型 Sendable | ⚠️ partial | `Search.swift:32`(`SearchResult` 无 `:Sendable`)、`Selection.swift:4`、`KeyShortcut.swift:6`、`Sorter.swift:8`(裸 class)、`Throttler.swift:6`(裸 class) | 补标注 |
| 7.12 AppIntent | ✅ | `Delete/Get/Select.swift @MainActor perform()`;`Clear` await | — |
| 7.13 obs 收敛 | ⏭️ skipped | `HistoryItemDecorator.swift:416-454` + `AppDelegate.swift:245-259` 仍递归 `withObservationTracking`+`main.async` | **唯一行为变更**(ADR-003) |
| 7.14 entitlements | ✅ | — | — |
| 7.15 冗余 @MainActor | ⚠️ partial(**审计多算**) | 真实冗余 **36**(装饰器 12:`146,163,178,196,210,217,225,251,256,271,280,405`;History 类 24:见下)。审计的 "52" 含 `HistoryPersistence` 协议(8,`:12-26`)与 `SwiftDataHistoryPersistence` struct(8,`:33-86`)的 **load-bearing** 标注 —— **必须保留** | 删 36,留 16 |
| 7.16 C++ 标准 | ✅ | `project.pbxproj:1912,1975` `gnu++17` | — |
| 7.17 全量验证 | ✅(build) | complete 模式 CI 绿 | 4 测试文件缺(见测试清单) |

History 类 24 个冗余 per-method `@MainActor`:`232,249,259,271,313,331,369,388,426,457,481,506,540,571,598,612,651,691,732,742,774,793,803,959`。

### BS-8 — 4 done / 4 partial(与审计一致)

| 步 | 状态 | 证据 | 缺口 |
|---|---|---|---|
| 8.1 基线 | ✅ | `HistoryItemPerformanceTests.swift:28-43,47-55` | FNV baseline 切换前未捕(不可逆过程缺口,记 doc) |
| 8.2 xxh3 | ✅ | `third_party/xxhash.h`;`ClipboardByteProcessor.cpp:110-111`(xxh3_64);`kMaccyHashSeed=0` **固定**(`.mm:10`,持久化关键不变量正确) | — |
| 8.3 桥加固 | ⚠️ partial | `.mm:29` 仍 `data.bytes` 直传(无 `enumerateByteRanges`/`XXH3_64bits_update`);`.cpp:70` 仍 `index+width>limit`;无 empty guard/DEBUG assert;无 `__attribute__((deprecated))` | 防御项(详见 8.3 步) |
| 8.4 dataLikelyEqual | ✅(smaller) | `ClipboardDataProcessor.swift:48-70` 对称、双指纹必填、末尾 `lhs==rhs` 兜底 | UInt64 vs MaccyFingerprint 为 cosmetic 偏差(记 doc) |
| 8.5 backfill | ⚠️ partial(**确认**) | `HistoryItemContent.swift:33,41`(init 只赋新行);全仓 `.fingerprint =` grep **无任何回写旧 nil 行**;`HistoryItemEngine.swift:129-130`(ContentSignature 回退重 hash)、`:155`(ContentIndex 直接带 nil → 全 `==`) | **正确性退化**(ADR-002) |
| 8.6 ContentSignature/Index | ✅(smaller) | `HistoryItemEngine.swift:129,141,184-186` 读列 + 双向 DTO | — |
| 8.7 残留清理 | ⚠️ partial | 无 modulemap、无 deprecation、无 `@retroactive Sendable`(均因 UInt64 单方法设计而 N/A) | doc-only |
| 8.8 测试 | ⚠️ partial | 0/4 文件;无 `.baseline`/`xxh3>=3x`/`bytesHashed≈0` 断言 | 全补(见测试清单) |

## 二、测试清单(已有 vs 待补;去重后真实缺口)

**已有且可复用**(不重建):`PasteboardSimulator`/`HistoryBuilder`/`FakeClock`/`IngestorSpy`/`FixtureLoader`/`MainThreadProbe`(Support/ 全 real);`ThumbnailCacheTests`、`ImageProcessorTests`、`ImageDownsamplerTests`、`ImageProcessingContractTests`、`ImageDecodePerformanceTests`、`ColorImageTests`、`SearchActorTests`(15 法)、`SearchTests`、`TextSearchPerformanceTests`、`SignatureIndexTests`(23 法/337L,synthetic 指纹,**缺列读不变量**)、`HistoryConsumeTests`、`BackgroundClipboardIngestorTests`(12 法/550L)、`ClipboardIngestorTests`、`HistoryItemPerformanceTests`、`StorageBackgroundContextTests`、`DtoRoundTripTests`/`DtoTests`、`PerformanceTestCase` 基类。

**待补(仅未填的验收点)**:

| 文件 | 步 | 关键断言(failing-first) |
|---|---|---|
| `DataLikelyEqualContractTests` | 8.8 | size gate / 16KiB 阈界 / 碰撞→`==` / 双指纹必填(锁 08-F-009, GREEN) |
| `FingerprintMigrationTests` | 8.5 | nil 列大行→回填后非 nil;回填行与新建行 dedup-equal;幂等;<16KiB 不动 |
| `FingerprintSymmetryTests` | 8.8 | `bytesHashed` 不随 lhs 数线性增长(08-F-001 热路径) |
| `Xxh3ThroughputTests` | 8.8 | 10MB measure + `.baseline`;合成 FNV baseline(测桥调保留的 `fnv1a64`);`xxh3>=3x` |
| `SignatureIndexTests`(扩) | 8.6 | `testLhsFingerprintReadFromColumnNotRehashed`(断言列读,非每比较重算) |
| `SendableBoundaryTests` | 7.17 | DTO 经 `@Sendable` 探针无 trap(`ItemSnapshotDTO`/`ContentDTO`/`StoreEvent`) |
| `ObservationMirrorTests` | 7.13 | 1ms 内 100 次突变,断言最终态 = @Model(7.13 闸门) |
| `ClipboardIsolationTests` | 7.17 | `checkForChangesInPasteboard` 在 main(`MainThreadProbe`) |
| `AppIntentDtoTests` | 7.17 | Get/Delete/Select/Clear `perform()` DTO = 直接 @Model 读 |
| `DecodedImageCacheTests` | 6.2 | countLimit/totalCostLimit 淘汰;evict/purgeAll;读 API(接通前锁) |
| `MemoryGovernanceTests` | 6.3/6.11 | `handleMemoryWarning` 5 步全清;非可视区释放;可视区不动;scroll-out 后重建 |
| `ApplicationImageCacheTests` | 6.6/6.11 | countLimit=128;purge 触发 `deinit` cancel;fd guard |
| `SessionLogReleaseTests` | 6.5/6.11 | delete 移除 sessionLog 条目;add→isModified 仍命中 |
| (perf) `G-memory`/`G-search` 子类 | 6.12/BS-5 | `PerformanceTestCase` 子类(ADR-004) |

## 三、实施序列(按风险/价值;每小步独立 commit;每大步 CI gate)

> 序:**BS-8(正确性优先)→ BS-7(隔离收尾)→ BS-6(预览路径,测试闸门最重)**。
> fork 无关项先行;fork 相关项(6.2/8.5/7.13)在用户确认 ADR 后做。

### BS-8
1. **8.8 `DataLikelyEqualContractTests`** — GREEN,锁对称契约(决策无关,首步)。`MaccyTests/DataLikelyEqualContractTests.swift`。
2. **8.5 backfill**(ADR-002,fork 相关)— `FingerprintMigrationTests`(failing)+ 惰性 signal-to-actor 回填。插入点:ingest actor 后台 context 写列;main 读侧收集 nil 大行 persistentID 后投递。详见 decisions.md。
3. **8.8 `FingerprintSymmetryTests`** — `bytesHashed` 不随 lhs 线性增长(需 IngestorSpy metrics,先核 metrics 钩子)。
4. **8.8 `Xxh3ThroughputTests`** — 合成 FNV baseline(测桥调 `fnv1a64`)。
5. **8.3 防御加固** — `.mm` empty guard + DEBUG assert;`.cpp:70` `index+width>limit`→`width>limit-index`;streaming(08-F-004)记 accepted-risk 偏差。
6. **8.7 doc-only** — modulemap 延后记 step-7;deprecation/Sendable 记 N/A 于 step-8。
7. 更新 `step-8-cpp.md` 勾选(4✓ 4⚠)+ 偏差注释(UInt64 DTO、FNV baseline 丢失、streaming accepted)。
8. **BS-8 CI gate**(push、~11min、poll ≤每 2min)。

### BS-7
1. **7.4** — `ApplicationImage.swift:80` 改 `queue:.main`,删 `:83` 内层 hop。
2. **7.11** — `SearchResult`/`Selection`/`KeyShortcut` `:Sendable`(Selection 加 `where Item: Sendable`,先 grep 全 `Selection<` 实例);`Sorter`/`Throttler` `@MainActor final class`。
3. **7.15** — 删 36 个冗余 per-method `@MainActor`(装饰器 12 + History 类 24);**保留**协议 8 + struct 8。
4. **7.13**(ADR-003,fork 相关)— `ObservationMirrorTests`(failing 闸门)→ 若 @Observable→@Model 传播则 computed-mirror,否则 AsyncStream 回退。
5. **7.17 测试** — `SendableBoundaryTests`/`ClipboardIsolationTests`/`AppIntentDtoTests`。
6. 更新 `step-7-swift6.md` 勾选(12✓ 3⚠ 1⏭ 1🔄)+ 偏差。
7. **BS-7 CI gate**。

### BS-6
1. **6.2**(ADR-001,fork 相关)— `DecodedImageCacheTests`(failing)→ 接通:`startPreviewGeneration`(`HistoryItemDecorator.swift:339-373`)decode 后 `setImage`;`ensurePreviewImage` 读侧先查 `image(for:)`。
2. **6.3** — `handleMemoryWarning` 补 ThumbnailCache 内存清(actor,async `Task`) + 正则缓存清(Clipboard 暴露 purge 钩子)。
3. **6.4** — 删 `sizeImages()` 或记 intentional-retention;清理因 6.2 接通后多余的 evict 调用。
4. **6.7** — `.previewHidden` 在预览关闭边界接线(定位真实 dismiss 点:`NavigationManager.leadHistoryItem` didSet? 已 cancelPreviewGeneration 处)或并入 6.2。
5. **6.8** — 加 `Defaults.updates(.ignoreRegexp)` 重建循环(陈旧 pattern 即时 drop);记 inline-RegexpCache 偏差。
6. **6.11 测试** — `MemoryGovernanceTests`/`ApplicationImageCacheTests`/`SessionLogReleaseTests`(RegexpCache/ColorSwatch 经 Clipboard/ColorImage 内联测)。
7. **6.12**(ADR-004)— `G-memory` 作 `PerformanceTestCase` 子类,或按 06-27 retire 并记偏差。
8. 更新 `step-6-memory.md` 勾选(4✓ 6⚠ 2⏭)+ 偏差(DecodedImageCache、VisibleWindowLoader dropped、06-27 floor)。
9. **BS-6 CI gate**。

## 四、执行规则(继承 CLAUDE.md)

- 无本地工具链:不本地 build/test/swiftlint。每大步 push CI 验证(~11min,poll ≤每 2min)。
- TDD:行为变更先写 failing 测试,再最小正确改动。无本地运行时,测试+实现同 commit,CI 验证(推理测试在无实现时会失败)。
- 一小步一 commit;消息含 roadmap 项(`feat(bs8.5): ...`/`test(bs7.17): ...`/`docs(bs6.2): ...`)。仅大步边界 push。
- 偏差先记 audit docs(step-X + 本目录 decisions.md)再 commit。
- 勿改用户可见行为,除非 spec 要求。

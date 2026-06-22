# B — 测试策略与数据流抽象

每个大步骤引用本文的**测试设施**与**数据流抽象**。原则:TDD 引导新模块;纯函数优先(易测);性能闸门守卫主线程预算。

## 1. 测试金字塔

| 层 | 范围 | 工具 | 速度 |
|---|---|---|---|
| 单元(纯函数) | UTF-8 前缀、指纹、签名比对、降采样数学、截断/单位换算、排序键 | `XCTest` | ms |
| 模块(actor/store) | `ClipboardIngestor` 端到端(含模拟 pasteboard)、`ImageProcessor`、`SignatureIndex` | `XCTest` + doubles | ms–s |
| 集成 | actor→main 投影→observable 一致性 | `XCTest`(in-memory store) | s |
| 性能闸门 | 主线程时延、内存峰值 | `XCTMetric`/`OSSignposter` + fixture | s |

> 新增纯逻辑(`SignatureIndex`、`ImageDownsampler`、指纹)**先写失败单测**;actor/store 用 doubles 写**契约测试**;**禁止**把 SwiftData 真库作为唯一验证手段。

## 2. Test Doubles / Fixtures(新增到 `MaccyTests/Support/`)

| 设施 | 路径 | 职责 |
|---|---|---|
| `PasteboardSimulator` | `Support/PasteboardSimulator.swift` | 注入 `changeCount` 与 `[(type, Data)]`;替代真 `NSPasteboard` |
| `HistoryBuilder` | `Support/HistoryBuilder.swift` | 流式构造 `[HistoryItem]`(in-memory store),支持图片/文本/富文本/超大 |
| `FakeClock` | `Support/FakeClock.swift` | 控制 `firstCopiedAt/lastCopiedAt`,测排序与去重合并 |
| `MockHistoryStore` / `IngestorSpy` | `Support/IngestorSpy.swift` | 记录 `ingest()` 调用与返回 `StoreEvent`;验证不触主线程重活 |
| `FixtureLoader` | `Support/FixtureLoader.swift` | 加载 `heavy_text.txt`、合成图片(small/medium/large/edge) |
| `MainThreadProbe` | `Support/MainThreadProbe.swift` | 在后台发主线程 `sync` 探针,采样主线程占用比(性能闸门用) |

### Fixtures(数据形状,覆盖边界)
- 文本:`empty`、`1B`、`ascii_1k`、`utf8_cjk_2k`、`emoji_grapheme_mix`、`heavy_text.txt(31KB)`、`huge_1MB`、`malformed_utf8(截断多字节)`。
- 图片:`png_1x1`、`jpeg_small(64²)`、`screenshot_1440x900`、`photo_12mp`、`heic`、`corrupt_truncated`。
- 富文本:`rtf_small`、`html_small`、`rtf_huge(>512KB)`。
- 边界:`maxValueSize_boundary(恰好/超 1B)`、`multi_pasteboard_item_merge`、`file_url_invalid`。

> `heavy_text.txt` 当前**无测试引用**(`03` Bench-1)。本路线图将其纳入 `FixtureLoader` 并加 CJK/emoji 用例(原基准仅 ASCII)。

## 3. 数据流抽象(IngestRequest / IngestResult)

把"摄取"建模为**纯数据变换 + 副作用分离**,便于离线单测:

```
IngestRequest  = { source: PasteboardSource, items: [(type, Data)], application: String?, now: Date }
                 │ (Sendable;不含 AppKit/SwiftData 引用)
                 ▼  纯函数:ClipboardIngestor.materialize(request, signatureIndex) -> IngestPlan
IngestPlan     = { action: .create(ContentDTOs) | .merge(existingID, ContentDTOs) | .ignore(reason) }
                 │ (决定动作,不触碰 DB/UI)
                 ▼  副作用:ClipboardIngestor.commit(plan, bgContext) -> IngestResult
IngestResult   = { event: StoreEvent, metrics: { dedupHits, bytesHashed, parseMs } }
```

- `materialize` 是**纯函数**(可单测去重逻辑、单位换算、忽略规则,无需 DB)。
- `commit` 是**唯一副作用点**(后台 context 单事务);用 `IngestorSpy` 验证调用与错误传播。
- `metrics` 喂给性能闸门(断言 `bytesHashed` 在指纹持久化后趋近 0)。

### 关键契约测试(每个大步骤补)
- 去重正确性:相同内容 `.merge`;等价但不同字节(经指纹)行为一致;超 `maxValueSize` 丢弃单 blob 而非整条。
- UTF-8 安全:`malformed_utf8` 不产生半 codepoint;截断点落在 codepoint 边界。
- 截断单位:`grapheme` 与 `byte` 路径不混用(`03-LT-UTF8-01`/`07-F-012`)。
- 主线程纯净性:`ingest`/`search`/`image decode` 不在 main(用 `MainThreadProbe` 断言)。
- 事件一致性:`StoreEvent` 应用后,`items` 与后台 store 计数一致(随机化操作序列,属性测试)。

## 4. 性能闸门(主线程预算)

| 闸门 | 场景 | 预算(目标) | 失败动作 |
|---|---|---|---|
| `G-popup-open` | history=1000,**冷启动** `load()` 到首屏(D1 域) | 主线程占用 < 50ms(目标 < 16ms) | 阻塞合并 |
| `G-resident-open` | app 已 warm,热键等价打开→首帧(**D2 渲染链**,不含 load) | 主线程 < 16ms(目标) | 阻塞合并(4.10) |
| `G-copy-large-image` | 复制 12MP 图,到可预览 | 主线程无 >16ms 段 | 阻塞合并 |
| `G-copy-text` | 复制 `heavy_text.txt` | 主线程 < 16ms;`bytesHashed` 趋 0(指纹持久化后) | 阻塞合并 |
| `G-search` | history=1000,逐键搜索 | 主线程 < 16ms/键;后台 actor 承担 | 阻塞合并 |
| `G-memory` | 浏览+预览 5min | 常驻 < 300MiB(目标从 ~GB 级降) | 阻塞合并 |

测量:`XCTest` 的 `measure(metrics:[XCTClockMetric(), XCTMemoryMetric()])` + `OSSignposter` 标记区间;`MainThreadProbe` 采主线程占用比。闸门以**独立 target**(`MaccyPerformanceTests`)运行,默认 CI 非阻塞,改性能 PR 须绿。

## 5. 覆盖矩阵(finding → 测试)

| Finding | 覆盖测试/闸门 |
|---|---|
| `07-F-032`(首项 ↑ trap) | `CollectionSurroundingTests.before_firstItem_returnsNil` |
| `07-F-001`(删库) | `StorageRecoveryTests.failure_movesToQuarantine_notDelete` |
| `07-F-002/003`(吞错) | `IngestErrorPropagationTests.saveFailure_surfacesError` |
| `08-F-001`(指纹非对称) | `SignatureIndexTests.dedup_lhsFingerprint_notRehashed` + `bytesHashed≈0` 闸门 |
| `02-IMG-001/002`(主线程解码/resize) | `G-copy-large-image` + `ImageDownsamplerTests` |
| `03-LT-UTF8-01`/`07-F-010` | `TextBoundaryTests` + `SearchHighlightIndexTests` |
| `04 load/findsimilar` | `G-popup-open` + `HistoryLoadTests.incremental` |

## 6. 运行

```bash
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS'           # 单元+集成
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -only-testing:MaccyPerformanceTests     # 性能闸门
```

> 编译边界验证(每个大步骤结束):`xcodebuild build ...` 必须通过,且上述非性能测试全绿。

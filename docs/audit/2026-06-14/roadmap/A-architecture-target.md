# A — 目标架构

本文定义所有大步骤的**目标态**:actor/上下文模型、数据流、模块边界、DTO 边界。每个 BS-x 文档都向此架构收敛。

## 1. 隔离模型(目标态)

```
┌──────────────── Main (UI 线程) ────────────────┐    ┌──────────────── Background (actor) ────────────────┐
│ SwiftUI Views                                    │    │ actor ClipboardIngestor                              │
│  ├─ HistoryListView / ListItemView               │    │  ├─ 读 NSPasteboard(后台)                          │
│  ├─ PreviewItemView                              │    │  ├─ RTF/HTML 解析(NSAttributedString,后台)        │
│  └─ 仅绑定 @Observable 状态                       │    │  ├─ 去重(签名索引查询,非全表)                     │
│                                                  │ DTO│  ├─ 标题生成(文本项,后台)                          │
│ @Observable History(瘦视图模型,持有 items)       │◄───│  └─ 写入(background context,单事务)               │
│ @Observable HistoryItemDecorator(UI 状态)         │    │ actor ImageProcessor                                 │
│  ├─ thumbnailImage / previewImage(就绪位图)      │    │  ├─ ImageIO 降采样(CGImageSource 缩略图)           │
│  └─ applicationImage(NSCache)                    │    │  └─ 后台解码 / 缩略图 / 预览                         │
│ Storage.mainContext(轻量读:可见窗口)             │    │ Storage.newBackgroundContext()(重读/写)             │
└──────────────────────────────────────────────────┘    └─────────────────────────────────────────────────────┘
                  ▲                                                          │
                  │ AsyncStream<StoreEvent>(item added/updated/removed)     │
                  │ → 主线程增量更新 items(不全量重排/重装饰)               │
```

### 隔离规则
- **主线程只做廉价 SwiftUI diffing + 轻量读**。任何 `NSImage(data:)`、resize、`NSAttributedString(rtf:/html:)`、SwiftData fetch/save、正则、去重比对——**禁止在 main**。
- **`@Model HistoryItem`/`HistoryItemContent` 不跨 actor**。跨边界前转成 DTO。
- **单一可变源**:每个数据项的真相源是 SwiftData(后台 context 写)。主线程 observable 是其**投影**。
- **SwiftData context 线程归属**:`mainContext` 仅 main;`newBackgroundContext()` 仅所属 actor;**禁止跨域使用同一 context**。

## 2. 上下文策略

| 操作 | 当前 | 目标 | 依据 |
|---|---|---|---|
| 写入(insert/delete/save) | `mainContext` + 多次 `processPendingChanges+save`(`History.swift:130-201,282-284`) | 后台 context + **单事务** | `04` critical |
| 去重 fetch | `mainContext` 全表 fetch(`History.swift:456`) | 后台 context + 签名索引(内存/持久化指纹列) | `01/04/08` critical |
| 冷开 load | `mainContext` 全量 fetch+排序+装饰(`History.swift:106`) | 后台分批 fetch(`fetchLimit`+`sortBy`+prefetch)+ 仅装饰可见窗口 | `01/04` critical |
| UI 读 | `mainContext` | `mainContext`(保留,但只读可见窗口轻量字段) | — |

## 3. 数据流(目标态,逐步骤)

```
[1] NSPasteboard changeCount 变化(Timer/通知)
        │ raw NSPasteboardItem
        ▼
[2] actor ClipboardIngestor.ingest()  ── 后台
        ├─ 提取类型 + data(受 maxValueSize 限制)
        ├─ 构建 ClipboardItemDTO(Sendable)
        ├─ 富文本/HTML 解析(受 richTextParsingLimit)→ 决定 title 来源
        ├─ 去重:查询 SignatureIndex(Sendable) → 命中则合并;否则新建
        ├─ 标题生成(文本:engine;图片:空标题 `""`,仅缩略图展示)
        ├─ 单事务写(background context)
        └─ 发出 StoreEvent.added(dto) / .merged(dto) / .ignored
        │ StoreEvent(Sendable enum)
        ▼
[3] History(主线程)消费 AsyncStream<StoreEvent>
        ├─ 增量更新 `all`/`items`(二分插入,不重排)
        └─ 装饰仅新增/变更项
        │
        ▼
[4] ListItemView/PreviewItemView 渲染
        └─ 需要位图时 → actor ImageProcessor.thumbnail/preview(fingerprint) → 回主线程赋值
```

边界约定:每条箭头跨越 actor/main 时,载荷必须是 **Sendable**(DTO/值类型/Data/UUID 等)。

## 4. DTO 目录(新增,均 `Sendable`)

| DTO | 字段 | 用途 | 来源(从哪拷出) |
|---|---|---|---|
| `ContentDTO` | `type: String, value: Data?, fingerprint: UInt64?, size: Int` | 单个 pasteboard 内容(去重用) | `HistoryItemContent` |
| `ClipboardItemDTO` | `contents: [ContentDTO], application: String?, source: PasteboardSource` | 一次复制的完整载荷 | pasteboard → `Clipboard.contents(from:)` |
| `SignatureDTO` | `entries: [ContentSignatureEntry]` | 去重签名(Sendable 版 `HistoryItemEngine.Signature`) | `HistoryItemEngine.Signature` |
| `ItemSnapshotDTO` | `id: PersistentIdentifier(uuid), title, firstCopiedAt, lastCopiedAt, numberOfCopies, pin, application, textPreview, imageFingerprint` | 给 UI 的轻量投影(不含大 blob) | `HistoryItem` 投影 |
| `MaccyFingerprint` | `size: Int, hash: UInt64` | C++ 哈希结果(Sendable,持久化用) | `ClipboardDataProcessor` |
| `StoreEvent` | `enum { added(ItemSnapshotDTO), merged(...), removed(id), cleared }` | actor → main 的事件 | — |

> DTO 故意**不带 `@Model` 引用**;`ItemSnapshotDTO` 在主线程被 `HistoryItemDecorator` 包装为 UI 状态。大 blob(图片字节)按需经 `ImageProcessor` 取,不随 DTO 常驻。

## 5. 新/改文件地图

| 路径 | 动作 | 职责 |
|---|---|---|
| `Maccy/Persistence/Storage+Background.swift` | 新增 | `Storage.newBackgroundContext()` 与 context 复用池 |
| `Maccy/Ingest/ClipboardIngestor.swift` | 新增 | actor:摄取/解析/去重/写库/发事件 |
| `Maccy/Ingest/SignatureIndex.swift` | 新增 | 内存去重索引(`[SignatureDTO: ItemID]`) |
| `Maccy/Ingest/Dtos.swift` | 新增 | 上述 DTO 定义 |
| `Maccy/ImageProcessing/ImageProcessor.swift` | 新增 | actor:降采样/解码/缩略图/预览 |
| `Maccy/ImageProcessing/ImageDownsampler.swift` | 新增 | ImageIO 缩略图纯函数(可单测) |
| `Maccy/ImageProcessing/ThumbnailCache.swift` | 新增 | 磁盘 + NSCache 缩略图缓存 |
| `Maccy/Observables/History.swift` | 改 | 瘦化:消费 `AsyncStream<StoreEvent>`,增量更新 |
| `Maccy/Observables/HistoryItemDecorator.swift` | 改 | 去 `@unchecked Sendable`;位图来自 `ImageProcessor`;UI 状态归 main |
| `Maccy/Clipboard.swift` | 改 | Timer → 仅触发 `Task { await ingestor.ingest() }`;移除主线程重活 |
| `Maccy/Engine/HistoryItemEngine.swift` | 改 | 签名/指纹逻辑迁入 `SignatureIndex`,支持两向指纹 |
| `Maccy/Processor/*` | 改(BS-8) | xxh3/wyhash;持久化指纹 |
| `MaccyTests/Support/*` | 新增 | test doubles/fixtures(见 `B-test-strategy.md`) |

## 6. 复杂度预算摘要(详见 `C-complexity-and-limits.md`)

| 操作 | 当前 | 目标 |
|---|---|---|
| 复制去重 | O(n) fetch + O(n·大块哈希) | O(签名查询命中数),指纹持久化后零重哈希 |
| 复制插入 | O(n log n)(整表重排) | O(log n)(二分插入) |
| 冷开 load | O(n) 全量 fetch+装饰 | O(visible) 装饰;O(n) 后台分批预取 |
| 搜索/按键 | O(n) 全量扫描(main) | O(n) 后台 actor(可并行/提前终止) |
| 图片缩略图 | 全量解码 + draw(O(像素)) | ImageIO 降采样 O(目标像素) |
| ~~标题 OCR~~ | ~~main 阻塞~~ | ~~后台;仅图片项~~ | **已移除(OCR 功能删除, 2026-06-14);图片项用空标题** |

## 7. 不变性(全流程必须成立)

- 任何写入经后台 context 单事务;失败有日志/回滚(不再 `try?` 静默)。
- 容器加载失败不删库(移隔离目录 + 询问)。
- 跨 actor 载荷均 Sendable;`@Model` 不跨域。
- 主线程无 >16ms 同步重活(性能闸门守卫,见 `B-test-strategy.md`)。
- 截断/索引单位一致(grapheme vs byte 显式区分)。

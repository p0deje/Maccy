# Maccy 代码审查 — 总览

- **日期**:2026-06-14
- **范围**:全量只读审查(`Maccy/` 应用源码 + C++/ObjC++ 层 + 构建设置),不含测试代码本身(仅作为行为规格参考)。
- **方法**:8 个维度的深度审查(分 4 批,每批 ≤2 并发)→ 关键断言由人工对抗式复核(见 `99-verification.md`)。
- **约束**:本次只产出分析与计划,**未修改任何源码**。

## 发现统计

| 维度文档 | Total | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| `01-concurrency-ui-blocking.md` | 31 | 3 | 9 | 12 | 7 |
| `02-image-pipeline.md` | 38 | 5 | 7 | 11 | 15 |
| `03-large-text.md` | 37 | 3 | 10 | 13 | 11 |
| `04-data-pipeline-storage.md` | 32 | 4 | 6 | 14 | 8 |
| `05-memory-caching.md` | 26 | 4 | 4 | 8 | 10 |
| `06-swift6-migration.md` | 50 | 5 | 12 | 21 | 12 |
| `07-data-safety-boundaries.md` | 64 | 4 | 15 | 24 | 21 |
| `08-cpp-interop-opportunities.md` | 12(+7 机会) | 0 | 1 | 3 | 6 |
| **合计** | **~290** | **28** | **64** | **106** | **90** |

> 严重度按各文档**摘要表行数**重新统计(2026-06-14 复核,可由 `awk -F'|'` 逐文档复现)。说明:`08` 的 Total 含 2 条 Info 级(F-011/F-012),未计入 C/H/M/L 列;`07` 的 F-004 在正文 prose 中被重分类为 Low、摘要表内仍列为 Critical,本表从摘要表(故 C=4);`07` 正文自述 "60" 与摘要表行数(64)不一致,以摘要表为准;`06` 正文 §0 自述 "TOTAL=45" 已陈旧,实际摘要表 50 行。

## 单一根因(一句话)

> **整条数据管线都是 `@MainActor` 隔离、且只用 SwiftData 的 `container.mainContext`。没有后台 context、没有 actor、没有任何重活被搬离主线程。**

证据(`Storage.swift:5,10`):
```swift
@MainActor class Storage {
  static let shared = Storage()
  var container: ModelContainer
  var context: ModelContext { container.mainContext }   // ← 唯一入口,绑死主队列
}
```
全项目并发计数:**0 个 `actor`、0 个 `nonisolated`、~6 个 `async`、20 个 `@MainActor`、仅 1 处后台队列**(`ApplicationImage.swift:58`,且只是文件监听 dispatch source)。

所有"重活"——SwiftData fetch/insert/delete/save、`NSImage(data:)` 全量解码、`NSImage.resized`、`NSAttributedString(rtf:/html:)`、正则、**去重时全表 fetch**、**插入时整表重排**——都同步跑在主线程。

## 瓶颈地图(热路径)

| # | 热路径 | 位置 | 现状 | 为什么阻塞 | 量级 |
|---|---|---|---|---|---|
| 1 | 启动/弹窗加载 | `History.load()` `History.swift:106` | fetch 全表→排序→全量装饰 | 全在 mainContext+主线程 | O(n) fetch + O(n log n) 排序 + O(n) 装饰 |
| 2 | 每次复制·去重 | `findSimilarItem()` `History.swift:456` | 每次复制重新 fetch 全表 + O(n) 比对 | 全表扫描 + **lhs 指纹每次重算**(见 08-F-001) | O(n) fetch + O(n·大块哈希) |
| 3 | 每次复制·插入 | `add()` `History.swift:191` | `sorter.sort(all+[item])` 找插入点 | 整表重排 | O(n log n) |
| 4 | 粘贴板轮询 | `Clipboard.start()` `:57` + `checkForChangesInPasteboard` `:158` | Timer `max(0.1,…)`,`@MainActor @objc` | 高频主线程唤醒 | 每 0.1s 一次 |
| 5 | 富文本检测 | `richText()` `Clipboard.swift:316` | `NSAttributedString(rtf:)/(html:)` 同步 | RTF/HTML 解析在主线程 | 上限 512KB,仍很重 |
| 6 | 图片解码 | `HistoryItemDecorator.image()` `:178` | `NSImage(data:)` 全量解码 | 主线程解码大图 | 多 MB 截图 |
| 7 | 图片缩放 | `generateThumbnail/Preview` `:150/:159` + `NSImage+Resized` | `@MainActor`,预览缩到**整屏尺寸** | 主线程 resize(无 ImageIO 降采样) | 预览≈屏幕(retina ~50MiB) |
| 8 | ~~图片标题 OCR~~ | `HistoryItem.generateTitle()` `:103` | ~~`Task{@MainActor}` Vision~~ | ~~OCR 在主线程~~ | **已移除(OCR 功能删除, 2026-06-14)** |
| 9 | 容量裁剪 | `limitHistorySize` `:122` → `delete` `:282` | 逐条 `delete+processPendingChanges+save` | N 次独立 SQLite 写 + 单次复制最多 3 次 save | O(n) saves |
| 10 | 搜索 | `searchQuery` didSet `:22` + `Search.swift` | throttler 0.2s,每次按键全量扫 | 全量扫描 + 高亮重建 | O(n)/按键 |
| 11 | 应用图标 | `ApplicationImage.nsImage` `:42`,装饰 init 调用 | `NSWorkspace.icon` 同步 | 装饰时同步查图标 | 每 item 一次 |

## 27 条 Critical 的主题归类

**A. 主线程数据管线(根因派生)**
- `load()` 全量 fetch+排序+装饰在主线程(01/04)
- `findSimilarItem()` 每次复制全表 fetch + O(n) 比对(01/04/03)
- 粘贴板 Timer 回调整条摄取管线同步在主线程(01)
- `add()` 单次复制最多 3 次独立 `processPendingChanges+save`,无事务(04)
- `showSpecialSymbols` 切换重生成**所有** item 标题(03)

**B. 图片解码/缩放在主线程**
- `NSImage(data:)` 全量解码并缓存为 `decodedImage`(02)
- `resized()` 用 `draw()` 全量重绘,非 ImageIO 降采样(~10× 慢)(02)
- 预览缩到全屏 `visibleFrame`,且 `Task{@MainActor}` 并未真正搬离主线程(02)

**C. 内存爆炸**
- 全分辨率 `imageData` 在装饰器里**复制第二份**(SwiftData 行内 + `imageData`)(05)
- 全分辨率解码位图 `decodedImage` 永久持有,仅 `invalidate()` 释放(05)
- 预览位图按全屏尺寸(retina ~50MiB/张)常驻(05);重度浏览最坏估算 **~12.8 GiB**

**D. Swift 6 硬阻断**
- `HistoryItemDecorator: @unchecked Sendable`——满字段可变却声称可跨线程(06-F01)
- `AppDelegate: @unchecked Sendable` 掩盖 6 个裸 `Task{}` 跨域访问(06-F02)
- `ModelContext`(非 Sendable)与 `@Model HistoryItem` 跨隔离域流动(06-F03/F05)

**E. 数据丢失/安全**
- `recoverContainer` 容器加载失败即**删除 SQLite 文件**(07-F-001)
- 全局 `try?` 吞掉所有 save/delete/fetch 错误,内存态与磁盘态可能分叉(07-F-002/F-003)
- `Collection+Surrounding.item(before:)` 首元素时 `index(_,offsetBy:-1)` **运行时 trap**(可达:首项按 ↑,07-F-032,已验证)

## 已额外人工复核的关键断言(详见 `99-verification.md`)

| 断言 | 结论 |
|---|---|
| `SWIFT_VERSION=5.0`、`SWIFT_STRICT_CONCURRENCY` 未设(minimal) | ✅ 确认(pbproj 多处) |
| C++ 指纹非对称:lhs 每次比对都重算 FNV | ✅ 确认(`ClipboardDataProcessor.swift:53` + `HistoryItemEngine.swift:162`) |
| `item(before:)` 首项 trap 可达(↑ 键) | ✅ 确认(`ItemsProtocol.swift:43` → `NavigationManager.swift:210`) |
| `recoverContainer` 删库丢数据 | ✅ 确认(`Storage.swift:37-72`) |

## 如何阅读本组文档

1. **先读本文件**(总览/根因/地图)。
2. 按痛点优先读:`02-image-pipeline` → `01-concurrency` → `04-data-pipeline` → `05-memory`。
3. 迁移/重构前读:`06-swift6-migration` + `09-roadmap`。
4. 实施前读:`99-verification`(确认哪些断言已被复核)。
5. 各文档顶部均有汇总表,按严重度排序;每条发现含 `id / 严重度 / file:line / 问题 / 证据 / 影响 / 建议`。
6. 每文档末尾列有"正确代码(勿改)"清单,避免回退既有好设计。

下一步建议见 `09-roadmap.md`(分阶段实施路线图,含 C++ 落点与 Swift 6 迁移顺序)。

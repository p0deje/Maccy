# C — 复杂度预算、I/O 限制与管线时延

全局量化基线。每个大步骤文档给"前→后"增量;本文给总账与硬上限。

## 1. 复杂度预算(操作级)

| 操作 | 当前(file:line) | 当前复杂度 | 目标复杂度 | 落点 |
|---|---|---|---|---|
| 冷开 load | `History.swift:106-119` | O(n) fetch + O(n log n) 排序 + O(n) 装饰(全 main) | O(visible) 主线程装饰;O(n) 后台分批预取 | BS-4 |
| 复制去重 | `History.swift:456-470` | O(n) fetch + 每项 `supersedes`(比对大块)+ lhs 重哈希 | O(签名命中数);指纹持久化→零重哈希 | BS-4 + BS-8 |
| 复制插入 | `History.swift:191-194` | O(n log n)(整表 `sorter.sort`) | O(log n)(二分插入/维护顺序) | BS-4 |
| 容量裁剪 | `History.swift:122-128,282-284` | O(k) 次 `(processPendingChanges+save)` | O(1) 单事务批量 delete | BS-2 |
| 搜索/按键 | `History.swift:22-35`;`Search.swift:46-160` | O(n) 全量(main)+ 高亮重建 | O(n) 后台 actor(可提前终止/并行) | BS-5 |
| 图片缩略图 | `HistoryItemDecorator.swift:150-156`;`NSImage+Resized.swift` | 全量解码 + draw,O(srcPixels) | ImageIO 降采样 O(targetPixels) | BS-3 |
| 图片预览 | `HistoryItemDecorator.swift:158-165` | 同上,目标=整屏 | 目标=预览区(封顶) | BS-3 |
| ~~图片 OCR~~ | ~~`HistoryItem.swift:97-113,269-292`~~ | ~~main,Vision `.fast`~~ | ~~后台队列;仅图片项;可取消~~ | **已移除(OCR 功能删除, 2026-06-14)** |
| 富文本检测 | `Clipboard.swift:316-336` | main,`NSAttributedString(rtf:/html:)` | 后台 actor;≤`richTextParsingLimit` | BS-2 |
| 正则忽略 | `Clipboard.swift:275-302` | main,每复制全 regex | 后台;缓存编译结果(已部分缓存) | BS-2 |
| App 图标 | `ApplicationImage.swift:42`;init `HistoryItemDecorator.swift:83` | main,装饰时同步 | 后台预热 + NSCache | BS-6 |

## 2. I/O 限制(输入/输出/内存硬上限)

### 输入限制(粘贴板侧)
| 限制 | 当前(file:line) | 目标值 | 说明 |
|---|---|---|---|
| 单 blob 大小 | `HistoryItemContent.maxValueSize` | 保持(核对值,见 `07-F-017`) | 超→丢弃该 blob 不丢弃整条 |
| 文件图读取 | `HistoryItem.swift:260-267` | `try?` nil 时**按超限处理**,不 fallthrough 无界 `Data(contentsOf:)` | `07-F-017` |
| 富文本解析 | `Clipboard.swift:10` `512*1024` | 保持 | 超→视为存在(richText 早返) |
| 正则输入 | `Clipboard.swift:9` `2_000` | 保持 | 超→不跑用户正则 |
| 搜索模糊串 | `Search.swift:37` `5_000` | 保持;改后台执行 | 截断仅影响该项高亮范围 |
| 正则搜索串 | `Search.swift:38` `1_000` | 保持;强制 `isLikelyUnsafeRegularExpression` 守卫 | 防灾难回溯 |

### 输出/存储限制(UI 侧)
| 限制 | 当前 | 目标值 | 说明 |
|---|---|---|---|
| 缩略图目标尺寸 | `HistoryItemDecorator.swift:14`(340×`imageMaxHeight`) | 保持 | 列表用 |
| 预览目标尺寸 | `HistoryItemDecorator.swift:13`(整屏 `visibleFrame`,fallback 2048×1536) | **预览区实际尺寸**,retina 上限 ≤ `previewMaxPixels`(建议 ≤ 1600²) | `02-IMG-003` |
| 标题预览长度 | `HistoryItem.swift:9` `1_000` | 保持 | |
| 文本预览长度 | `HistoryItem.swift:10` `10_000` | 保持;缓存 | `textPreviewCache` |
| 高亮基础串 | `HistoryItemDecorator.swift:197` `shortened(to:500)` | 单位与 `stringPrefix` 对齐 | `03-LT-UTF8-01` |

### 内存/缓存限制
| 限制 | 当前 | 目标值 | 说明 |
|---|---|---|---|
| `decodedImage` 留存 | 永久(`HistoryItemDecorator.swift:51,177-189`) | 滚出可视区/告警释放 | `05` critical |
| `imageData` 双份 | decorator 复制第二份(`:50,82`) | 按需从 store 取,不复制 | `05` critical |
| App 图标缓存 | 无界 Dict(`ApplicationImageCache.swift:8`) | `NSCache`(countLimit≈128,costLimit) | `05` |
| 缩略图缓存 | 无 | NSCache(内存)+ 磁盘(键=指纹,LRU≤256MiB) | BS-3/BS-6 |
| 历史条目数 | `Defaults[.size]`(计数) | 保持计数;**追加字节预算**告警 | 大图场景 |
| `sessionLog` | `[Int:HistoryItem]` | 改存 `[Int:ItemID]`(不持模型引用) | `05` |

### C++ / 哈希限制
| 限制 | 当前 | 目标 | 说明 |
|---|---|---|---|
| 指纹阈值 | `ClipboardDataProcessor.swift:4` `16*1024` | 保持 | 仅大内容算指纹 |
| 哈希算法 | FNV-1a(`ClipboardByteProcessor.cpp:78`) | xxh3/wyhash | `08-F-002/003` |
| 指纹存储 | 仅 rhs 临时 | 持久化 lhs(`HistoryItemContent.fingerprint` 列) | `08-F-001`(V-2 确认) |

## 3. 管线时延预算(目标态,从触发到可见)

| 阶段 | 触发 | 目标主线程预算 | 目标端到端 | 当前问题 |
|---|---|---|---|---|
| 弹窗打开→首屏 | 用户唤起 | < 16ms(仅 diff 已预取数据) | < 80ms(p95) | 当前 main 全量 load |
| 预加载可见窗口 | 弹窗将开 | 0(后台 actor) | 后台并行 | 无 |
| 复制文本→列表可见 | changeCount 变 | < 16ms(仅追加单行) | < 120ms(p95) | main 摄取+去重 |
| 复制大图→可预览 | changeCount 变 | < 16ms(主线程无解码) | < 400ms(后台降采样) | main 解码+resize |
| 按键搜索 | searchQuery 变 | < 16ms/键 | < 60ms(p95,后台) | main 全量扫 |

> "2× UI 响应"等价于:**主线程预算全部压到 < 16ms/事件**,重活移到后台并行,数据预加载。见 `README.md` 度量基线。

## 4. 内存预算(目标态)

- 稳态(浏览,history=1000,20% 图片):常驻 < 300MiB(当前重度浏览估算 ~GB 级)。
- 单项最大驻留:缩略图(≤340²) + 必要时预览(≤1600²) + 文本预览(≤10k char)。**不常驻** `decodedImage` 与全分辨率 `imageData`。
- 内存告警:释放非可视区缩略图 + 解码位图。

## 5. 并发与线程预算

- 主线程:仅 SwiftUI diff + observable 赋值 + 轻量 mainContext 读。
- `ClipboardIngestor` actor:1 个,串行化摄取(去重/写库顺序一致)。
- `ImageProcessor` actor:可内部用 `Task`/后台队列并行降采样与解码。
- 后台 SwiftData context:每 actor 一个,不复用跨域。

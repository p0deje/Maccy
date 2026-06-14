# Maccy 优化路线图

本文把 `00`~`08` 的发现落成**分阶段、可执行、按优先级**的实施计划。每阶段标注:目标、关键改动、预期收益、依赖、风险。顺序按"先止血、再奠基、后加速"组织。

> 总目标:消除 UI 阻塞(图片预览/大文本为先)、内存可控、可迁 Swift 6、UI 响应 ~2×。本路线图**不改 UI 行为**,只把重活搬离主线程并预加载数据。

---

## P0 — 止血:数据安全与崩溃修复(先做,低风险高价值)

不依赖任何大重构,先消除"丢数据/崩溃"类问题。

| 项 | 对应发现 | 改动方向 | 风险 |
|---|---|---|---|
| 修首项 ↑ trap | 07-F-032(V-3 已确认) | `Collection+Surrounding.item(before:)` 改 `guard currentIndex > startIndex else { return nil }` 后再 `index(offsetBy:-1)`;`item(after:)` 保持现状 | 极低 |
| 容器失败不删库 | 07-F-001(V-4 已确认) | `recoverContainer` 改为:失败时**移动到隔离目录** + 询问用户,而非直接删 `-sqlite/-shm/-wal`;仅在用户确认后清理 | 低 |
| 不再静默吞错 | 07-F-002/F-003(V-5) | 把 ingest/save 路径的 `try?` 改为捕获并 `logger.error` + 视情况回滚内存态;失败时通知用户 | 低-中 |
| 富文本/文件大小双重校验 | 07-F-017 | `dataFromFileIfAllowed` 在 `try?` 返回 nil 时**按未通过上限处理**,不 fallthrough 到无界 `Data(contentsOf:)` | 低 |
| C++ 构建方言统一 | 99 补充 | pbxproj 两个 `gnu++0x` config 统一为 `gnu++17`,为后续 C++ 机会预留 | 极低 |

**验收**:↑ 在首项不再崩;模拟容器损坏不丢历史;save 失败有日志/提示。

---

## P1 — 奠基:并发模型重构(根因,所有加速的前提)

目标:把"重活"从 `@MainActor` + `mainContext` 搬到后台。这是 P2/P3/P4 的地基,不做则后续只能做局部优化。

### P1.1 引入后台 ModelContext
- `Storage` 增加 `func newBackgroundContext() -> ModelContext`(`container.newContext()`),后台写/读走它;`mainContext` 只供 UI 读取已就绪的轻量状态。
- 后台 context 写入后,通过 `NotificationCenter`/`AsyncStream` 通知主线程刷新 `items`(只更新必要的可见窗口)。
- 单次复制改为**单事务**:insert + dup-delete + size-trim 合并成一次 `context.transaction { }`,一次 save(对应 04 `add-multi-processpending-save-per-copy`)。

### P1.2 引入 `actor HistoryStore`(或 `ClipboardIngestor`)
- 用 `actor` 承载:粘贴板读取、富文本/HTML 解析、去重比对、标题生成、写库。
- 主线程只持有轻量 `@Observable` 视图模型(现有 `History`/`HistoryItemDecorator` 的 UI 状态部分),数据由 actor 异步喂入。
- `onNewCopyHook` 改 `async`;`Clipboard.checkForChangesInPasteboard` 把数据采集 `Task { await ingestor.ingest(...) }`。

### P1.3 弹窗打开预加载(Pre-warm)— 直接命中"2× 响应"
- Popup 即将打开时,后台 actor 预取**可见窗口**的 item(分批 `fetchLimit`,带 `sortBy`+`propertiesToFetch`+`relationshipKeyPathsForPrefetching`),预解码缩略图,主线程拿到的是"已就绪"数据,首屏只做廉价 SwiftUI diffing。
- `load()` 不再一次性 fetch+排序+装饰全部(对应 01/04 critical)。

**依赖**:无(起点)。**风险**:中(SwiftData 跨 context 合并语义需测;`@Model` 跨 actor 传递需转 DTO)。**预期**:冷开/弹窗打开从"全量同步"变"后台预取 + 即时渲染",UI 响应数量级改善。

---

## P2 — 图片管线(用户最痛)

前置:P1(后台 actor 才能安全解码)。

| 项 | 对应发现 | 改动方向 | 收益 |
|---|---|---|---|
| ImageIO 降采样 | 02-IMG-002 | `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` + `kCGImageSourceCreateThumbnailFromImageAlways` + `kCGImageSourceShouldCacheImmediately`,在后台 actor 生成缩略图/预览,替代 `NSImage.draw` | 大图 ~10× 提速,内存大幅下降 |
| 后台解码 | 02-IMG-001 | `NSImage(data:)`/解码移到 actor;主线程只拿结果 | 解码不阻塞 UI |
| 缩略图磁盘缓存 | 02 机会 | 持久化已生成缩略图(键=内容指纹),避免重复解码 | 二次打开近零成本 |
| 预览尺寸封顶 | 02-IMG-003 | 预览目标改为**实际预览区尺寸**(非全屏 `visibleFrame`),retina 上限可控 | 每张预览 ~50MiB → 数 MiB |
| 真异步任务 | 02-IMG-004 | 去掉 `Task{@MainActor}`,改后台 actor + 回主线程赋值(图片解码/缩略图/预览) | 真正并行 |

**验收**:复制大图/打开预览期间 UI 不卡;Instruments 主线程无解码/resize 长尾。

---

## P3 — 数据管线:增量与去重加速

前置:P1。

| 项 | 对应发现 | 改动方向 | 收益 |
|---|---|---|---|
| 增量插入(免整表重排) | 01/04 `add()` `:191` | 维护已排序数组,二分插入 `O(log n)`;或排序键(`lastCopiedAt`/`pin`)由 SwiftData `sortBy` 直接保证 | 每次复制 O(n log n)→O(log n) |
| 去重免全表 fetch | 01/04 `findSimilarItem` `:456` | 内存维护 `(type→签名/指纹)` 索引;或 SwiftData 增加**持久化指纹列**+谓词过滤;命中再做内容比对 | 每次复制 O(n) fetch→O(命中数) |
| 指纹对称复用 | 08-F-001(V-2 已确认) | `ClipboardDataProcessor.dataLikelyEqual` 持久化/缓存 lhs 指纹(`HistoryItemContent` 加 `fingerprint` 字段或内存表),两向都传指纹 | 免对全表大块重哈希 |
| 分批/限量 fetch | 04 `load()` | `FetchDescriptor` 设 `fetchLimit`/分页 + `relationshipKeyPathsForPrefetching`;UI 只需可见窗口 | 冷开内存与时延双降 |
| 摄取合并/节流 | 04 | 快速连击复制用 `Throttler`/coalesce 合并(仅保留最终态或去重入队),避免风暴式全量摄取 | 复制风暴不卡 |
| 去重 merge 去拷贝 | 04 `:151` | dup 合并时不整数组复制 contents | 小幅内存/CPU |

**验收**:大历史(数百~上千条)下复制/打开无明显延迟;去重不再全表扫描。

---

## P4 — 大文本与搜索

| 项 | 对应发现 | 改动方向 |
|---|---|---|
| 搜索搬后台 | 03/01 | `searchQuery` 改 `Task { await searchActor.search(...) }`,主线程只接收结果;Fuse/regex 在 actor 内 |
| 单位一致性 | 03-LT-UTF8-01 / 07-F-012 | 统一 `String+Shortened`(grapheme)与 `Data.stringPrefix`(byte)的截断语义,或显式区分"标题预览"与"内容前缀" |
| 高亮索引修正 | 07-F-010 | Fuse 返回 UTF-16 偏移,转 `String.Index` 需正确换算(grapheme/UTF-16/标量),避免 emoji/CJK 高亮错位 |
| 标题生成缓存/降频 | 03-LT-MAIN-02 | `showSpecialSymbols` 切换只重建可见项标题,或缓存"去符号"基底 |
| 大文本正则防护 | 03 | 复用 `isLikelyUnsafeRegularExpression`;考虑 RE2 替代 NSRegularExpression(见 P7) |

---

## P5 — 内存治理

| 项 | 对应发现 | 改动方向 |
|---|---|---|
| 解码位图按需释放 | 05 `decodedImage` | 滚出可视区/内存告警时 `cleanupImages()` 释放 `decodedImage`/`previewImage`,仅留缩略图;`NSCache` 管 cost |
| 图片不双份存储 | 05 `img-fullres-dup-storage` | 装饰器不复制 `imageData`,改为按需从 SwiftData 取(或弱引用) |
| App 图标缓存封顶 | 05 | `ApplicationImageCache` 改 `NSCache`(countLimit);LRU 淘汰 |
| 内存告警响应 | 05 | 注册 `NSApplication.didReceiveMemoryWarningNotification`,清理解码位图与非可见缩略图 |
| sessionLog/regex 缓存边界 | 05 | 复核增长上限 |

**验收**:重度浏览下常驻内存从"~GB 级"降至"百 MiB 级";内存告警能回收。

---

## P6 — Swift 6 迁移(增量,与 P1 并行推进)

基线:`SWIFT_VERSION=5.0`,`SWIFT_STRICT_CONCURRENCY=minimal`(V-1 已确认)。建议 5 阶段:

1. **minimal→targeted**:开启 `SWIFT_STRICT_CONCURRENCY = targeted`,修显式 `@MainActor`/`Sendable` 警告。
2. **去 `@unchecked Sendable`**:`HistoryItemDecorator`、`AppDelegate` 改为正确隔离(06-F01/F02)。`HistoryItemDecorator` 的可变 UI 状态归 `@MainActor`,数据/图片归 actor。
3. **ModelContext 边界**:定义 Sendable DTO(从 `@Model` 拷贝出值类型)跨 actor 传递(06-F03/F05)。`HistoryItem`(模型)不跨隔离域。
4. **单例复核**:`Storage/History/AppState/Clipboard/ApplicationImageCache` 的隔离域明确化。
5. **targeted→complete**:开启 `SWIFT_VERSION = 6`,清剩余 data-race 警告。

**关键**:`ModelContext` 非 Sendable 是硬阻断,P1 的"后台 context + DTO"同时解决了 Swift 6 与性能。

---

## P7 — C++ 扩展落点(仅在基准证明瓶颈后再做)

> 原则:**先测量再下沉**。Foundation/AppKit/ImageIO 能做好的,不要为 C++ 而 C++。

| 机会 | 现状 | C++ 方案 | 预期 | 复杂度 | 前置 |
|---|---|---|---|---|---|
| 哈希升级 | FNV-1a 串行依赖,~1GB/s | xxh3 / wyhash(SIMD) | 25–35× | 中 | P3(先让指纹被持久化复用,再换算法) |
| 持久化指纹 DTO | lhs 每次重算 | `MaccyFingerprint { size; hash }` Sendable 值类型,存入 `HistoryItemContent` | 免全表重哈希 | 低 | P3 |
| 图片降采样 | `NSImage.draw` | vImage / libjpeg-turbo / libheif 封装(或 C++ 包 ImageIO) | 大图显著 | 高 | P2(先验证 ImageIO 原生降采样是否已够) |
| 感知哈希去重 | 仅字节相等 | pHash/aHash 近似重复图检测 | 新能力 | 中 | P3 |
| 大文本正则 | NSRegularExpression | RE2 / hyperscan(线性时间,抗灾难回溯) | 抗 DoS + 更快 | 中-高 | P4(仅在 NSRegularExpression 成瓶颈) |
| SIMD 串搜索 | Fuse/`range(of:)` | memmem/SSE/AVX 加速子串 | 长文本搜索提速 | 中 | P4 |

**已在用的 C++(`validUTF8PrefixLength`、`fnv1a64`)经审查正确**(99-V 系列复核:UTF-8 状态机各分支正确,含 overlong/surrogate/边界)。ObjC++ 桥接需补 `data.bytes` 空/连续性守护与 Sendable DTO 边界(08)。

---

## "UI 响应 ×2" 的直接策略(汇总)

1. **预加载**:弹窗打开前后台预取可见窗口 + 预解码缩略图(P1.3 + P2)。
2. **搬离主线程**:解码/resize/搜索/去重/富文本解析全部进 actor(P1+P2+P3+P4)。
3. **主线程只做廉价 diffing**:SwiftUI 视图只绑定"已就绪"的轻量状态。
4. **增量更新**:复制/搜索只动增量,不整表重排/重装饰(P3)。
5. **去重免全表**:签名索引/指纹列(P3)。
6. **内存可控**:解码位图按可视区/告警回收(P5),避免 GC/swap 抖动。

---

## 建议实施顺序

```
P0(止血,1–2 天) ──┐
                   ├─→ P1(并发地基)─possibility┬─→ P2(图片)
                   │                          ├─→ P3(数据管线)
                   │                          └─→ P4(大文本/搜索)
                   └─→ P6(Swift 6,与 P1 并行增量推进)
                                              P5(内存)随各阶段落地
                                              P7(C++)仅在基准后
```

- **第一周**:P0 全部 + P1.1(后台 context)+ P1.3(预加载)→ 弹窗打开/复制的体感立刻改善。
- **第二周**:P2(图片)→ 解决最痛的预览阻塞。
- **第三周起**:P3 → P4 → P5,穿插 P6 增量迁移。
- **C++**:P3 落地后,先做"持久化指纹 + xxh3"(最高 ROI),其余按基准决定。

---

## 度量建议(落地前后对比)

- 弹窗冷开到首屏可交互耗时(主线程挂钟 + main-run-loop 占用)。
- 复制一张大图到可粘贴/可预览的时延。
- 大历史(500/1000 条)下搜索 P95 延迟。
- 常驻内存(重度浏览 5 分钟后)与内存告警回收效果。
- Instruments:Main Thread 长尾(>16ms)帧数。

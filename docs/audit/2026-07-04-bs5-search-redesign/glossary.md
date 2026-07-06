# 词汇表 — BS-5 搜索重设计(2026-07-04)

> 术语 + finding-id 词汇 + 不变量。配套 `README.md` / `decisions.md`。
> finding-id 上游权威:`docs/audit/architecture-and-root-causes.md §6`。

## 一、新术语(本设计引入)

| 术语 | 定义 |
|---|---|
| **Track 0/1/2/3** | 本设计四大轨:0=模式循环按钮;1=标题域正确性;2=全文搜索;3=预览高亮+滚动。每轨一个编译边界(BS-5R.x)。 |
| **`searchText`** | `HistoryItem` 新持久化列(`String?`),存该项的**不截断**全文(first-rep 提取,优先级 fileURL→string→rtf→html;image=`""`)。ingest 一次性写;`SearchActor` cache 的源。ADR-6。 |
| **body cache** | `SearchActor` 持有的 `[ItemID: String]` 内存语料,惰性 bootstrap 自 `searchText` 列,经 StoreEvent 增删维护。取代每按键 `all.map` 投影。ADR-6。 |
| **正文封顶(searchBody)** | `TextLimits.searchBody=32_000` 字符(Defaults 可配)。索引/扫描正文超此不命中(退化标题搜索)。ADR-5。 |
| **fuzzy 正文前缀** | fuzzy 语料 = `title + body.prefix(5_000)`,Fuse DP 成本有界。ADR-3。 |
| **Stage 1 / Stage 2 预览** | Stage1=SwiftUI `Text(AttributedString)` 窗内高亮(≤3000);Stage2=`NSTextView` representable,惰性布局 + `scrollRangeToVisible` 深度滚动。ADR-4。 |
| **`TextLimits`** | 新单一常量源 enum:`titlePreview=1_000`/`highlight=1_000`/`fuzzy=5_000`/`regexp=1_000`/`searchBody=32_000`。取代分散硬编码(锁 07-F-013)。T1.2。 |
| **`PreviewTextRep`** | 新 `NSViewRepresentable` 包 `NSTextView`,Stage 2 预览文本视图。`NSTextStorage` 持全文 + 惰性 layout + 范围高亮 + 精确滚动。T3.2。 |
| **`inBody`** | `SearchMatchDTO` 新字段(Bool),标记命中在标题前缀内(`false`)还是正文(`true`)——预览高亮路径选择依据。T2.3。 |
| **Track 2-index** | 条件轨:仅 T2.7 G-search 测量 actor 延迟不可接受时开。trigram `[String: Set<ItemID>]` 索引(模板克隆 `SignatureIndex`)。ADR-2。 |
| **mode abbreviation** | `Search.Mode.abbreviation`:`EX/FZ/RE/MX`,循环按钮显示文本。ADR-1。 |

## 二、finding-id 词汇(本设计触及)

### `03-LT-*`(大文本,源自 06-14 spec)

| id | 含义 | 本设计处理 |
|---|---|---|
| `03-LT-UTF8-01` | 截断单位 grapheme vs byte 不一致 | T1.9 `shortened(toChars:/toBytes:)` 统一 |
| `03-LT-UTF8-02`/`06` | `count`/`offsetBy` 的 O(n) | T1.9 `prefix`/`utf8.count` 快判 |
| `03-LT-SEARCH-01` | 截断导致漏匹配 | T2 全文(解) |
| `03-LT-SEARCH-02` | `mixedSearch` 三遍扫描 | T1.3 短路(无元字符跳 regexp)→ 至多两遍 |
| `03-LT-SEARCH-04` | 正则守卫自身无界 | T1.4 `regexpInputLimit=2_000` |
| `03-LT-MAIN-02` | `showSpecialSymbols` 对全 items 重生成标题 | T1.6 仅可见项 + `regenerateTitleForSymbolToggle` |
| `03-LT-MAIN-05` | resize 在搜索 throttle 内 | T1.7 移 `.utility` Task + 阈值 |
| `03-LT-RENDER-01` | 逐键重建 attributedTitle 无 memoize | T1.5 memoize `(query,ranges)→AttributedString` |
| `03-LT-TITLE-03` | 双 `replacingOccurrences` 分配 | T1.6 单遍 `UnicodeScalarView` |

### `07-F-*`(数据安全/正确性,源自 06-14 spec)

| id | 含义 | 本设计处理 |
|---|---|---|
| `07-F-010` | 高亮 UTF-16/grapheme 错位 | T1.1 经验闸门(先测 Fuse 1.4.0 offset 语义,按结果决定加 `toGrapheneRange` 或删夸大注释) |
| `07-F-012` | 截断单位混用 | T1.9(同 LT-UTF8-01) |
| `07-F-013` | 搜索/高亮截断不一致→静默丢 | T1.2 `TextLimits` 单源 + clamp-and-log(锁) |
| `07-F-030` | 同 07-F-013 静默丢 | T1.2(同) |
| `07-F-049` | 双 `replacingOccurrences` | T1.6(同 LT-TITLE-03) |

### `LT-SEARCH-06`(Fuse 实例)

| id | 含义 | 本设计处理 |
|---|---|---|
| `LT-SEARCH-06` | Fuse per-Search 实例 | **已完成**(`SearchActor.swift:32` 单实例);T2 保持 |

## 三、不变量(本设计必须成立)

继承 `A-architecture-target.md §7` + 本设计新增:

### 隔离/并发
- **跨 actor 载荷 Sendable**:`searchText: String`、`SearchMatchDTO`、`(ItemID, String)` 均值类型;`@Model HistoryItem/HistoryItemContent` **不跨域**。
- **上下文归属**:`mainContext` 仅 main;`searchText` 的 fault/bootstrap 在 `@ModelActor` 后台 context(`BackgroundClipboardIngestor` 或专用 loader),不在 main。
- **`SearchActor` 互斥即同步**:body cache + (条件)trigram 索引 + Fuse 均 actor 内,无 `@unchecked`/`nonisolated(unsafe)`(同既有 `SearchActor` 注释 `:11-16`)。
- **`mainContext` 从不 reset**(架构 §4.2):body cache **必须**在 actor(不在 main),规避进程级累积滞留。

### 正确性
- **offset 单位**:全文 offset 为 **grapheme**(`String.distance(from:to:)`),与 `SearchMatchDTO` 既有语义一致;预览侧 `index(offsetBy:)` 解析。非 UTF-16/NSRange。
- **fuzzy 两遍 title-first-wins(ADR-8)**:`SearchActor.fuzzySearch(for:in:)` 标题先扫;**仅 title-miss**(Fuse threshold 0.7 未命中)才扫 `body.prefix(TextLimits.fuzzy)`;每结果单 `SearchMatchDTO`、单 `inBody`(标题命中 `false` / 正文命中 `true`),**单结果永不跨字段**(无 title/sep/body 接缝 bug 类)。镜像 T2.3 `simpleSearch`/`regexpSearch`。替代(单遍 concat / best-of-both)见 ADR-8,均否决。
- **fuzzy 跨项排序两 bucket(ADR-9)**:`fuzzySearch(query:within:)` 排序 = stable partition by `inBody`(标题命中 bucket 在前)+ 各 bucket 内 score 升序。消除 Fuse score 跨 haystack 长度非归一化坑;T2.3 标题优先先例延续。
- **突变后刷新路由 actor(ADR-10)**:`refreshVisibleItems` 非空分支走 `performSearch()`(actor),不走 legacy `search.search`;修 T2.3 起 shipped 分歧(add/pin/reconcile 突变后正文命中缺失)。
- **equality guard**:`applySearchResults` 仅当 `decorator` 的对应文本 == DTO snapshot 时高亮(防 stale offset 越界);`searchText` snapshot 须随 DTO 携带(类比既有 `title` equality guard)。
- **截断单源**:所有截断走 `TextLimits`;搜索与高亮同源(锁 07-F-013)。
- **generation guard**:`searchGeneration` 在增/删/清/模式切换/ingest 时 bump,防 stale 覆盖(既有,扩展到模式切换)。

### 性能/主线程纯净
- **`G-search` 闸门**:n=1000 逐键搜索,**主线程 <16ms/键**;搜索全在 actor;`MainThreadProbe` 断言。T2.7 改测 actor 路径(非 legacy `Search()`)。
- **无每按键 main 投影**:`performSearch` 不再 `all.map`(语料在 actor)。T2.2。
- **预览大文本 live 内存有界**:Stage 2 NSTextView 惰性 layout(非 Text 急切);`measure(XCTMemoryMetric)` 闸 31KB body 不涨。

### 范围封顶
- **正文封顶 32KB**(`TextLimits.searchBody`/`Defaults[.searchBodyLimit]`):超封顶不索引/扫描。ADR-5。
- **fuzzy 正文前缀 5000**:超不命中 fuzzy(精确由 exact/regexp 覆盖)。ADR-3。

## 四、测量与决策点

| 点 | 触发 | 输出 |
|---|---|---|
| **T1.1 Fuse offset** | emoji fuzzy 落位断言 | grapheme→删夸大;UTF-16→加 `toGrapheneRange` |
| **T2.7 G-search actor 延迟** | n=1000 heavy-text,`measure` + `MainThreadProbe` | P95 < ~30ms→无索引;> ~50ms→开 Track 2-index(ADR-2 叉点) |
| **T3.2 NSTextView 内存** | 31KB body,`XCTMemoryMetric` | live 内存有界(lazy layout 验证) |

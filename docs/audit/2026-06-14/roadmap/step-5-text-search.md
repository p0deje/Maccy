# BS-5 — Large Text & Search(后台化 + 文本边界/单位/高亮正确性)

> **依赖**:BS-2(复用其 actor 模式与 `ItemSnapshotDTO`/`StoreEvent` 抽象)。**编译边界**:小步骤 5.4 起会临时破坏编译(`searchQuery.didSet` 与 `Search` 调用点重写),**5.6 恢复**;完成全部后 `xcodebuild build` 通过、既有测试全绿。
>
> **不越界**:C++ 正则(RE2 / 灾难回溯根除)属 **BS-8**;OCR / 标题生成的 actor 化属 **BS-2/3**;图片预览路径属 **BS-3**。本步只做"搜索后台化 + 文本边界/单位/高亮正确性 + 标题重建范围收窄 + 正则守卫强化"。

**目标**:把逐键搜索(fuzzy / regex / simple / mixed)整条搬进后台 actor,主线程只接收 `[SearchResult]` 增量;修掉 Fuse UTF-16 偏移与 grapheme `index(_:offsetBy:)` 混用导致的高亮错位;统一"标题预览"与"内容前缀"的截断单位;`showSpecialSymbols` 切换只重建可见项标题(不再对全 `items` 调 `generateTitle`);强化正则守卫并加输入长度上限。
**依据**:`07-F-010`(高亮 UTF-16/grapheme 错位)、`07-F-011`(fuzzy 截断 trap 隐患)、`07-F-012`/`03-LT-UTF8-01`(截断单位 grapheme vs byte 不一致)、`07-F-013`/`03-LT-RENDER-01`(`highlight` 用截断串 + 全串 ranges 静默丢高亮)、`07-F-030`(同上静默丢)、`03-LT-MAIN-02`(`showSpecialSymbols` 对全 `items` 重生成标题)、`03-LT-SEARCH-01`(截断导致漏匹配)、`03-LT-SEARCH-02`(`mixedSearch` 三遍扫描)、`03-LT-SEARCH-03`(Fuse range 映射未测)、`03-LT-SEARCH-04`(正则守卫自身无界)、`03-LT-SEARCH-06`(Fuse 实例)、`03-LT-UTF8-02/06`(`count`/`offsetBy` 的 O(n))、`03-LT-TITLE-03`/`07-F-049`(双 `replacingOccurrences` 分配)、`03-LT-MAIN-05`(resize 在搜索 throttle 内)、`A-architecture-target.md §6`(搜索 `O(n) main` → `O(n) background`)。
**编译安全性**:核心变更是 `History.searchQuery.didSet` 接线方式 + `Search` 的范围类型 + `String.shortened(to:)` 语义 + `highlight` 路径;末尾所有调用点统一经 actor/事件,恢复编译。

## 受影响文件
- 新:`Maccy/Search/SearchEngine.swift` — `actor SearchEngine`,封装 fuse/regex/simple/mixed,主线程只调用 `search(...) async`。
- 新:`Maccy/Search/HighlightRange.swift` — `struct HighlightRange: Sendable, Equatable`(单位显式的范围模型)。
- 新:`Maccy/Search/SearchResult.swift` — `struct SearchSnapshot: Sendable`(`objectID: UUID` + `ranges: [HighlightRange]` + `score: Double?`),跨 actor 传回主线程。
- 新:`MaccyTests/SearchHighlightIndexTests.swift`、`MaccyTests/TextBoundaryTests.swift`、`MaccyTests/SearchEngineTests.swift`。
- 改:`Maccy/Search.swift:36-160` — `class Search` 改为薄壳或弃用;fuzzy/regex/mixed 实现迁入 `SearchEngine`;`SearchResult.ranges`(`Range<String.Index>` 改 `[HighlightRange]`);`isLikelyUnsafeRegularExpression`(`:40-44`)加输入长度上限。
- 改:`Maccy/Extensions/String+Shortened.swift:2-8` — 区分 `shortened(toChars:)`(grapheme,显式)与新增 `shortened(toBytes:)`(UTF-8 字节,对齐 `Data.stringPrefix`);旧 `shortened(to:)` 标 `@available(*, deprecated, renamed: "shortened(toChars:)")`。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:191-216` — `highlight` 接收 `[HighlightRange]`,与 `SearchEngine` 同单位(UTF-16/标量)换算后落到截断后的串;`title.shortened(to: 500)`(`:197`)改 `shortened(toChars: highlightLimit)`,且 `highlightLimit` 与搜索侧截断点**显式对齐**(同一常量)。
- 改:`Maccy/Observables/History.swift:22-36`(`searchQuery.didSet`)、`:88-94`(`showSpecialSymbols` toggle)、`:480-498`(`updateItems`/`refreshVisibleItems`)、`:510-514`(`updateTitle`)。
- 改:`Maccy/Engine/HistoryItemEngine.swift:67-107`(special-symbols 单遍化 + `previewableTextPrefix` 截断单位对齐)。

## 小步骤

- [ ] **5.1 `HighlightRange` 模型(单位显式)** — `Search/HighlightRange.swift`。
  - `struct HighlightRange: Sendable, Equatable { var lower: Int; var upper: Int; var unit: TextUnit }` + `enum TextUnit: Sendable { case utf16 /* Fuse 返回 */; case grapheme /* Swift String.Index */; case utf8 /* byte */ }`。
  - 附纯函数:`func clamped(toCount count: Int) -> HighlightRange?`(超出 `count` 返回 nil,对应 `07-F-013` 静默丢 → 改为可观测的 clamp-and-log)。
  - 纯值类型,无 AppKit 依赖 → 可单测(锁 `07-F-010`/`07-F-013`/`07-F-030`)。
- [ ] **5.2 UTF-16 ↔ grapheme 换算(纯函数 + 测试)** — `Search/HighlightRange.swift` 附加。
  - `func toGrapheneRange(in string: String) -> Range<String.Index>?`:用 `String.UTF16View.Index(_offsetInCodeUnits:)` + `String.Index(_:within:)` 把 Fuse 的 UTF-16 偏移落到 `String.Index`(根除 `index(_:offsetBy:)` grapheme 推进的错位,`07-F-010`)。
  - 单元测试 `SearchHighlightIndexTests`:
    - `fuseRange_emoji_landsOnCorrectGrapheme`:title `"x😀y"`,query `"y"`,断言高亮落在 `y` 而非 `😀` 的尾字节(原 bug:UTF-16 偏移 3 → grapheme `index(offsetBy:3)` 越过 emoji)。
    - `fuseRange_cjk_alignsWithGrapheme`:`heavy_text.txt` 首段 CJK。
    - `range_pastTruncation_returnsNil`:`clamped(toCount:)` 行为(锁 `07-F-013`)。
- [ ] **5.3 `SearchSnapshot` DTO** — `Search/SearchResult.swift`。
  - `struct SearchSnapshot: Sendable, Equatable { var objectID: UUID; var ranges: [HighlightRange]; var score: Double? }`。
  - **不持 `HistoryItemDecorator` 引用**(它 `@unchecked Sendable` 且 `@Observable`,跨 actor 不安全);主线程拿 `objectID` 后在自己域内查 `[HistoryItemDecorator]`(`all.first { $0.item.id == objectID }`)。对应 `A §7`"`@Model` 不跨域"。
- [ ] **5.4 [breaks compile] `actor SearchEngine`** — `Search/SearchEngine.swift`。
  ```swift
  actor SearchEngine {
    private let fuse = Fuse(threshold: 0.7)               // 复用,见 LT-SEARCH-06(实例级,与 History 同生命周期)
    private let fuzzyLimit: Int = 5_000                   // 与 highlightLimit 同源常量
    private let regexpLimit: Int = 1_000
    private let regexpInputLimit: Int = 2_000             // 新增:正则输入长度上限(对齐 Clipboard.regularExpressionInputLimit,锁 LT-SEARCH-04)

    func search(query: String, in items: [SearchableDTO], mode: SearchMode) async -> [SearchSnapshot]
    // query 为空 → 返回全部(items.map { .init(objectID: $0.id, ranges: [], score: nil) }),早返
    // 内部:fuzzy / regex / simple / mixed 全在 actor 域;Fuse 返回的 UTF-16 偏移直接包成 HighlightRange(unit: .utf16)
  }
  ```
  - `SearchableDTO: Sendable { var id: UUID; var title: String }`(主线程从 `HistoryItemDecorator` 投影:`.init(id: $0.item.id, title: $0.title)`)。
  - **截断单位对齐**:`fuzzySearch` 内 `searchString.shortened(toChars: fuzzyLimit)`(替换 `index(_:offsetBy:)`,锁 `07-F-011` trap + `03-LT-UTF8-06` O(n));`regexpSearch` 内 `searchString.shortened(toChars: regexpLimit)`(与 `highlight` 同常量,锁 `07-F-013`)。
  - **mixed 短路**:`mixedSearch` 仅当 `simple` 为空**且** query 含正则元字符时才跑 `regex`;否则直接 `fuzzy`(`03-LT-SEARCH-02` 三遍扫描 → 至多两遍,且在后台)。
  - **可提前终止**:actor 内可加 `Task.isCancelled` 检查(旧串搜索进行中新键到来时取消旧 task),但本步不强求(留 BS-7 严格化)。
- [ ] **5.5 [breaks compile] 重写 `Search.swift` 为薄壳** — `Search.swift:5-162`。
  - `class Search` 改为持有 `let engine = SearchEngine()` 的转发壳;`search(string:within:)` 改 `func search(...) async -> [SearchSnapshot]`;`SearchResult` 改用 `SearchSnapshot`;`Searchable` 仍 = `HistoryItemDecorator`(`SearchEngine` 不接收它,接收 `SearchableDTO`)。
  - `isLikelyUnsafeRegularExpression`(`:40-44`):加 `guard pattern.count <= regexpInputLimit else { return true }`(超长一律视为不安全,锁 `03-LT-SEARCH-04`),并保留 nested-quantifier 检测。
  - 此步破坏编译(`Search.SearchResult` 类型变了,`HistoryItemDecorator.highlight` 签名待 5.6 改)。
- [ ] **5.6 [restores compile] `searchQuery.didSet` 接后台 actor** — `History.swift:22-36`。
  ```swift
  var searchQuery: String = "" {
    didSet {
      // 旧:throttler.throttle { updateItems(search.search(...)) }  —— 同步主线程 O(n)
      searchTask?.cancel()
      throttler.throttle { [self] in
        let dtos = all.map { SearchableDTO(id: $0.item.id, title: $0.title) }
        searchTask = Task { @MainActor in
          let snapshots = await self.search.search(string: self.searchQuery, within: dtos)
          // 仅处理最近一次结果(避免乱序覆盖)
          guard !Task.isCancelled else { return }
          self.updateItems(snapshots)
          if self.searchQuery.isEmpty {
            AppState.shared.navigator.select(item: self.unpinnedItems.first)
          } else {
            AppState.shared.navigator.highlightFirst()
          }
        }
      }
      // resize 移出搜索关键路径(LT-MAIN-05):改为低优先级 coalesce,见 5.8
    }
  }
  ```
  - `updateItems(_ snapshots: [SearchSnapshot])`(`:480-489`):`items = snapshots.compactMap { snap -> HistoryItemDecorator? in guard let item = all.first(where: { $0.item.id == snap.objectID }) else { return nil }; item.highlight(searchQuery, snap.ranges); return item }`。复杂度 `O(visible)` 装饰 + `O(snapshots)` 查找(`all` 可在 5.9 加 `[UUID: HistoryItemDecorator]` 索引)。
  - 此时编译恢复(`Search` 已 async、`highlight` 签名见 5.7)。
- [ ] **5.7 `highlight` 路径修正** — `HistoryItemDecorator.swift:191-216`。
  - 签名:`func highlight(_ query: String, _ ranges: [HighlightRange])`。
  - 早返:`guard !query.isEmpty, !title.isEmpty else { attributedTitle = nil; return }`(保留,锁 `03-LT-RENDER-01` 备注的"空 query/title 早返"已存在,确认保留)。
  - 截断:**`var attributedString = AttributedString(title.shortened(toChars: highlightLimit))`**,`highlightLimit` 与 `SearchEngine` 的 `regexpLimit`/`fuzzyLimit` **同一常量源**(新增 `enum TextLimits { static let highlight = 500; static let fuzzy = 5_000; static let regexp = 1_000 }`)。锁 `07-F-013`(搜索与高亮同切片)。
  - 换算:对每个 `HighlightRange(unit: .utf16)` 调 `range.toGrapheneRange(in: 截断后的 title)` 得 `Range<String.Index>?`;nil 则 `logger.debug("highlight range dropped: out of bounds")`(锁 `07-F-030` 静默丢 → 可观测)。
  - **memoize**:缓存 `(query, ranges) → AttributedString`(`03-LT-RENDER-01` 建议项);当 query/ranges 未变时直接复用,避免逐键重建。
- [ ] **5.8 resize 移出搜索关键路径** — `History.swift:33`。
  - 删除 throttle 块内的 `AppState.shared.popup.needsResize = true`;改为在 `updateItems` 后用 `Transaction(animation: nil)` 包裹的独立低优先级 `Task`(`priority: .utility`),仅当结果数变化超过阈值时才置位(`03-LT-MAIN-05`)。
- [ ] **5.9 `showSpecialSymbols` 只重建可见项标题** — `History.swift:88-94`。
  - 旧:对全 `items`(语义为可见项,但 `refreshVisibleItems` 会重算)调 `generateTitle()`;**但 `LT-MAIN-02` 指出对全 `all` 的隐患**。改为:
    - 只对**当前可见** `items`(或可视区)调 `item.regenerateTitleForSymbolToggle()`(新方法,见下);不触 `all` 的重生成。
    - `HistoryItemDecorator` 新增 `func regenerateTitleForSymbolToggle()`:在已缓存的"pre-special-symbols"标题上做符号替换,**不从 content 重算 prefix**(`03-LT-MAIN-02` 建议 2/3)。
  - `HistoryItemEngine.generateTitle`(`:67-79`):special-symbols 分支改单遍——用 `String.UnicodeScalarView` 一次遍历替换前导/尾随空格 + `\n`/`\t`,消除两个 `replacingOccurrences` 分配(`03-LT-TITLE-03`/`07-F-049`);或暴露 `formatTitleSpecialSymbols(_ title: String) -> String` 纯函数供 decorator 复用。
  - `updateTitle`(`:510-514`):批量包 `withTransaction` coalesce,避免逐项两次 SwiftUI diff(`03-LT-MEM-03`)。
- [ ] **5.10 截断单位统一** — `String+Shortened.swift`。
  - 现状:`shortened(to:)`(`:2-8`)按 grapheme;`Data.stringPrefix(maxBytes:)` 按 byte;`HistoryItemEngine`(`:97-105`)链式混用(`textPrefix` byte → `shortened` grapheme),`03-LT-UTF8-01`/`07-F-012`。
  - 改:
    - `func shortened(toChars maxLength: Int) -> String`(现 `shortened(to:)` 重命名;`guard count > maxLength` 改 `string.utf8.count` 快速判断或 `prefix(maxLength)` 避免 O(n) 全扫,锁 `03-LT-UTF8-02`)。
    - 新 `func shortened(toBytes maxBytes: Int) -> String?`(走 `data(using: .utf8)?.prefix(maxBytes)` + 边界对齐,委托既有 `Data.stringPrefix`)。
    - `HistoryItemEngine.previewableTextPrefix`(`:97-105`):`fileURLs`/`rtf`/`html`/`fallback` 各分支显式选单位(标题预览=grapheme;字节预算场景=byte),加注释说明。
  - `TextBoundaryTests`:CJK(每 char 3 byte)+ emoji(每 cluster 4+ byte)用例,锁两种单位的差异(对应 `B §5` 覆盖矩阵 `03-LT-UTF8-01`/`07-F-010`)。
- [ ] **5.11 Fuse 实例复用** — `SearchEngine` 持单一 `fuse`(`Search.swift:36` 现 per-`Search` 实例,`03-LT-SEARCH-06`);threshold 不可变,生命周期跟随 `History.shared`。
- [ ] **5.12 测试** — 见下"测试"小节。
- [ ] **5.13 全量验证** — `xcodebuild build` + `xcodebuild test` 通过;CJK/emoji 高亮位置正确;`showSpecialSymbols` toggle 不再触全量 `generateTitle`(用 spy/计数断言);性能闸门 `G-search` 绿。

## 测试
- 引用:`B §2`(`IngestorSpy` 不适用,本步用 `HistoryBuilder` 构 `[HistoryItem]` + `FixtureLoader` 取 `heavy_text.txt`/`emoji_grapheme_mix`/`utf8_cjk_2k`)、`§3`(数据流抽象:搜索入参=`SearchableDTO` 集合 + query,出参=`[SearchSnapshot]`,纯函数可测)、`§5` 覆盖矩阵。
- 新增:
  - `SearchHighlightIndexTests`(纯函数,5.1/5.2):emoji/CJK 高亮落位;`clamped(toCount:)`;UTF-16↔grapheme 换算;`range_pastTruncation`。
  - `TextBoundaryTests`(纯函数,5.10):`shortened(toChars:)` vs `shortened(toBytes:)` 在 CJK/emoji 上的长度差;`index(_:offsetBy:)` 替换为 `prefix` 后语义一致。
  - `SearchEngineTests`(模块,5.4/5.5/5.6):`PasteboardSimulator` 不需要;构造 `[SearchableDTO]`(1000 项,含 1 项 > 5000 char CJK + 1 项 emoji)→ 断言:(a) fuzzy 命中长串项且 ranges 单位 `.utf16`;(b) regex 在 >1000 char 项上仍命中(截断点与 highlight 对齐);(c) `mixedSearch` 短路:无正则元字符时只跑一次 fuzzy(用调用计数器);(d) `isLikelyUnsafeRegularExpression(超长串)` 返回 true;(e) `MainThreadProbe` 断言 `search` 期间主线程无 >16ms 占用。
  - `HistoryItemDecoratorHighlightTests`(集成,5.7):注入 `(query, ranges)` → 断言 `attributedTitle` 的 attribute runs 落在正确 grapheme;memoize 命中时不重建。
  - `ShowSpecialSymbolsScopeTests`(集成,5.9):toggle 前后,spy 断言 `regenerateTitleForSymbolToggle` 调用次数 == 可见项数(非 `all.count`);`generateTitle(从 content)` 未被调用。
- 闸门:`G-search`(history=1000,逐键搜索;主线程 < 16ms/键;后台 actor 承担;详见 `B §4`)。

## 验收标准
- **功能**:CJK / emoji / 混合脚本的高亮落在正确 grapheme(无错位、无静默丢失);长串(>5000 char)fuzzy / (>1000 char)regex 仍命中且高亮与搜索切片一致;`showSpecialSymbols` toggle 仅重建可见项标题;超长正则输入被拒。
- **复杂度(前→后)**:
  - 搜索:`O(n) main`(全量扫 + 高亮重建 per visible,`Search.swift:46-160` + `History.swift:25`/`:496`)→ `O(n) background`(可提前终止 / 取消旧 task);**主线程搜索调用从同步 O(n) 降为异步派发 O(visible)**。
  - `mixedSearch`:三遍扫描 main(`Search.swift:122-138`)→ 至多两遍 background(短路,5.4)。
  - 高亮重建:`O(all matches) main`(`updateItems` per visible,`History.swift:480-489`)→ `O(visible)` main(只对结果项 `highlight`)+ memoize 命中时 O(1)。
  - `shortened` 守卫:`O(n) count`(`String+Shortened.swift:3`)→ `O(maxLength)`(`prefix` / `utf8.count` 快判)。
- **管线**:搜索 main→background;`[SearchSnapshot]` 单向回主线程增量更新;resize 移出搜索关键路径(独立低优先级 task)。
- **I/O 限制**:`fuzzySearchLimit=5_000` / `regexpSearchLimit=1_000` / `highlightLimit=500` **同一常量源**且单位显式(`TextLimits`);正则输入上限 `regexpInputLimit=2_000`(`C §2` 输入限制表)。
- **不变性**:`A §7` 的"主线程无 >16ms 重活"(由 `G-search` 守卫)、"跨 actor 载荷 Sendable"(`SearchSnapshot`/`HighlightRange`/`SearchableDTO` 均值类型)、"截断/索引单位一致"(本步显式区分 grapheme/byte 并对齐搜索与高亮切片)在本步达成。OCR/标题 actor 化属 BS-2/3,C++ RE2 属 BS-8,本步不碰。

## Commit
`refactor(search): move search to background actor, fix UTF-16/highlight index alignment, unify truncation units, scope showSpecialSymbols rebuild`

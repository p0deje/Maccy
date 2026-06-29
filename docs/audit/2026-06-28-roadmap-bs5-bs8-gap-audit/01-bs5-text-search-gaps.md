# BS-5 文本搜索 — 缺口详审计(2026-06-28)

> 规范:`docs/audit/2026-06-14/roadmap/step-5-text-search.md`(13 小步 5.1–5.13)。
> 相关提交:`4fa4946`(feat bs5 search off-main)、`74bd873`(rename test ids)、`b6653fc`(pbxproj UUID typo fix)。
> 当前源码 HEAD `b6653fc`。本审计以源码现状为准。

## 总览

- **完成**:2(5.6 接线、5.11 Fuse 复用)
- **部分**:3(5.4 actor、5.12 测试、5.13 验证)
- **取代**:1(5.3 DTO,合理替代)
- **跳过**:7(5.1、5.2、5.5、5.7、5.8、5.9、5.10)
- **commit 诚实度**:**夸大** — `4fa4946` 声称 "5 naive bugs pre-identified + fixed",但其中 "bug-2 fix(Character not UTF-16)" 是空描述,且 07-F-010/07-F-013 两个核心正确性 bug 未修。
- **范围收窄本身是诚实的**:06-25 审计文档(`10-roadmap-alignment.md`)预先记录了"恢复 BS-5,范围可收窄:仅搬 Search.search 进 actor + DTOs"。**问题不在收窄,而在收窄后仍未做完承诺范围内的正确性 bug,且 commit message 夸大。**

## 逐小步

### 5.1 HighlightRange 模型(单位显式)+ clamped(toCount:) — ❌ 跳过
规范要求 `struct HighlightRange { lower; upper; unit: TextUnit }` + `enum TextUnit { utf16/grapheme/utf8 }` + `clamped(toCount:)`。
**现状**:全仓 grep `HighlightRange|TextUnit|clamped(toCount` = 0 命中。用裸 `Range<Int>` 替代,单位语义隐式。
**影响**:07-F-013(静默丢高亮)本应通过 clamp-and-log 变可观测,现仍静默 nil 丢。

### 5.2 UTF-16↔grapheme 换算 + emoji/CJK 测试 — ❌ 跳过
规范要求 `toGrapheneRange(in:)` 用 `String.UTF16View.Index(_offsetInCodeUnits:)` + `String.Index(_:within:)`,锁 07-F-010。
**现状**:该函数从未编写。`SearchActor.swift:132-135` 把 Fuse ranges 映射为 `$0.lowerBound..<($0.upperBound+1)`,apply 侧用 `index(offsetBy:)` — 与 legacy `Search.swift:89-95` **逐字节相同**。
**关键矛盾**:若 Fuse 返回 UTF-16 偏移(审计前提),则 actor 仍有 07-F-010 bug;若 Fuse 返回 Character 偏移,则 legacy 本来就对、"bug-2 fix" 是空描述。**两种情况下 commit 的 "bug-2 fix" 都不成立。**
**测试缺失**:`SearchHighlightIndexTests`(emoji/CJK 高亮落位)不存在。唯一 fuzzy emoji 测试 `SearchActorTests.swift:122-129` 只做边界检查(lower≥0, upper≤count),从不断言高亮落在正确 grapheme。

### 5.3 SearchSnapshot DTO(Sendable,不持 decorator 引用)— 🔄 取代(合理)
规范要求 `struct SearchSnapshot { objectID: UUID; ranges: [HighlightRange]; score: Double? }`。
**现状**:`SearchMatchDTO{id:UUID; title:String; score:Double?; ranges:[Range<Int>]}`(SearchDTOs.swift:39-44)满足"不持 decorator 引用"。额外带 `title` 供 apply 侧 equality guard。**合理替代。**

### 5.4 actor SearchEngine + SearchableDTO + mixed 短路 + regexpInputLimit — ⚠️ 部分
- ✅ `actor SearchActor`(SearchActor.swift:31)镜像 4 模式,actor 持有 Fuse。
- ❌ **mixed 短路未做**:`mixedSearch`(:67-78)仍三遍 `simple→regexp→fuzzy`,无"仅当 simple 空且 query 含正则元字符才跑 regex"的短路(03-LT-SEARCH-02 未改善)。
- ❌ **`regexpInputLimit=2000` 未加**:`isLikelyUnsafeRegularExpression` 无长度上限守卫(03-LT-SEARCH-04 未锁)。

### 5.5 Search.swift 薄壳 + isLikelyUnsafeRegularExpression 长度守卫 — ❌ 跳过
**现状**:`Search.swift` 只改了 1 个 token(`Mode` 加 `, Sendable`),未薄壳化。`isLikelyUnsafeRegularExpression`(:41-45)原样未动,无 `guard pattern.count <= regexpInputLimit`。legacy `Search.search` 仍是热路径(`refreshVisibleItems` 调用它)。

### 5.6 searchQuery.didSet 接后台 actor + updateItems(snapshots)— ✅ 完成
`History.swift` `performSearch`/`applySearchResults`(:817-876):生成代 guard + `searchTask.cancel()` + DTO 快照 + equality guard(title==dto.title 才 highlight)。clear/clearAll/delete 调 `invalidateInFlightSearch` bump 生成代。空 query 主线程同步短路(无闪烁)。**扎实且正确。**

### 5.7 highlight 路径修正([HighlightRange]+TextLimits+toGrapheneRange+memoize+clamp-and-LOG)— ❌ 跳过
**现状**(`HistoryItemDecorator.swift:362-387`):签名仍是 `(_ query, _ ranges:[Range<String.Index>])`;仍 `AttributedString(title.shortened(to: 500))` 硬编码 500;无 `TextLimits` 单一常量源;越界仍 `AttributedString.Index(within:)` 返回 nil 静默丢(无 log);无 memoize。
**影响**:
- 07-F-013 未修:正则命中在 600–1000 字符区间,highlight 截到 500 后 `AttributedString.Index(within:)` 对 500+ 偏移返回 nil → 静默丢高亮。
- 逐键重建 `attributedTitle` 无 memoize(03-LT-RENDER-01 建议项未做)。

### 5.8 resize 移出搜索热路径 — ❌ 跳过
**现状**:`History.swift:824`(空路径同步置位)与 `:875`(apply 同步置位)仍 `AppState.shared.popup.needsResize = true`,在搜索关键路径同步执行。规范要求移到 `.utility` Task 且按结果数变化阈值置位(03-LT-MAIN-05)。

### 5.9 showSpecialSymbols 只重建可见项 — ❌ 跳过
**现状**:`History.swift:192-198` 仍 `for item in items { updateTitle(item: item, title: item.item.generateTitle()) }`;`HistoryItemEngine.swift:64-65` 仍两个 `replacingOccurrences`(03-LT-TITLE-03/07-F-049)。无 `regenerateTitleForSymbolToggle()`。**LT-MAIN-02 全量 generateTitle 隐患仍在。**

### 5.10 截断单位统一 — ❌ 跳过
**现状**:`String+Shortened.swift` 未改,只有 `shortened(to:)` grapheme 版;无 `shortened(toChars:)/(toBytes:)`,无 deprecation。`HistoryItemEngine.previewableTextPrefix`(:86,90,92,94)仍链式混用 byte→grapheme(03-LT-UTF8-01/07-F-012)。

### 5.11 Fuse 实例复用 — ✅ 完成
`SearchActor.swift:32` 单一 actor 持有 fuse(03-LT-SEARCH-06)。

### 5.12 测试(5 文件 + MainThreadProbe<16ms + G-search 闸门)— ⚠️ 部分
**现状**:仅 `SearchActorTests.swift`(4 模式等价 + emoji/CJK 边界 + empty-match + unsafe-pattern)。**缺 4 个**:`SearchHighlightIndexTests`、`TextBoundaryTests`、`SearchEngineTests`、`HistoryItemDecoratorHighlightTests`、`ShowSpecialSymbolsScopeTests`(实为 5 个全缺)。无 MainThreadProbe <16ms 断言。

### 5.13 全量验证 — ⚠️ 部分
- ✅ CI 绿(run `28323209640`,10/10)。
- ❌ `TextSearchPerformanceTests.swift:13` 自述 "Baseline-only (no `<16 ms` assertion yet)",且**直接测 legacy `Search()` 而非新 actor** → off-main 收益未被 CI 证明/闸门。
- ❌ CJK/emoji 高亮落位、showSpecialSymbols 范围均无断言。

## 最严重的两个正确性缺口

### 缺口 A:07-F-010 高亮错位未真正修复(commit 夸大)
- 规范的换算函数从未写;actor fuzzy-range 处理与 legacy 逐字节相同。
- 唯一能证伪的 emoji fuzzy 测试只做边界检查。
- **行动**:写 `fuseRange_emoji_landsOnCorrectGrapheme`(title `"x😀y"`,query `"y"`,断言高亮落 `y` 而非 `😀` 尾字节)。若 Fuse 返回 UTF-16 → 补 `toGrapheneRange`;若返回 Character → 删除 commit/comment 里夸大的 "bug-2 fix" 描述。

### 缺口 B:07-F-013 搜索/高亮截断不一致静默丢高亮
- 搜索截断 5000(fuzzy)/1000(regex),高亮截断 500,不同源无 `TextLimits`。
- 正则命中在 600–1000 字符区间,highlight 侧 `AttributedString.Index(within: 截到500的串)` 返回 nil 静默丢。
- **行动**:新增 `enum TextLimits { static let highlight=500; static let fuzzy=5_000; static let regexp=1_000 }`,highlight 与搜索侧同源;越界改 clamp + `logger.debug("highlight range dropped: out of bounds")`。

## 建议补全(按价值/风险排序)

1. **修缺口 B(07-F-013)**:`TextLimits` 单一常量源 + clamp-and-log。改动小、纯正确性。
2. **核实缺口 A(07-F-010)**:写 emoji fuzzy 落位断言;按结果决定补 `toGrapheneRange` 还是删夸大注释。
3. **5.9 showSpecialSymbols**:加 `regenerateTitleForSymbolToggle()` 只重建可见项 — LT-MAIN-02 真实主线程隐患。
4. **5.8 resize**:移到 `.utility` Task,按结果数变化阈值置位。
5. **5.13 G-search 闸门**:让 `TextSearchPerformanceTests` 测 actor 路径 + 加 <16ms 主线程断言。
6. **5.4 mixed 短路 + regexpInputLimit**:低风险增量优化。
7. **文档**:更新 step-5 勾选框(2✓ 3⚠ 1🔄 7❌),把收窄决策与遗留缺口记入 in-step 偏差注释。

## 证据索引
- `Maccy/SearchActor.swift:31,32,67-78,132-135` — actor、fuse、mixedSearch(3 遍)、fuzzy range 映射(= legacy)
- `Maccy/SearchDTOs.swift:39-44` — SearchMatchDTO
- `Maccy/Search.swift:7,41-45` — 仅 +Sendable;isLikelyUnsafeRegularExpression 未动
- `Maccy/Observables/History.swift:192-198,817-876` — showSpecialSymbols 未改;performSearch/applySearchResults 接线 ✓;needsResize 同步置位
- `Maccy/Observables/HistoryItemDecorator.swift:362-387` — highlight 签名未改、硬编码 500、无 memoize、静默丢
- `Maccy/Extensions/String+Shortened.swift` — 未改
- `Maccy/Engine/HistoryItemEngine.swift:64-65,86-94` — 两个 replacingOccurrences、混用单位
- `MaccyTests/SearchActorTests.swift:122-129` — fuzzy emoji 仅边界检查
- `MaccyTests/TextSearchPerformanceTests.swift:13` — baseline-only,测 legacy Search()
- commit `4fa4946` body — "5 bugs fixed" 夸大

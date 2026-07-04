# BS-5 搜索重设计(2026-07-04,grill-with-docs 产物)

> **本文件是 BS-5「搜索重设计」的执行计划**,由 `/grill-with-docs` 会话产出。
> 基线:HEAD `6880f28`(BS-6/7/8 完成后)。设计以**当前源码 + 3-agent 实测**为准。
> 配套:`decisions.md`(6 个 ADR)、`glossary.md`(术语 / finding-id 词汇)。
> 上游权威:`docs/audit/2026-06-14/roadmap/step-5-text-search.md`(冻结 spec)、`docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/01-bs5-text-search-gaps.md`(缺口)、`docs/audit/architecture-and-root-causes.md` §2.3(架构)。

## 背景:为何「重设计」而非「补全冻结 spec」

冻结 spec(06-14 `step-5-text-search.md`)的 13 小步聚焦「搜索后台化 + 高亮 UTF-16/grapheme 正确性 + 截断单位统一 + showSpecialSymbols 范围收窄」。06-28 缺口审计判定仅 2/13 完成,且 commit `4fa4946` 的 "bug-2 fix" 夸大。

用户 2026-07-04 指令**扩展了范围**(超出冻结 spec):
1. **搜索框右侧加按钮,循环切换搜索方式,与设置联动**(冻结 spec 无此 UI)。
2. **真正的全文搜索**——匹配项的**完整剪贴板内容**(可达数十 KB),而非 ≤1000 字符的标题预览。
3. **匹配在预览面板高亮**(滚动到/居中匹配,带上下文)。
4. **每个搜索方式的时间/空间复杂度最优**——「又快又省」。

故本计划是**重设计**,冻结 spec 作为正确性参考(Track 1 仍兑现其核心正确性缺口),但其搜索范围/索引/UI 三轴均被本次扩展重塑。

## ⚠️ 用户决策(2026-07-04,本会话内做出,非代理)

四个真实叉点,用户已答:

| 叉点 | 用户决策 | ADR |
|---|---|---|
| 搜索框按钮位置 | **替换左侧放大镜**(点击循环,`✕` 清除键留右侧) | ADR-1 |
| 模式视觉 | **短文本缩写** `EX`/`FZ`/`RE`/`MX` | ADR-1 |
| 交互 | **仅点击循环**(无右键菜单;直接跳转走设置) | ADR-1 |
| 效率/索引 | **先无索引 + 测量,按需再加**(经验式) | ADR-2 |
| Fuzzy 全文深度 | **标题 + 正文前缀(封顶 ~5000)** | ADR-3 |
| 预览高亮/滚动 | **分阶段:Stage 1 预览窗内高亮(廉价)→ Stage 2 NSTextView 深度匹配滚动+高亮** | ADR-4 |
| 全文 body 上限 | **32KB(覆盖 31KB heavy_text fixture),`Defaults` 可配** | ADR-5 |
| `searchText` 持久化 + 语料移 actor | **持久化列 + SearchActor 持 cache + StoreEvent 维护** | ADR-6 |
| 搜索派发框架 | **采用 swift-async-algorithms `debounce`,删手写 `Throttler`** | ADR-7 |

> 详见 `decisions.md`。所有 ADR 用户已确认;推翻 = 改 ADR + 调整对应小步。

## 一、当前真值(HEAD `6880f28`,3-agent 验证后)

### 1.1 搜索/内容管线现状

| 维度 | 现状(源码证据) | 缺口 |
|---|---|---|
| 搜索语料 | **仅标题**(`decorator.title` ≤1000;`History.swift:857` `all.map { SearchCorpusItem(id:,title:) }`) | 全文缺失 |
| 全文存储 | **从未存储/计算**;三层截断:标题 1000(`HistoryItem.swift:13`)、textPreview 3000(`:20-23`)、字符串字节上限(`ClipboardDataProcessor.stringPrefix`) | 无 `searchText` 列 |
| SearchActor | 普通 `actor`,**无 ModelContext**(`SearchActor.swift:30`);只收 `[SearchCorpusItem]` | 不能 fault 内容 |
| 主线程投影 | 每按键 `all.map { … }`(O(n) DTO 分配 + String retain,**在 main**,`History.swift:857`);apply 路径 `all.first(where:)` 每 match O(n)(`:879`) | 全文下投影税线性放大 → 必须移语料到 actor |
| 富文本提取 | RTF/HTML 走 `NSAttributedString(rtf:/html:)`,**主线程亲和**,封顶 512KB(`Clipboard.swift:14`,`HistoryItemEngine.swift:199-216`);`.string`/`.fileURL` 廉价(Foundation,任意 actor) | 提取须在 ingest 一次性做 |
| 提取优先级 | **first-match-wins**(fileURL→string→rtf→html,`HistoryItemEngine.swift:90-113`) | 多 rep 不同文本的边角情形(罕见;macOS 约定 .string=规范文本) |
| 索引基础设施 | `SignatureIndex`(`Ingest/SignatureIndex.swift`)是**全 blob xxh3 指纹索引,不可复用为文本索引**;但生命周期模板完美(actor 持 Sendable struct `[Key:Set<ID>]` + `register/remove/merge(StoreEvent)`) | 无 n-gram/token 工具,须自建 |
| 语料变更钩子 | 增:`StoreEvent.added/merged`(ingest→`maintainDedupIndex`→`onEvent`→`History.consume`);**删:无事件**(`History.delete/clear/clearAll/limitHistorySize` 直改 `all`,但 `consume` 已有 `.removed/.cleared` 分支) | 删/清须补发事件 |
| 预览面板 | `PreviewItemView`:图片=`Image`,其余=普通 `ScrollView { Text(item.text) }`(`PreviewItemView.swift:55-58`);**无 ScrollViewReader、无 NSTextView、无范围高亮**;body 封顶 `textPreviewLimit=3000` | 高亮廉价(AttributedString);深度滚动须 NSTextView |
| 预览状态钩子 | `SlideoutController.previewedItem`(`:94`,无 didSet);`leadHistoryItem.didSet` **是错位钩子**(sticky-chase 已解耦) | 须在 `previewedItem` 注入 |

### 1.2 BS-5 冻结 spec 缺口(继承 06-28 审计,HEAD 复核)

| 缺口 | finding-id | 现状 | Track |
|---|---|---|---|
| 高亮 UTF-16/grapheme 错位 | 07-F-010 | SearchActor fuzzy 路径(`:132-135`)直传 Fuse 整数 offset;simple/regexp 路径(`:100-101,164-169`)用 `String.distance`。**Fuse 返回 UTF-16 还是 grapheme 未经验证**(测试仅边界检查) | T1.1 经验闸门 |
| 搜索/高亮截断不一致→静默丢 | 07-F-013 | 搜索在 ≤1000 标题上跑,高亮截 500(`HistoryItemDecorator.swift:368`),`AttributedString.Index(within:)` 对 500+ 偏移返 nil 静默丢 | T1.2 `TextLimits` 单源 |
| mixed 三遍无短路 | LT-SEARCH-02 | `mixedSearch`(`SearchActor.swift:64-75`)仍 simple→regexp→fuzzy | T1.3 |
| resize 在搜索热路径 | LT-MAIN-05 | `History.swift:847,898` 同步 `needsResize=true` | T1.7 |
| showSpecialSymbols 全量重生成 | LT-MAIN-02 | `History.swift:192-198` 对全 `items` 调 `generateTitle()` | T1.6 |
| 截断单位不统一 | LT-UTF8-01/07-F-012 | `String+Shortened.swift` 仅 grapheme 版;`previewableTextPrefix` 链式混用 byte→grapheme | T1.2(部分) |
| 死限制 | — | `fuzzySearchLimit=5000` 永不命中(标题 ≤1000) | T1.8 删 |
| G-search 闸门 | — | `TextSearchPerformanceTests:13` baseline-only、测 legacy `Search()` 非 actor | T2.7 |

## 二、设计总览:三轨 + 经验式索引叉点

```
Track 0  模式循环按钮(纯 UI,独立,先发)            ── BS-5R.0  编译边界
Track 1  标题域正确性(兑现冻结 spec 核心缺口)      ── BS-5R.1  编译边界
Track 2  全文搜索(actor 持语料 + 正文扫描 + 测量) ── BS-5R.2  编译边界
         └─ 2.7 G-search 测量 → 若延迟不可接受 → 开 Track 2-index(ADR-2)
Track 3  预览高亮 + 滚动(Stage1 SwiftUI / Stage2 NSTextView)── BS-5R.3  编译边界
```

**依赖**:T2 的正文 offset 是 T3 的输入 → T3 在 T2.3 之后。T0/T1 独立,可先行。

**复杂度预算**(前→后;详 `A-architecture-target.md §6` + 本计划 ADR-2):

| 操作 | 当前 | 目标(本设计) |
|---|---|---|
| 搜索/按键(主线程) | O(n) `all.map` 在 main + O(n) 扫描在 main(legacy)/actor | **O(1) main**(仅发 (query,mode,gen));扫描全在 actor |
| 搜索/按键(actor 总延迟) | O(n·标题)(actor) | O(n·正文_cap)(无索引);**O(matches·verify)** 若开索引 |
| 全文匹配覆盖 | 仅 ≤1000 标题 | **≤32KB 正文**(封顶,ADR-5) |
| 主线程纯净性 | `G-search` 未闸门 actor 路径 | **`G-search` 测 actor 路径,main <16ms/键** |
| 预览大文本 | `Text` 急切全量布局(故封顶 3000) | **NSTextView 惰性布局**(封顶解除,live 内存有界) |

> **关键不变量**:`<16ms` 闸门针对**主线程**——off-main 扫描(actor 承担)已满足,无索引下 actor 延迟 ~5–30ms 被 0.2s `Throttler` + `searchGeneration` 取消掩盖(见 ADR-2)。这是「无索引仍达标」的根据。

## 三、Track 0 — 模式循环按钮(BS-5R.0)

> ADR-1。纯 UI,绑定 `Defaults[.searchMode]`,与设置 Picker 自动联动(同一 key)。

### 受影响文件
- 改:`Maccy/Views/SearchFieldView.swift` — 左侧 `Image(magnifyingglass)` 替换为模式按钮(`Button` + 短文本缩写 + tooltip);点击循环 `CaseIterable` 顺序 `exact→fuzzy→regexp→mixed→exact`。
- 改:`Maccy/Search.swift` — `Mode` 加便捷 `var abbreviation: String`(`"EX"/"FZ"/"RE"/"MX"`)+ `next` 循环;本地化 tooltip key(走 `*.lproj`,BartyCrouch/Weblate 管理,**勿手编**)。

### 小步骤
- [ ] **0.1 模式按钮 + 循环** — `SearchFieldView`:左图标位改为 `Button { cycleMode() } label: { Text(mode.abbreviation) }`,`@Default(.searchMode) private var searchMode`;`cycleMode` = `searchMode = searchMode.next`。`Mode.abbreviation`/`Mode.next` 加于 `Search.swift`。tooltip 用 `NSLocalizedString("SearchModeTooltip_\(mode)", …)` 模式名 + "click to change"。
  - **不变性**:点击不改 query、不触发搜索(仅切模式;下次按键或 `.onChange(of: searchMode)` 触发重搜——后者须接:`History` 监听 `Defaults[.searchMode]` 变化重跑 `performSearch`,见 0.2)。
- [ ] **0.2 模式切换触发重搜** — `History`:`.onChange(of: Defaults[.searchMode])`(经 `@Default` 观察)→ 若 `searchQuery` 非空调 `performSearch()`(空 query 无需重搜)。
  - 测试 `SearchFieldCycleTests`:循环顺序正确;点击写 `Defaults[.searchMode]`;设置 Picker 与按钮同 key(改一端另一端同步);空 query 点击不搜;非空 query 切模式重搜;`accessibilityLabel`/`accessibilityValue` 正确(VoiceOver)。
- [ ] **0.3 本地化占位** — `*.lproj/GeneralSettings.strings` 加 tooltip key(BartyCrouch 增量,英文 + 现有语种)。
- [ ] **BS-5R.0 CI gate**(push、~11min、poll ≤每 2min)。

## 四、Track 1 — 标题域正确性 + 派发基础设施(BS-5R.1)

> 兑现冻结 spec 核心正确性缺口;**与全文范围正交**(全文搜索同样依赖这些修复)。低风险。**T1.0 为派发基础设施(ADR-7,系统性),先于其他正确性项。**

### 小步骤
- [ ] **1.0 搜索派发迁移(ADR-7):`swift-async-algorithms` `debounce` 取代手写 `Throttler`** — 加 SPM 依赖 `AsyncAlgorithms`(1.1.3,镜像 `fuse-swift` 的 pbxproj 4 段注册 + `Package.resolved`);`History.searchQuery.didSet` 改为向 `AsyncStream<String>` 产出;常驻消费 `Task` 迭代 `stream.removeDuplicates().debounce(for:.milliseconds(200))` 调 `performSearch`;删 `Maccy/Throttler.swift` + `History` 4 处调用点。**语义变更:leading-edge+trailing → 纯 trailing debounce**(记行为变更)。可测性:debounce 间隔经 `Clock` 注入。
  - **为何先做**:系统性基础设施(用户 2026-07-04「更系统、非补丁」);为未来 `StoreEvent` 流 + ingest 写合并(`no-coalesce-of-ingest-writes`)铺路(同框架 `chunks`/`debounce`/`combineLatest`)。
  - 测试 `SearchDispatchDebounceTests`:debounce 合并连续按键;`removeDuplicates` 不触发相同值;消费 Task 可确定性 await(注入 clock/0 间隔)。
- [ ] **1.1 Gap A 经验闸门(07-F-010)** — `MaccyTests/SearchHighlightIndexTests.swift`:`fuseRange_emoji_landsOnCorrectGrapheme`(title `"x😀y"`,query `"y"`,断言高亮落 `y` 而非 `😀` 尾字节)+ CJK 用例 + `range_pastTruncation`。
  - **判定**:Fuse 1.4.0 若返回 grapheme offset → actor 路径已正确,**删 `4fa4946` 夸大的 "bug-2 fix" 注释/commit 引用**(记偏差);若返回 UTF-16 → 加 `toGrapheneRange(in:)`(`String.UTF16View.Index(_offsetInCodeUnits:)` + `String.Index(_:within:)`)转换。**CI 是判官**(无本地工具链)。
- [ ] **1.2 Gap B `TextLimits` 单源(07-F-013)** — 新 `Maccy/Search/TextLimits.swift`:`enum TextLimits { static let titlePreview=1_000; static let highlight=1_000; static let fuzzy=5_000; static let regexp=1_000; static let searchBody=32_000 }`。`HistoryItemDecorator.highlight`(`:368`)改 `shortened(to: TextLimits.highlight)` 且与搜索侧同源;越界改 **clamp + `logger.debug("highlight range dropped: out of bounds")`**(不再静默 nil 丢)。
  - 测试:正则命中 600–1000 区间高亮不丢;`highlight` 与 `regexp` 限制同源(改一处)。
- [ ] **1.3 mixed 短路(LT-SEARCH-02)** — `SearchActor.mixedSearch`:仅当 simple 空**且** query 含正则元字符(`[\^\$.|?*+()[]` 之一)才跑 regexp;否则直接 fuzzy。三遍 → 至多两遍。
  - 测试:调用计数器断言无元字符时只跑一次 fuzzy。
- [ ] **1.4 regexp 输入长度守卫(LT-SEARCH-04)** — `Search.isLikelyUnsafeRegularExpression`(`Search.swift:46`)加 `guard pattern.count <= 2_000 else { return true }`。
  - 测试:>2000 字符 pattern 返回 true(拒编译)。
- [ ] **1.5 高亮 memoize(03-LT-RENDER-01)** — `HistoryItemDecorator`:缓存 `(query, ranges) → AttributedString`;未变则复用,避免逐键重建。
  - 测试:注入相同 (query,ranges) 两次,第二次不重建(spy 计数)。
- [ ] **1.6 showSpecialSymbols 范围收窄(LT-MAIN-02)** — `History` toggle 只对当前可见 `items` 调新 `regenerateTitleForSymbolToggle()`(在已缓存 pre-special-symbols 标题上做符号替换,不从 content 重算 prefix);`HistoryItemEngine` special-symbols 分支单遍化(`UnicodeScalarView` 一次遍历替两个 `replacingOccurrences`)。
  - 测试 `ShowSpecialSymbolsScopeTests`:spy 断言调用次数 == 可见项数(非 `all.count`);`generateTitle(从 content)` 未被调。
- [ ] **1.7 resize 移出搜索热路径(LT-MAIN-05)** — `History` 删搜索路径内同步 `needsResize=true`(`:847,898`);改 `updateItems` 后用 `Transaction(animation:nil)` 包裹的 `.utility` Task,仅当结果数变化超阈值才置位。
  - 测试:搜索期间 `needsResize` 不在搜索 Task 内同步置位。
- [ ] **1.8 删死限制** — `fuzzySearchLimit=5000`(`Search.swift:41`、`SearchActor.swift:32`)在全文设计(Track 2)中由 `searchBody` 常量取代;此处先记「标题域永不命中」偏差,实际删在 T2 重构时。
- [ ] **1.9 截断单位统一(LT-UTF8-01)** — `String+Shortened.swift`:`shortened(to:)` 重命名 `shortened(toChars:)`(grapheme);新增 `shortened(toBytes:)`(委托 `Data.stringPrefix`);旧名 `@available(*, deprecated, renamed:)`。`previewableTextPrefix` 各分支显式选单位 + 注释。
  - 测试 `TextBoundaryTests`:CJK(3 byte/char)+ emoji(4+ byte/cluster)两种单位长度差;`prefix` 替 `index(offsetBy:)` 语义一致。
- [ ] **更新 `step-5-text-search.md`** 勾选(本轨兑现 5.1/5.2/5.7/5.8/5.9/5.10 的标题域部分)+ 偏差注释。
- [ ] **BS-5R.1 CI gate**。

## 五、Track 2 — 全文搜索(BS-5R.2)

> ADR-2(无索引经验式)/ADR-3(fuzzy 深度)/ADR-5(body 封顶)。核心:语料移到 actor + 持久化 `searchText` 列 + off-main 正文扫描。

### 受影响文件
- 新:`Maccy/Models/HistoryItem+SearchText.swift` 或加列于 `HistoryItem` — `@Model` 属性 `var searchText: String?`(nullable,懒回填)。
- 改:`Maccy/Ingest/ClipboardIngestor.swift` — ingest 一次性提取全文(优先级同 title,但**不截断**;`.string`/`.fileURL` off-main 于 `@ModelActor` 提取,RTF/HTML 沿用现有 `MainActor.run { … }` hop,封顶 512KB),写列于单事务。
- 改:`Maccy/SearchDTOs.swift` — `SearchCorpusItem` 弃用(语料移到 actor);`SearchMatchDTO.ranges` 语义改为「**正文 grapheme offset**」(+ `inBody: Bool` 标记命中在标题前缀内还是正文)。
- 改:`Maccy/SearchActor.swift` — 持 `[ItemID: String]` body cache(惰性 bootstrap 自 `searchText` 列,经 `@ModelActor` 后台 context fault);`search(query:mode:)` 不再收 `within:`,查自身 cache。
- 改:`Maccy/Observables/History.swift` — `performSearch` 删 `all.map` 投影(改为 `(query,mode,generation)` 投递);删/清/限容 mutators 发 `StoreEvent.removed/.cleared`(接既有 `consume` 分支)。

### 小步骤
- [ ] **2.1 `searchText` 持久化列 + 迁移** — `HistoryItem.searchText: String?`(lightweight migration,模板同 BS-8.5 `fingerprint` 列)。ingest 提取器 `previewableTextPrefix(maxLength:)` 新增**不截断**变体 `searchableBody()`(优先级 fileURL→string→rtf→html;`.string`= `String(data:encoding:.utf8)` 全量;RTF/HTML=`NSAttributedString(rtf:/html:).string` 全量,512KB 守卫;image=`""`),写列于 ingest 单事务。
  - **既有行懒回填**:类比 BS-8.5,可在 ingest actor 后台 context 命中 nil 行时回填(或冷开批量,节流);**首版接受「老行 searchText=nil → 退化到标题搜索」**,回填作 follow-up(记偏差,同 8.5 历史决策)。
  - 测试 `SearchTextMigrationTests`:新行 `searchText` 非空;重启后非空(lightweight migration);RTF/HTML 项 `searchText` 为提取纯文本;<512KB 提取、≥512KB 退化;image 项为 `""`。
- [ ] **2.2 语料移到 actor + StoreEvent 维护** — `SearchActor` 持 `private var bodyCache: [ItemID: String]`(惰性:首次 `search` 前经 `@ModelActor` 后台 context fault 全部 `searchText`,或增量)。`History.consume` `.added/.merged` 时投递 `(id, searchText)` 给 actor `register`;**新增** `History.delete/clear/clearAll/limitHistorySize` 发 `StoreEvent.removed(id)/.cleared`(接 `consume` 既有分支 → 投递 actor `remove`)。
  - **不变性**:`@Model` 不跨域;`searchText` 作 `String`(Sendable)跨 actor。`mainContext` 从不 reset → cache 必须在 actor(不在 main),规避滞留(架构 §4.2)。
  - 测试 `SearchCorpusOwnershipTests`:增删清后 cache 计数与 `all` 一致(随机化操作序列,属性测试);`performSearch` 不再分配 `all.map`(spy/计数);冷启后首次搜索 bootstrap 正确。
- [ ] **2.3 全文 exact + regexp(正文扫描,off-main)** — `SearchActor.simpleSearch`/`regexpSearch` 在 `bodyCache[id]` 上跑(扫描全 body,封顶 `TextLimits.searchBody=32_000`);`SearchMatchDTO` 携带正文 grapheme offset(`String.distance`)。
  - **取消 actor 内 fuzzy/regexp 截断**(`fuzzySearchLimit`/`regexpSearchLimit`)——正文扫描用 `searchBody` 封顶(ADR-5)。
  - 测试 `FullTextSearchTests`:heavy_text(31KB)中 query 命中字节 ~5000/10000/20000 处,断言找到 + offset 正确;空 body(image)不命中;封顶外(>32KB)不命中(记偏差)。
- [ ] **2.4 Fuzzy 标题 + 正文前缀(ADR-3)** — `SearchActor.fuzzySearch`:语料 = `title + body.prefix(5_000)`(Fuse DP 成本有界 ~ms)。命中 offset 标记 `inBody`。
  - 测试:body 前缀内 fuzzy 命中;超出 5000 前缀的 fuzzy 不命中(精确命中仍由 exact/regexp 覆盖)。
- [ ] **2.5 mixed 全文 + 短路** — exact(body)→ regexp(body,含元字符守卫)→ fuzzy(title+prefix),first-non-empty-tier 返回。复用 T1.3 短路逻辑。
  - 测试:三模式 mixed 优先级 + 短路(无元字符跳 regexp)。
- [ ] **2.6 body 封顶 + Defaults(ADR-5)** — `Defaults[.searchBodyLimit]`(默认 32_000,范围 [1_000, 256_000]);超封顶的 body 不索引/不扫描(退化标题搜索)。设置 pane 加控件(可选;首版 defaults-only)。
  - 测试:封顶生效;封顶外命中不返回;改 Defaults 后重建 cache。
- [ ] **2.7 G-search 测量(经验式索引叉点,ADR-2)** — `TextSearchPerformanceTests` 改测 **actor 路径**(非 legacy `Search()`);场景 `n=1000`(heavy_text × 多倍 + 混合小项);`MainThreadProbe` 断言 main <16ms/键;`measure` 记 actor 总延迟。
  - **决策点**:若 actor 总延迟 P95 < ~30ms(被 throttle 掩盖)→ **不开索引**(ADR-2 现状);若 > ~50ms 不可接受 → 开 **Track 2-index**(trigram,见下)。记测量结果于本文件进度日志 + `decisions.md` ADR-2。
- [ ] **更新 `step-5-text-search.md` + `architecture-and-root-causes.md` §2.3** — 全文范围偏离冻结 `O(n) 标题` → `O(n·正文_cap)`;记 ADR-2/3/5。
- [ ] **BS-5R.2 CI gate**。

### Track 2-index(条件,仅 T2.7 测量不达标时)
- [ ] **2.8 trigram 索引** — `SearchActor` 持 `trigramIndex: [String: Set<ItemID>]`(模板克隆自 `SignatureIndex`:`register/remove/merge(StoreEvent)`);tokenizer 复用 `validUTF8PrefixLength`(字节边界安全,`Processor/ClipboardByteProcessor.cpp`);query→trigrams→交集候选→在 body 上 verify 取 offset。exact/regexp 候选加速;**fuzzy 仍走标题+前缀**(trigram 不加速 fuzzy)。
  - 测试 `TrigramIndexTests`:候选集正确;增删维护;交集退化(无公共 trigram)返回空。
  - **内存再核**:索引 ~2–4× body 字节;封顶 32KB × n → 须在 ADR-2 复核内存预算(可能需降封顶或 NSCache evict)。

## 六、Track 3 — 预览高亮 + 滚动(BS-5R.3)

> ADR-4(分阶段)。依赖 T2.3 的正文 offset。**关键洞察**:3000 字符封顶是 SwiftUI `Text` 急切布局的权宜;NSTextView 惰性布局解除之。

### 受影响文件
- 改:`Maccy/Views/PreviewItemView.swift` — 文本分支 `Text(item.text)` → Stage1 `Text(attributedString)` / Stage2 `PreviewTextRep`(NSTextView)。
- 改:`Maccy/Observables/HistoryItemDecorator.swift` — 加 `previewHighlight: (query: String, ranges: [Range<String.Index>])?` 状态 + 全文 `previewBody` 访问器(超 `textPreviewLimit`)。
- 改:`Maccy/Observables/SlideoutController.swift` — `previewedItem` 加 didSet,注入"滚动到匹配"。
- 改:`Maccy/Observables/History.swift` — `applySearchResults` 把正文 offset 推到 **previewed** decorator(非全 items)。

### 小步骤
- [ ] **3.1 Stage 1:预览窗内高亮(廉价 SwiftUI)** — `HistoryItemDecorator` 加 `previewHighlight` 状态;`PreviewItemView` 文本分支:`Text(attributedString)`(复用 `highlight()` 的 AttributedString 范围样式,`HistoryItemDecorator.swift:369-384`),对落在 `textPreviewLimit`(3000)窗内的匹配高亮。`SlideoutController.previewedItem` didSet → 调 `applyPreviewHighlight`。`applySearchResults` 仅推到 previewed decorator。
  - **范围**:窗内匹配高亮;**深度匹配(>3000)仍被找到(item 进结果)但不滚动**——Stage 2 解决。
  - 测试 `PreviewHighlightTests`:窗内匹配高亮 attribute run 落对 grapheme;深度匹配 item 仍在结果但 previewHighlight 不越界;`PreviewRefreshUITests` 保持绿(identity 契约)。
- [ ] **3.2 Stage 2:NSTextView 深度匹配滚动 + 高亮** — 新 `Maccy/Views/PreviewTextRep.swift`(`NSViewRepresentable` 包 `NSTextView`):`NSTextStorage` 持全文 `searchText`(lazy layout,解封顶);`addAttributes(.backgroundColor, range:)` 高亮匹配;`scrollRangeToVisible(matchRange)` 滚动到匹配。`PreviewItemView` 文本分支切到 `PreviewTextRep`(当 `previewHighlight != nil` 或 body > textPreviewLimit)。
  - **不变性**:lazy layout → live 内存有界(仅可见行 layout),与 `Text` 急切布局不同;`scrollRangeToVisible` 精确字符偏移;`NSTextStorage` 属性高亮原生支持。image 分支不动。
  - 测试 `PreviewTextRepTests`:31KB body 全量加载内存有界(`measure(XCTMemoryMetric)`);深度匹配(offset 20_000)滚动到位 + 高亮;多匹配高亮 + 滚首个;`PreviewRefreshUITests` 绿;VoiceOver 可访问。
  - 偏差:NSTextView 引入 AppKit 桥(项目首个 NSTextView);`PreviewRefreshUITests` identity 契约须保持。
- [ ] **更新 `architecture-and-root-causes.md` §2.5(UI/渲染)** — 记预览 NSTextView 化。
- [ ] **BS-5R.3 CI gate**。

## 七、测试清单(已有 vs 待补)

**已有可复用**(不重建):`PasteboardSimulator`/`HistoryBuilder`/`FakeClock`/`IngestorSpy`/`FixtureLoader`/`MainThreadProbe`(Support/ 全 real);`SearchActorTests`(15 法)、`SearchTests`、`TextSearchPerformanceTests`(改测 actor)、`HistoryDecoratorTests.testHighlight`(`:263-275`,预览高亮模板)、`testLargeTextPreviewIsBounded`/`testLargeTextPreviewBenchmark`、`HistoryItemTests`(`text`/`rtfData`/`htmlData`/`fileURLs` 访问器)、`DtoTests`/`DtoRoundTripTests`、`PerformanceTestCase` 基类、`PreviewRefreshUITests`。

**待补**:

| 文件 | 轨 | 关键断言 |
|---|---|---|
| `SearchFieldCycleTests` | T0 | 循环顺序;Defaults 同步;空 query 不搜;切模式重搜;VoiceOver label |
| `SearchHighlightIndexTests` | T1.1 | emoji/CJK 高亮落位;`range_pastTruncation`;**Fuse offset 经验判定** |
| `TextBoundaryTests` | T1.9 | `shortened(toChars:)` vs `(toBytes:)` CJK/emoji 长度差 |
| `ShowSpecialSymbolsScopeTests` | T1.6 | toggle 重建调用数 == 可见项数(非 all) |
| `SearchTextMigrationTests` | T2.1 | 新行非空;重启非空;RTF/HTML 提取;512KB 退化;image 空 |
| `SearchCorpusOwnershipTests` | T2.2 | 增删清后 cache 一致;无 per-keystroke `all.map`;冷启 bootstrap |
| `FullTextSearchTests` | T2.3 | 31KB 命中 offset 正确;image 不命中;封顶外不命中 |
| `FullTextFuzzyTests` | T2.4 | body 前缀 fuzzy 命中;超 5000 不命中 |
| `SearchBodyLimitTests` | T2.6 | 封顶生效;Defaults 改后重建 |
| (T2.7 改) `TextSearchPerformanceTests` | T2.7 | actor 路径;main <16ms;n=1000;P95 延迟记录 |
| `TrigramIndexTests` | T2.8(条件) | 候选集;增删维护;交集退化 |
| `PreviewHighlightTests` | T3.1 | 窗内高亮落对 grapheme;深度匹配不越界;PreviewRefresh 绿 |
| `PreviewTextRepTests` | T3.2 | 31KB 内存有界;深度滚动+高亮;多匹配;VoiceOver |

## 八、执行规则(继承 CLAUDE.md)

- 无本地工具链:不本地 build/test/swiftlint。每大步 push CI 验证(~11min,poll ≤每 2min)。
- TDD:行为变更先写 failing 测试,再最小正确改动。无本地运行时,测试+实现同 commit,CI 验证。
- 一小步一 commit;消息含轨标(`feat(bs5r0.1): …`/`test(bs5r1.2): …`/`docs(bs5r2.7): …`)。仅大步边界 push。
- 偏差先记 audit docs(`step-5` + 本目录 `decisions.md`)再 commit。
- **源码注释清洁 Apple 风格**:无 `BS-x`/finding-id 标签(audit 黑话仅 `docs/audit/`)。commit msg 仍用 `type(bsXrY):` 轨标。
- pbxproj 手改:每个新测试文件 4 处注册(PBXBuildFile/PBXFileReference/PBXGroup/Sources),已验证模式。
- **序列建议**:T0(独立快胜)→ T1(正确性地基,全文也依赖)→ T2(范围扩展)→ T3(预览)。T2.7 是索引叉点。

### ⭐ 实时跟踪契约(用户 2026-07-04 强制要求)

> **实现期间必须实时、逐步、同步记录到本目录文档,不得延后、不得积累、不得事后补。**(用户原话:"实现的时候,一定要随时实时的跟踪和记录到对应的文档里面,一定要做好这个事情,一定要跟踪好,实时反馈。")

每一步(无论大小、无论代码还是测试还是文档)落地后,**同一回合内**完成:

1. **`README.md` §九 进度日志追加** —— 一行,含:日期、轨.步号、状态(✅/⚠️/❌)、CI run id + 10/10、commit short hash、一句话做了什么 + 任何偏差。
2. **`decisions.md`**(若触及叉点/偏差)—— ADR 增补或修订,带日期与理由。
3. **`glossary.md`**(若引入新术语/不变量)—— 同步。
4. **`step-5-text-search.md`**(若兑现/偏离冻结 spec 项)—— 勾选框 + 偏差注释。
5. **`docs/audit/architecture-and-root-causes.md` §2.3/§2.5**(若搜索/预览架构实质变化)—— 同步。

**反馈给用户**:每步 CI 绿(或失败)后,即时回报状态——做了什么、哪条 CI run、是否偏离、下一步。失败必须带 tail 诊断 + 真/假判定(CLAUDE.md 失败排查规则)。

**真相源**:进度日志 + commit 历史 + CI run 三重对账;任一不一致以源码 + CI 为准并修正文档。

## 九、实时进度日志

> 随每步 CI 绿实时追加;commit 历史是另一条真相源。

- **2026-07-04** 📋 **计划成稿** — grill-with-docs 产出 README + 6 ADR + glossary。3-agent 验证当前管线(预览/内容/索引)。用户确认 4 叉点决策。待开工 T0。
- **2026-07-04** 🔨 **T0.1 模式循环按钮** — `Search.Mode.abbreviation`(`EX`/`FZ`/`RE`/`MX`)+ `Mode.next`(CaseIterable 循环 `exact→fuzzy→regexp→mixed→exact`);`SearchFieldView` 放大镜替换为模式 `Button`(`@Default(.searchMode)`,点击循环,`.help`=模式名,`.accessibilityLabel`=模式名);`MaccyTests/SearchModeCycleTests.swift`(4 法:循环序/全周期无重复/缩写值/唯一)。pbxproj 4 站注册(fileRef `DA070411…01` / buildFile `DA070412…02`)。CI 待 T0 门 push(T0.1/0.2/0.3 合并 ~11min 验证)。
- **2026-07-04** 📐 **ADR-7 决策:搜索派发采用 swift-async-algorithms `debounce`** — 用户「更系统、非补丁」指令;仔细核查(swiftpackageindex)确认 `debounce(for:)` 稳定公共 API(`throttle` 1.0.4 起移出公共,不相关——Maccy 需 debounce 语义);1.1.3(2026-03-04)Swift 6 完整模式兼容;系统性未来收益(`StoreEvent` 流/ingest 合并复用)。T1.0 落地:加 SPM 依赖 + `AsyncStream.debounce` 消费 Task + 删 `Throttler.swift`。Track 1 起步步。
- **2026-07-04** 🔨 **T0.2 模式切换触发重搜** — `History.refreshForModeChange()`(非空 query 调 `performSearch`,空 no-op)+ `waitForInFlightSearch()`(await `searchTask?.value`,确定性测试钩子);`ContentView` 加 `@Default(.searchMode)` + `.onChange(of: searchMode) → refreshForModeChange`(按钮/设置任一变更均触发);`searchGeneration` 改 `private(set)`(测试读 oracle);`MaccyTests/SearchFieldCycleTests.swift`(3 法:空 query no-op / 非空触发 / 多次重跑)。CI 待 T0 门 push。
- **2026-07-04** 🔨 **T0.3 tooltip/a11y 本地化 + T0 CI 门** — tooltip + `accessibilityLabel` 复用既有本地化模式名键(`"Exact"/"Fuzzy"/"Regex"/"Mixed"`);**"click to change" 提示文本延后**(偏差:新 locale 键须 BartyCrouch translate 传播 20+ 语种,无本地工具链;非英语会回退键名——见 ADR-1)。VoiceOver 经 label 随模式变更自然传达循环。Plan-doc push `1c6ebb5` 已 CI 绿(run `28689753952`)。推 T0(b7a52fb+1f96da3+9c4a5f1+本步)→ CI 门。
- **2026-07-04** ❌→🔧 **T0 CI 失败(run `28690718436`)→ 修复** — `Lint+diagnostics` 绿但**全部 shard 红**:`SearchModeCycleTests.swift` 缺 `@testable import Maccy` → `Search.Mode` 不在域 → ~20 级联 `cannot find 'Search'` → 测试 target 编译失败 → 所有 shard 红。模式诊断:`Lint` 过 + 全 shard 红 = 测试 target 编译错(每 shard 同建测试 target)。修复:补 `@testable import Maccy`(`SearchFieldCycleTests` 已有,`SearchModeCycleTests` 漏)。**教训纳入无本地工具链自检清单:每测试文件须 `@testable import Maccy`**(追加 [[no-local-toolchain-ci-gates]])。重推验证。
- **2026-07-04** ✅ **T0 CI GREEN(run `28690933856`,10/10)** — Track 0 完成并验证。模式循环按钮功能落地:`SearchFieldView` 放大镜 → 模式 Button(`EX`/`FZ`/`RE`/`MX`),点击循环 `exact→fuzzy→regexp→mixed→exact`,与设置 Picker 双向联动(同绑 `Defaults[.searchMode]`),模式切换触发重搜(`ContentView.onChange` + `History.refreshForModeChange`)。提交 `b7a52fb`/`9c4a5f1`/`eda047b`/`ec9f9f6`。下一步:T1.0 框架迁移(swift-async-algorithms)。
- **2026-07-04** 🔨 **T1.0a AsyncAlgorithms SPM 依赖(去风险拆步)** — 6 站 pbxproj 镜像 fuse-swift(`XCRemoteSwiftPackageReference DA070531…10` `upToNextMajorVersion 1.0.0` + `XCSwiftPackageProductDependency DA070532…11` + `PBXBuildFile DA070533…12`)+ `Package.resolved` pin(`1.1.3`,SHA `9d349bcc328ac3c31ce40e746b5882742a0d1272`);`AsyncAlgorithmsIntegrationTests`(build-integration:`debounce` 在 finished 空 stream 上不 emit,确定性无时序)。**隔离 SPM 解析风险于 History 改造之外**(T1.0b)。CI 待验证。
- **2026-07-04** ✅ **T1.0a CI GREEN(run `28691375939`,10/10)** — AsyncAlgorithms 包解析正确,build-integration 测试通过。6 站 pbxproj 手改 SPM 模式验证有效。T1.0b 解除风险。
- **2026-07-04** 🔨 **T1.0b 搜索派发迁移 + Throttler 退役(ADR-7)** — `History.searchQuery.didSet` → 向 `AsyncStream<String>` 产出;常驻消费 `Task` 迭代 `removeDuplicates().debounce(for:.milliseconds(200))` → `performSearch`(镜像 `init` 既有 `Defaults.updates` 消费 Task 模式,去风险);`init` 建 stream+continuation 并 `startSearchConsumer()`(一次性,不重启——避免单消费者 stream 双迭代器竞争);删 `Throttler.swift` + 4 调用点;`clear/clearAll/delete` 改赖 `searchGeneration` guard 丢弃 stale 结果。**行为变更(记 ADR-7)**:pending debounce 在 clear/delete 后 ~200ms 重过滤(一致语义;delete 正确——重过滤 corpus 减删除项;clear 显示查询匹配 survivors)。
- **2026-07-04** 🧹 **源码注释清洁(用户指令强化)** — 用户:「不能加入 bs/ADR,必须直观,不引用任何 doc」。清掉全部源码注释中的 `ADR-7`/`BS-x`/doc 引用:`History.swift`(searchQueryStream/startSearchConsumer 文档)、`AsyncAlgorithmsIntegrationTests`、`MemoryGovernance`(BS-3/06-27)、`SendableBoundaryTests`(BS-7)。源码现为纯 Apple Swift docstring,audit 黑话仅 `docs/audit/`。强化 [[source-comments-clean-apple-style]] 记忆。
- **2026-07-04** ✅ **T1.0b CI GREEN(run `28691944090`,10/10)** — swift-async-algorithms 迁移完成并验证。搜索派发:Dispatch/`Date` `Throttler` → `AsyncStream.debounce`(ContinuousClock 200ms + `removeDuplicates`),`Throttler.swift` 退役。中间断点 commit(`84e3a37` git-add 原子中止误——已记 [[no-local-toolchain-ci-gates]] lesson)被 `d933dff` 修复。**ADR-7 落地**。Track 1 基础设施就绪;下一步 T1.1 Gap A 经验闸门(Fuse offset 语义)。
- **2026-07-04** 🔨 **T1.1 Gap A 经验闸门(07-F-010)** — `MaccyTests/SearchHighlightIndexTests.swift`:exact control(`"x😀y"` query `"y"` → `2..<3`,`String.distance`=Character,必过)+ fuzzy 探针(同 query → `2..<3` 若 Fuse 返 grapheme offset = 当前代码已正确 / `3..<4` 若 UTF-16 = 实有 bug 需 `toGrapheneRange`)。**CI 是判官**:pass=grapheme(删 `4fa4946` "bug-2 fix" 夸大注释),fail=UTF-16(加 UTF-16→grapheme 转换)。pbxproj 4 站注册(`DA070451…07`/`DA070452…08`)。CI 待验证。
- **2026-07-04** ✅ **T1.1 CI GREEN + 结论(run `28695236510`,10/10)** — fuzzy 探针 **PASS**:Fuse 对 `"x😀y"` query `"y"` 返 **grapheme offset `2..<3`**(非 UTF-16 `3..<4`)。**结论:07-F-010 不是 bug**——SearchActor fuzzy 路径(grapheme offset)本就正确;`4fa4946` "bug-2 fix" 为空夸大(gap 审计矛盾判定 #2 属实);冻结 spec 的 `toGrapheneRange`(5.1/5.2)非必要。测试现锁该不变量防回归。**源码无需改**(注释本就准确)。Gap 审计 07-F-010 "未修" 推翻 → "经验证代码正确"。
- **2026-07-04** 🔨 **T1.2 TextLimits 单源(07-F-013 静默丢修复)** — 新 `Maccy/TextLimits.swift`(`titlePreview=1000`/`highlight=1000`/`fuzzy=5000`/`regexp=1000`);`HistoryItemDecorator.highlight` 硬编码 `500` → `TextLimits.highlight`(**渲染窗对齐标题窗**,消除 500–1000 区间正则/精确命中静默丢)+ 越界 `logger.debug`(替代旧静默 nil-drop,可观测);`HistoryItem.titlePreviewLimit`、`Search`/`SearchActor` 的 `fuzzySearchLimit`/`regexpSearchLimit` 全部指向 TextLimits 单源;`HistoryDecoratorTests.testHighlight_appliesToMatchesPastOldRenderCap`(600-char 标题尾部 `bcdef` 命中须高亮,旧 500-cap 会丢)。pbxproj 4 站注册(`DA070541…09`/`DA070542…0A`)。CI 待验证。
- **2026-07-04** ✅ **T1.2 CI GREEN(run `28695671670`,10/10)** — TextLimits 单源落地验证。下一步 T1.3 mixed 短路。
- **2026-07-04** 🔨 **T1.3 mixed 短路(LT-SEARCH-02)** — `Search.containsRegularExpressionMetacharacter`(nonisolated 静态,`CharacterSet` 检测 `\.[]{}()*+?^$|`);`Search.mixedSearch` + `SearchActor.mixedSearch` 短路 regexp tier——**仅当 simple 空且 query 含正则元字符才跑 regexp**(无元字符 query 是字面子串搜索,已被 exact tier 排除,直跳 fuzzy;3 遍→至多 2 遍);`SearchTests.testContainsRegularExpressionMetacharacter`(9 断言锁元字符集)。既有 `SearchActorTests` mixed 测试(`f.o` 元字符→regexp、`fb` 无元字符→fuzzy)覆盖两分支,无新集成测试需补。CI 待验证。
- **2026-07-04** ✅ **T1.3 CI GREEN(run `28696014888`,10/10)** — mixed 短路落地。下一步 T1.4 regexp 输入长度上限。**T1.8 重判**:原计划「删 dead `fuzzySearchLimit=5000`」**改为保留**——T1.2 后为 `TextLimits.fuzzy`,ADR-3 在 T2 用作 fuzzy 正文前缀 cap,非死代码。
- **2026-07-04** 🔨 **T1.4 regexp 输入长度上限(LT-SEARCH-04)** — `TextLimits.regexpInput = 2_000`;`Search.isLikelyUnsafeRegularExpression` 加 `guard pattern.count <= regexpInput else { return true }`(超长 pattern 一律判 unsafe,拒编译)。**该 helper 被 4 处共用**(`Search`/`SearchActor` regexpSearch、`Clipboard.ignoreRegexp`、`IngestFilter`),守卫统一硬化所有路径——>2000-char pattern 各处一致拒绝(合理:超长正则非常规剪贴板查询/忽略规则)。`SearchTests.testIsLikelyUnsafeRegularExpression_rejectsLongPattern`(2000 边界 + 嵌套量词)。CI 待验证。

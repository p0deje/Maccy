# ADR 集 — BS-5 搜索重设计决策(2026-07-04)

> 6 个真实决策叉点。**用户 2026-07-04 会话内已确认全部**(非代理决策,与 2026-07-03 BS-6/7/8 的代理 ADR 不同)。
> 推翻 ADR = 改本文件 + 调整 README 对应小步;若已实施需 revert。

---

## ADR-1:模式循环按钮 — 替换放大镜、短文本缩写、仅点击循环

**状态**:用户确认(2026-07-04)。**语境**:Track 0(用户原话:"搜索框内的右侧增个按钮……循环当前的搜索方式,并且和设置里面的对应")。

**决策**:
- **位置**:替换 `SearchFieldView` 左侧 `magnifyingglass` 图标为模式按钮(用户选"替换放大镜")。`✕` 清除键留右侧不变。布局 `[mode][textfield…………][✕?]`。
- **视觉**:短文本缩写 `EX`(Exact)/`FZ`(Fuzzy)/`RE`(Regexp)/`MX`(Mixed)(用户选"短文本缩写",弃 SF Symbol / 全名 pill)。tooltip 显示完整本地化模式名 + "click to change"。
- **交互**:仅点击循环 `CaseIterable` 顺序 `exact→fuzzy→regexp→mixed→exact`(用户选"仅点击循环",弃右键菜单 / 弹出 picker)。直接跳转走设置 Picker。
- **联动**:按钮与设置 Picker 同绑 `Defaults[.searchMode]`(`Defaults.Keys+Names.swift:76`),双向自动同步。

**考虑的替代**:
- (B)远右常驻 + `✕` 内移。用户未选——多一个控件,占地。
- (C)SF Symbol per mode。用户未选——缩写更显式、不依赖符号识别。
- (D)点击循环 + 右键菜单直跳。用户未选——直接跳转已由设置 Picker 覆盖,按钮保持极简。

**理由**:用户明确三项选择,均指向极简、显式、低占地。绑定同一 Defaults key 是联动设计的唯一正确解(无额外接线)。替换放大镜而非新增按钮:搜索框水平空间有限(`ListHeaderView` 内 `frame(maxWidth:.infinity)`),左侧图标位是天然 affordance 容器,不挤占文本区。

**后果**:
- 模式切换须触发重搜(`History` `.onChange(of: Defaults[.searchMode])` → 非空 query 调 `performSearch`,见 0.2)。否则切模式不生效。
- 缩写本地化:`EX/FZ/RE/MX` 拉丁字母语言中性;tooltip 走 `*.lproj`(BartyCrouch/Weblate,勿手编)。
- VoiceOver:`accessibilityLabel`=模式名,`accessibilityValue`=缩写,`accessibilityHint`="click to change"。
- 偏差:与冻结 spec 无冲突(冻结 spec 无此 UI);纯新增。

**推翻信号**:若用户改主意要 SF Symbol 或右键菜单 → 改本 ADR + 调整 0.1。低 revert 成本(纯 UI,Track 0 独立)。

---

## ADR-2:全文索引 — 先无索引、off-main 扫描、测量后按需加 trigram

**状态**:用户确认(2026-07-04)。**语境**:Track 2(用户 Q4 原选"true asymptotic index",但那是**标题域**提问;全文要求后内存数学巨变)。

**决策**:全文搜索**先以无索引 off-main 扫描落地**——`SearchActor` 持 body cache,`O(总正文_cap)` 扫描全在 actor,主线程仅发 `(query, mode, generation)`。**T2.7 G-search 在 n=1000 heavy-text 实测 actor 总延迟**;P95 < ~30ms → 维持无索引;> ~50ms 不可接受 → 开 Track 2-index(trigram)。

**背景**(内存数学,关键):
- 全文 body cache:n=200 × 31KB ≈ 6MB(典型 <1MB);G-search 闸门 **n=1000** → ~31MB。
- trigram 索引开销 ~2–4× body 字节 → **+60–90MB** 于 n=1000 heavy(62MB 地板之上 → ~150MB)。直接冲突用户「又快又省 / 空间最优」核心优先级。
- **`<16ms` 闸门针对主线程**(`B-test-strategy.md §4` "主线程 < 16ms/键;后台 actor 承担")。off-main 扫描已满足——actor 延迟 ~5–30ms 被 `Throttler(minimumDelay:0.2)`(`History.swift:139`)+ `searchGeneration` 取消掩盖,用户感知即时(结果在 200ms 节流窗内出现)。
- trigram 不加速 fuzzy(Fuse DP 允许 gap/substitution,索引候选须另建 Levenshtein 自动机,超范围)。fuzzy 是最需加速的模式,索引对它无效。

**考虑的替代**:
- (B)立即建 trigram 索引。搜索 ~1–5ms,但 +60–90MB 内存(违「省」);且 fuzzy 不受益。**用户 Q4 原选,但在标题域语境下做出;全文语境下推翻。**
- (C)永不开索引。若实测延迟可接受则等同;但放弃测量驱动的逃生通道。

**理由**:
1. **空间优先**:用户反复强调「尽可能做到空间复杂度的最优 / 又快又省」。全文索引的内存代价在 n=1000 下与该优先级直接冲突。
2. **闸门语义**:`<16ms` 是主线程预算,off-main 扫描已达标。索引优化的是 actor 总延迟,非闸门维度。
3. **延迟可掩盖**:0.2s throttle + 取消旧 task 是现有机制;~30ms actor 延迟在节流窗内不可感。
4. **fuzzy 不受益**:索引最大受益模式(exact/regexp)本就快(ICU substring/firstMatch);最慢模式(fuzzy)不被索引加速。
5. **经验式避险**:避免 60–90MB 的早熟索引;测量驱动决策(T2.7 是闸门)。

**后果/风险**:
- 大语料(n=1000 全 heavy)actor 延迟可能 ~20–50ms——可接受(节流掩盖),但须 T2.7 实测确认。
- 正文封顶(ADR-5,32KB)控制扫描量与内存。
- T2.7 是硬决策点:测量结果记入本 ADR + README 进度日志。
- 若开索引(Track 2-index):须复核内存预算,可能需降封顶或 NSCache evict(`ThumbnailCache` 64MiB / `ApplicationImageCache` 128 count 的先例)。

**推翻信号**:T2.7 实测 actor P95 > ~50ms 且用户优先延迟 → 开 Track 2-index(改本 ADR + 执行 2.8)。

---

## ADR-3:Fuzzy 全文深度 — 标题 + 正文前缀(封顶 ~5000)

**状态**:用户确认(2026-07-04)。**语境**:Track 2.4。

**决策**:fuzzy 搜索语料 = `title + body.prefix(TextLimits.fuzzy=5_000)`(Fuse DP 成本有界 ~ms)。exact/regexp 仍扫全文(封顶 32KB,ADR-5)。命中 offset 标 `inBody`。

**背景**:Fuse DP 复杂度 `O(text · query)`。31KB body × query → ~150M 操作 → ~50–100ms off-main,对单键可接受但模糊语义差(fuzzy 是"我记得大概"的标题级召回,非全文级)。全文 fuzzy 须 Levenshtein 自动机 + 索引,超范围。

**考虑的替代**:
- (B)fuzzy 仅标题。更简单,但弃正文前缀的 fuzzy 召回(用户未选)。
- (C)fuzzy 全正文。慢(50–100ms/大项),语义存疑。用户未选。

**理由**:用户选"标题 + 正文前缀"——平衡召回(正文前 5000 字 fuzzy 命中)与延迟(DP 有界)。精确召回仍由 exact/regexp 全文覆盖,fuzzy 不承担全文精确职责。

**后果**:
- 正文 5000+ 处的 fuzzy 不命中(精确仍由 exact/regexp 找到)。记偏差。
- `TextLimits.fuzzy=5_000` 与标题域 T1.8 删的旧 `fuzzySearchLimit=5_000` **同值不同语义**(旧=标题截断死代码;新=正文 fuzzy 前缀封顶,活代码)。

**推翻信号**:若用户要全文 fuzzy → 须 Levenshtein 自动机 + 索引(大工程,单开 ADR)。

---

## ADR-4:预览高亮/滚动 — 分阶段(Stage1 SwiftUI 窗内高亮 → Stage2 NSTextView 深度滚动)

**状态**:用户确认(2026-07-04,用户:"这个我在想主要是我限制了 3000 字符,我不知道能不能做到,你仔细想想")。**语境**:Track 3。

**决策**:分两阶段,均落地:
- **Stage 1(T3.1)**:`PreviewItemView` 文本分支 `Text(item.text)` → `Text(attributedString)`,对落在 `textPreviewLimit`(3000)窗内的匹配高亮(复用 `highlight()` 的 AttributedString 范围样式)。廉价,纯 SwiftUI,**覆盖常见情况(<3000 字内容)**。深度匹配仍被找到(item 进结果)但不滚动。
- **Stage 2(T3.2)**:文本分支切到 `NSViewRepresentable` 包 `NSTextView`(`PreviewTextRep`)——`NSTextStorage` 持全文 `searchText`(**惰性 layout**,解除 3000 封顶),`addAttributes(.backgroundColor, range:)` 高亮,`scrollRangeToVisible(matchRange)` 精确滚动到匹配。深度匹配(>3000)可见 + 滚动。

**背景**(可行性分析,回应用户"能不能做到"):
- **3000 封顶的根因**:SwiftUI `Text` **急切布局**整个字符串——CoreText 在 layout pass 测量全文 → 内存/布局暴涨(与历史渲染风暴同根,`titlePreviewLimit=1000` + `.middle` 截断放大)。封顶是权宜,非根本限制。
- **NSTextView 惰性布局**:`NSLayoutManager` 仅对可见 range layout glyph(`NSTextStorage` 持全文,cheap ~字节数);`scrollRangeToVisible` 触发目标 range layout。TextEdit/Safari/Xcode 开多 MB 文件不涨内存的机制。**故深度匹配可显示 + 滚动,live 内存有界。**
- 当前项目**无任何 NSTextView/NSViewRepresentable 文本视图**(3-agent 确认;仅有 VisualEffectView/GlassEffectView/MouseMovedViewModifer)。Stage 2 是项目首个文本 NSTextView 桥。

**考虑的替代**:
- (B)仅 Stage 1(窗内高亮,弃深度滚动)。廉价但违用户"高亮附近的"(深度匹配上下文)意图。
- (C)Stage 1 + ScrollViewReader 锚点 lossy 滚动(无 NSTextView)。近似滚动,无字符保真。用户未选(隐含接受 NSTextView 路线)。

**理由**:用户"高亮附近的"明确要深度匹配上下文 → 须能显示 + 滚动到 >3000 偏移 → 仅 NSTextView 可解(Text 急切布局)。分阶段:Stage 1 廉价快胜(覆盖常见 <3000),Stage 2 兑现深度承诺。两阶段均落地,非二选一。

**后果/风险**:
- Stage 2 引入 AppKit 桥: NSTextStorage 属性高亮 + 滚动状态同步 + `PreviewRefreshUITests` identity 契约(`.id(item.id)`,`SlideoutContentView.swift:21`)须保持绿。
- 图片分支不动(PreviewItemView image 分支保留)。
- `textPreviewLimit` Defaults 在 Stage 2 后对**文本预览项**失效(NSTextView 懒布局不需封顶);保留对其他上下文的语义(或调 doc)。
- 偏差:首个 NSTextView;记 `architecture-and-root-causes.md §2.5`。

**推翻信号**:若 AppKit 桥稳定性/测试代价过高 → 退到 Stage 1 + ScrollViewReader lossy 滚动(改本 ADR + 调整 3.2)。Stage 1 已独立有价值。

---

## ADR-5:全文 body 封顶 — 32KB(覆盖 heavy_text fixture),`Defaults` 可配

**状态**:用户确认(2026-07-04,由我代定具体值,用户确认范围)。**语境**:Track 2.6。

**决策**:每项 `searchText` 索引/扫描封顶 **32KB**(`TextLimits.searchBody=32_000` 字符),经 `Defaults[.searchBodyLimit]` 可配(默认 32_000,范围 [1_000, 256_000])。超封顶的 body 部分不被索引/扫描(退化标题搜索)。image 项 `searchText=""`。

**背景**:
- `heavy_text.txt` fixture = 31,052 字节(`MaccyTests/Fixtures/`)。32KB 封顶覆盖之。
- `HistoryItemContent.maxValueSize` 默认 10MB(`HistoryItemContent.swift:12-17`)——无封顶则单项 body 可达 10MB,n=1000 → 10GB(不可行)。
- 封顶控制:扫描量(无索引延迟) + cache 内存 + (若开索引)索引内存。

**考虑的替代**:
- (B)全文至 maxValueSize(10MB)。内存不可行;且 clipboard 单项 >32KB 文本罕见。
- (C)更紧封顶(8KB)。省内存但漏 heavy_text fixture 级匹配(测试覆盖受损)。

**理由**:32KB 覆盖最大 fixture + headroom,控内存于合理范围(32KB × n=200 = 6.4MB,典型 <1MB);`Defaults` 可配让 power user 调整。macOS 剪贴板单项 >32KB 纯文本罕见(图片走 image 分支,不进 searchText)。

**后果**:
- >32KB body 的尾部匹配不被找到(退化标题搜索)。记偏差;用户可调高 Defaults。
- 与 ADR-2 内存预算耦合:封顶 × n 是 cache + (条件)索引内存的主导项。开索引时须复核。

**推翻信号**:若实测常见用例有 >32KB 文本匹配需求 → 调高默认(改 Defaults + 本 ADR)。

---

## ADR-6:`searchText` 持久化列 + 语料移到 SearchActor

**状态**:用户确认(2026-07-04,隐含于全文设计批准)。**语境**:Track 2.1/2.2。

**决策**:
1. **持久化 `HistoryItem.searchText: String?` 列**(lightweight migration,模板同 BS-8.5 `fingerprint`);ingest 一次性提取(优先级 fileURL→string→rtf→html,first-rep,**不截断**,RTF/HTML 沿用 `MainActor.run` hop + 512KB 守卫;`.string`/`.fileURL` off-main 于 `@ModelActor`)。
2. **`SearchActor` 持 body cache `[ItemID: String]`**(惰性 bootstrap 自列,经 `@ModelActor` 后台 context fault;不在 main,规避 `mainContext` 滞留 §4.2)。`search(query:mode:)` 不再收 `within:`。
3. **删/清/限容 mutators 发 `StoreEvent.removed/.cleared`**(`History.delete/clear/clearAll/limitHistorySize`),接 `consume` 既有分支 → actor `remove`。增经既有 `.added/.merged`。

**背景**:
- 全文从未存储(`previewableTextPrefix` 三层截断);`SearchActor` 无 ModelContext(`SearchActor.swift:30`),不能 fault。
- 每按键 `all.map { SearchCorpusItem(id:,title:) }` 在 **main**(`History.swift:857`)——全文下投影税线性放大(1000 × 31KB body/按键 = 灾难),**必须移语料到 actor**(无索引也必须)。
- RTF/HTML 提取主线程亲和(`ClipboardIngestor.swift:227-244` 自述 off-main trap);ingest 已有 `MainActor.run { title(for:) }` hop——全文提取复用该 hop,无新主线程亲和工作,仅做更多(全量 vs 1000 截断)。
- `SignatureIndex`(`Ingest/SignatureIndex.swift`)是 actor 持 Sendable struct + `register/remove/merge(StoreEvent)` 的完美生命周期模板(虽其键 `(UTI,size,xxh3)` 不可复用为文本索引)。

**考虑的替代**:
- (B)in-memory only(不持久)。冷启重提取全部 RTF/HTML → 违 `G-popup-open <16ms`(主线程亲和批量)。弃。
- (C)给 SearchActor 一个 ModelContext + 懒 fault。违「SearchActor 故意无 context」隔离设计(Agent 2 判"architectural break");RTF/HTML off-main 不可行。弃。
- (D)每按键投影 body DTO。1000 × 31KB/按键 = ~31MB String retain/按键,灾难。弃。

**理由**:
- 持久化:免冷启重提取(保 `G-popup-open`);迁移成本低(模板存在);survive restart。
- 语料移 actor:全文投影税的唯一可行解(无论索引与否);额外消除标题域每按键 `all.map` 主线程税(净改进)。
- first-rep 提取:与 title 同优先级,offset 与预览显示对齐(预览显示 first-rep 提取);macOS 约定 `.string`=规范文本,多 rep 不同文本是边角(记偏差)。
- StoreEvent 维护:复用既有事件管线 + `SignatureIndex` 模板;删/清补发事件接 `consume` 既有空分支。

**后果/风险**:
- lightweight migration:既有库须回填 `searchText`(类比 8.5);**首版接受老行 nil → 退化标题搜索**,回填 follow-up(同 8.5 历史决策)。
- 删/清发事件:`invalidateInFlightSearch` 仍 bump generation(防 stale apply);新事件仅维护 cache。
- first-rep 偏差:多 rep 不同文本项(罕见)只在 first-rep 命中;次要 rep(如 .rtf 独有文本)不命中。记偏差。
- cache 内存:见 ADR-2/5(封顶 + 无索引下 ~6MB)。

**推翻信号**:若迁移风险/成本过高 → 改 (B) in-memory + 接受冷启重提取(调 `G-popup-open` 预算);若 first-rep 漏召回 → 扩展 concat 所有 rep(但 offset 与显示对齐复杂化)。

---

## ADR-7:搜索派发 — 采用 swift-async-algorithms(`debounce`)取代手写 Throttler

**状态**:用户决定(2026-07-04,"你来决定……更系统的办法,更方便未来开发,不是临时打补丁")。**语境**:Track 1 基础设施(搜索派发路径;用户在 T0.2 实现期间提出)。

**决策**:采用 Apple 官方 [`swift-async-algorithms`](https://swiftpackageindex.com/apple/swift-async-algorithms) 包(`/apple/swift-async-algorithms`,**1.1.3**,2026-03-04 发布,Swift 6 complete-mode 兼容,源码稳定 1.x)。`History.searchQuery.didSet` 改为向 `AsyncStream<String>` 产出值;一个常驻消费 `Task` 迭代 `stream.removeDuplicates().debounce(for: .milliseconds(200))`,每值调 `performSearch`。**删除手写 `Maccy/Throttler.swift`**(`@MainActor` Dispatch/`Date`-based,4 调用点全在 `History.swift`——`searchQuery.didSet` 的 `throttle` + `clear/clearAll/delete` 的 `cancel()`)。

**仔细检查后的关键发现**:
- **`throttle(for:)` 在 1.0+ 被移出公共 API**(1.0.4 release:"#296 …behavior was not fully ratified by review";1.0.0 `Make throttle underscored`)。**但 `debounce(for:)` 是稳定公共 API**——Maccy 搜索所需语义正是 **debounce**(静止期后触发),非 throttle。当前 `Throttler` 实为 debounce 语义误标(其 `cancel()`-then-reschedule = debounce,加一不寻常 leading-edge「空闲即触发」)。故 throttle 移除不影响本决策。
- 包活跃维护:1.1.3(2026-03-04),含 "address concurrency failures for 6.2 build modes"(#362,证 Swift 6 完整模式兼容)。源码稳定 since 1.0.0(2023-12,SemVer)。
- 平台要求 macOS 12+;Maccy 14+ ✓。
- **系统性 + 未来收益**:同包提供 `combineLatest/merge/zip/chunks/removeDuplicates/AsyncChannel/AsyncTimerSequence`——架构 §2.1 未修的 `no-coalesce-of-ingest-writes` 与未来 `StoreEvent` 流均可复用同框架(chunks/debounce)。此即"更系统、更方便未来开发"。

**考虑的替代**:
- (B)Task-based 重写 Throttler(保留 API/架构)。**用户否决**("不是临时打补丁")——单点重写不系统,不为未来铺路。
- (C)SwiftUI `.task(id:)`。Apple 惯用、无依赖,但把搜索派发从 model(History)移到 view(ContentView),改架构 + 测试面,且不提供 `combineLatest`/`chunks` 等未来工具。
- (D)Combine。Maccy 无 Combine;`@Observable`→publisher 桥接笨重;Combine 维护态。弃。
- (E)延后/保留。违用户"更系统"要求。

**理由**:用户明确要系统性框架 + 未来友好 + 非补丁。swift-async-algorithms 是 Apple 官方、稳定、Swift-6-native、富算子集的答案;`debounce` 是稳定公共 API(throttle 移除不相关);未来 ingest 合并/事件流复用同框架。删手写 Throttler 消除误标语义 + Dispatch/`Date` 旧机制 + 测试时序痛点(刚在 T0.2 撞到)。

**后果/风险**:
- **新增 SPM 依赖**(pbxproj 手改:`XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + `PBXFrameworksBuildPhase` + `Package.resolved`;镜像既有 `fuse-swift` 包模式,CI 验证。无本地工具链 → 解析失败须 CI 迭代)。
- **搜索语义变更**:从「leading-edge 空闲即触发 + 尾随合并」→ **纯尾随 debounce**(每次搜索延迟 200ms 触发)。标准搜索 UX,可接受;记行为变更(若用户要 leading-edge 即时反馈,debounce 不直接提供,需自定义——暂取纯尾随)。
- **常驻消费 Task**(History.shared 单例,app 生命周期);`clear/clearAll/delete` 的 `throttler.cancel()` 删除——debounce + generation guard 处理 staleness(set "" → debounce → performSearch 空短路;delete 无 yield → 无 pending;generation guard 丢弃 stale actor 结果)。
- **可测性提升**:debounce 间隔可经 `Clock` 注入(测试用 0 / 暂停 clock);消费 Task 可 await;比 Dispatch `asyncAfter` 更确定。
- 偏差:首个 `AsyncStream` + 消费 Task 模式;记 `architecture-and-root-causes.md §2.3`。

**推翻信号**:若 pbxproj 包解析在 CI 反复失败 → 退到 (B) Task-based 重写作 fallback(记偏差);若用户要 leading-edge 即时反馈 → 自定义 leading+trailing(记偏差)。

---

## 决策与冻结 spec 的关系(总结)

| 冻结 spec 项 | 本设计 | 关系 |
|---|---|---|
| 5.1/5.2 HighlightRange + toGrapheneRange | T1.1 经验闸门(先测 Fuse offset,按结果决定) | 兑现(经验式) |
| 5.3 SearchSnapshot DTO | `SearchMatchDTO`(已存在,扩 `inBody`) | 兑现 |
| 5.4 actor SearchEngine + mixed 短路 + regexpInputLimit | T1.3/T1.4 + T2.5 | 兑现 |
| 5.5 Search.swift 薄壳 | T2 后 legacy `Search` 评估合并/弃用 | 部分偏离(评估) |
| 5.6 searchQuery.didSet 接 actor | **已完成**(既有) | ✓ |
| 5.7 highlight 修正 + memoize | T1.2/T1.5 | 兑现 |
| 5.8 resize 移出 | T1.7 | 兑现 |
| 5.9 showSpecialSymbols 范围 | T1.6 | 兑现 |
| 5.10 截断单位统一 | T1.9 | 兑现 |
| 5.11 Fuse 复用 | **已完成** | ✓ |
| 5.12/5.13 测试 + 验证 | 测试清单(七)+ T2.7 G-search | 兑现 |
| **(新增)全文搜索** | Track 2 | **超 spec,ADR-2/3/5/6** |
| **(新增)预览高亮/滚动** | Track 3 | **超 spec,ADR-4** |
| **(新增)模式循环按钮** | Track 0 | **超 spec,ADR-1** |

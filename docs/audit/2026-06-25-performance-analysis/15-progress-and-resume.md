# 进度与下次启动恢复指南(2026-06-25)

> **下次启动从这里读起。** 本文汇总:当前状态、内存重大发现、已完成(P0/C1-C3/F4 全绿)、暂缓项(P2/C5/M8/C4)+ 原因、**P2 设计(可直接实现)**、CI 坑、下一步选项。上位文档:`AGENTS.md`、`14-master-plan.md`、`00-memory-profile.md`(2026-06-24)。

## 0. TL;DR

- **内存目标基本达成**:实测**基线 ~102MB**(短启动),213MB 是 2 天积累(HotKey + TIS 泄漏,**均已修**)。
- **代码侧内存+安全工作完成**:P0(M2-M10)+ C1-C3 + F4,~17 commits 全 CI 绿(见 §2)。
- **"36.6MB 盲区"已破解** = HotKey 泄漏(已修)+ 20MB 基线框架(不可降)。**D1 重抓不再关键**(见 §1)。
- **P2(搜索离主)已设计**(workflow),朴素版 unsound(5 bug),可靠版可直实现 —— 复杂 + 对当前小历史低价值,**暂缓待定**(见 §4)。
- C5(VisibleWindowLoader)、M8、C4 暂缓(原因见 §3)。

## 1. 内存重大发现(2026-06-25,推翻 06-24 的"盲区需 D1"判断)

用户用**短启动(2 分钟)**重抓了一份(覆盖了 `docs/maccy.*.txt`)。对照旧抓取(2 天/213MB):

| 指标 | 旧(2天) | 新(2分钟) | 含义 |
|---|---|---|---|
| phys_footprint | 213 MB | **102 MB** | 基线 ~102MB;213MB 全是积累 |
| peak | 415 MB | 191 MB | 峰值腰斩 |
| **SWAPPED(压缩冷页)** | 152 MB | **0** | 152MB 冷页 = 长期积累对象,基线没有 |
| leaks | 19,806 / 821 KB | **289 / 14 KB** | 泄漏几乎全是运行时积累 |
| `HotKey.carbonHotKey` | 783 / 43.5 MB | **1 实例** | bs6.13 修对 |
| `TSMInputSource` | 18,417 | **13** | 基线 IME;M2 修对后不再涨 |
| heap `non-object` | 36.6 MB / 176k | **20.2 MB / 77k** | 见下 |

**"36.6MB 盲区"真相**:旧堆里 HotKey 43.5MB 是**已分类**项(独立于 non-object);non-object 36.6MB 里:20.2MB 是**基线框架开销**(SwiftUI 图 / CoreText / 闭包,heap 归不了类、不可降、非泄漏),~16MB 是 2 天的框架工作集增长(AttributeGraph/CoreText 缓存等,非单一泄漏)。**没有神秘的 36.6MB 泄漏要追 —— 主要是 HotKey(已修)+ 基线框架。** 所以 `00-memory-profile.md` 之前"盲区阻塞 <100MB、需 D1"的结论**作废**:D1 不再是关键。

**剩余 top 项**(都正常):`__DataStorage._bytes` 9.4MB(232 个 @40KB,剪贴板内容 Data blob,用户数据非泄漏);MALLOC_SMALL 60MB;SwiftUI/CoreText 框架。

**结论**:<100MB 在启动态基本已达(102MB)。修复(HotKey+TIS)是把长期运行从 213MB 拉回基线的关键。**验证长期稳定性**:跑几小时后再抓一次,预期 ~110-130MB(基线 + 少量框架增长),不会回 213MB。

## 2. 已完成(全 CI 绿)

提交区间 `04298ab`(bs6.13)→ `8f38224`(F4)。每步 TDD/自检 + 推 CI,绿即过。

**P0(快赢面)**:
- **M2** KeyboardLayout TIS 泄漏(`takeRetainedValue`,18417 TSMInputSource leak 唯一来源)。
- **M3** sessionLog `[Int:HistoryItem]`→`[Int:PersistentIdentifier]`(dead-in-prod,正确性)。
- **M4** ApplicationImageCache→NSCache(128)+ fd defer 守护 + `[.delete,.rename]` + print→logger。
- **M5** ignoredRegexps→NSCache + Defaults 重建。
- **M6** autoreleasepool(load/clear/clearAll bulk loops)。
- **M7** withLogging fetchCount `#if DEBUG`。
- **M9** ColorSwatch totalCostLimit + drawingHandler(替 lockFocus)。
- **M10** settingsWindowController 关窗释放(willCloseNotification)。

**C1-C3(图像生命周期)**:
- **C1** 新 `Maccy/Observables/MemoryGovernance.swift`(ReleaseReason / HistoryRef / VisibilityObserving / VisibilityTracker / DecodedImageCache NSCache 32/64MiB / MemoryGovernor)+ pbxproj 4-insertion(objectVersion 54,无 sync groups)。
- **C2** decorator `releaseTransientImages(_:)` + VisibilityObserving;cleanupImages 委托(删 recache);HistoryItemView `.onDisappear`→scroll-out 释放。
- **C3** AppDelegate 挂 MemoryGovernor(attach+start,`DispatchSource.makeMemoryPressureSource` + `MainActor.assumeIsolated`)。
- 效果:滚出可视区的行释放 preview 位图;内存压力回收非可视位图 + DecodedImageCache + ApplicationImageCache。

**F4(安全)**:ImageDownsampler NaN/∞ 守卫;String.shortened 负 maxLength 守卫。

## 3. 暂缓项 + 原因

- **P2 搜索离主**:已设计(见 §4),朴素版 unsound;可靠版复杂 + 对当前 ~242 条历史(搜索 sub-ms)低价值 + 有破坏搜索 UX 风险。**待用户定。**
- **C5 接入 VisibleWindowLoader**:decorator init 现已廉价(BS-3 懒加载 + M4 封顶),windowed-load ROI 下降;且需重构 `all`(shell+detail)涉及搜索/导航/pin/分页,高风险。**暂缓。**
- **M8**(shortcuts diff):KeyShortcut 非 Equatable,低价值。
- **C4**(观察环 token):`isInvalidated` 守卫已限制,低价值。
- **F1/F5/F2**(BS-8 C++ 哈希 / SwiftData #Index / BS-7 Swift6):大工程,未做。

## 4. P2 设计(可直接实现,workflow 产出 + 对抗验证)

**map 要点**:searchQuery didSet → Throttler(0.2s,主队列,last-keystroke-wins)→ `search.search(string:within: all)` 同步主线程 → `updateItems`(highlight + items)→ didSet 副作用(select/highlightFirst + needsResize)。4 模式:exact(`range(of:.caseInsensitive)`,首匹配,corpus 序)/ fuzzy(Fuse 0.7,5k 截断,score 升序)/ regexp(`firstMatch`,1k 截断,corpus 序)/ mixed(简单→正则→模糊,首非空)。range 是 `[Range<String.Index>]`(字素偏移)。

**朴素设计(被验证判 unsound,5 个真 bug)**:corpus 投影→actor 搜索→generation 取消→main apply。bug:
1. `refreshVisibleItems` 必须保持**同步**(否则 `testAddingDuringSearchKeepsFilteredItems` 挂——add 后 items 不一致)。只让"用户键入的 throttled 路径"离主,ingest 重过滤留同步。
2. fuzzy range 必须是 **Character 偏移**,不是 NSRange/UTF-16(Fuse 返回字素偏移;emoji/组合字符会错位)。DTO 用 `[Range<Int>]`。
3. **title 快照 vs 实时**:title 会被 `showSpecialSymbols`/merge 在 search→apply 间改写 → 高亮错位。DTO 带快照 title,apply 时 `decorator.title == dto.title` 守卫,不等则无 range 高亮。
4. `clear`/`clearAll`/`delete` 必须 **bump searchGeneration + cancel searchTask**(不只 thrott器 cancel),否则删除时在飞的搜索用过期结果覆盖 items。
5. 正则空匹配(`z*`→`{0,0}`)零长度 range 要正确处理(`Range(NSRange{0,0}, in:)` → `startIndex..<startIndex`)。

**可靠版(可直实现)**:
- `Search.swift`:legacy `func search(string:within:)` **不动**(SearchTests 全绿当闸);新增 `SearchCorpusItem(id,title)`、`SearchMatchDTO(id,title,score?,[Range<Int>])`、`actor SearchActor`(自己的 4 模式逻辑,Character 偏移)。**或**抽取 per-mode 纯函数 `(title)->(score?,[Range<Int>])` 供 legacy + actor 共用(单源,但要重构 Search,风险略高)。
- `History.swift`:didSet → throttled → 离主 Task(`searchGeneration &+= 1`、cancel searchTask、`Task { @MainActor }` await actor、generation 守卫、apply);空 query 同步短路;`refreshVisibleItems` 保持同步(走 legacy `search.search`);clear/clearAll/delete bump generation + cancel searchTask。
- 新测试:`SearchActorTests`(等价 legacy)、emoji 字素、取消、throttle 合并、ingest 重过滤、destructive-while-searching。

**实现策略**:建议 legacy 不动 + actor 独立(隔离风险,SearchTests 零改动);多 CI 周期磨对 Character 偏移/apply/测试。

## 5. CI/build 坑(避免重蹈,详见 `roadmap-current-position` 记忆)

- **`line_length`=120 且 `ignores_comments:true`**("raise to 1000" 只对 body 规则)。
- **swift-log `Logger` 此处不接受 `privacy:`**(用 `\(value)`)。
- **@Sendable 闭包不能捕获非 Sendable `self`** → 走静态单例(`AppState.shared`)或 `MainActor.assumeIsolated`。
- **`@MainActor protocol` 会推断 conforming type 的隔离**(把 HistoryItemDecorator 拉成 @MainActor,破坏非隔离调用方)→ 用 id-only 协议 + 具体 `@MainActor` 实例方法。
- **macOS 无 `NSApplication.didReceiveMemoryWarningNotification`**(那是 iOS)→ `DispatchSource.makeMemoryPressureSource(.warning/.critical)`。
- **`orphaned_doc_comment`**:别在 `///` 和声明间插 `//`。
- **pbxproj**(objectVersion 54,无 sync groups):新源文件 4-insertion(PBXBuildFile / PBXFileReference / group children / Sources),用 Python 脚本 + 唯一性 assert 最稳。
- push 前自检:`grep privacy:` + `awk 'length>120 && !/^\s*\/\//'` + 看 doc 挂载 + @Sendable self 捕获。
- 无本机工具链:lint/compile 只在 CI(~11min)显现;`[ test ] && { }` 监控脚本成功时退出码是 1(误报失败),看 conclusion 字段。

## 6. 下次启动选项(按价值)

1. **验证长期内存**(低成本高确认):用户跑几小时后重抓,确认不回 213MB(预期 ~110-130MB)。这基本"收尾"内存目标。
2. **P2 搜索离主**:按 §4 可靠版实现(legacy 不动 + actor)。多 CI 周期。对大历史有价值;当前小历史低价值。
3. **C5 接 VisibleWindowLoader**:大历史冷开/内存,但高风险(重构 `all`)。
4. **F1(BS-8 C++ 哈希)/ F5(#Index)/ F2(Swift6)**:大工程。
- 其它低价值项(M8/C4/F4-cpp)可顺手清。

**建议下次**:先做 (1) 验证长期内存(确认收尾);若用户要继续代码,P2 是下一个实质项(设计已就绪)。

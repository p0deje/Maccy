# 2026-06-22 — 渲染链残留风暴目录（post-stopgap 诊断）

## 背景

`2026-06-21-render-feedback-stopgap.md` 的 P0/P1/P2/P3 止住了 `perf-mixed`
~400s 的灾难性 LazyVStack 布局反馈风暴（固定行高、hover 不再 scrollTo、preview
取消、Duration 1000×）。**之后**对常驻运行中的 app 重新 `sample`，仍然看到弹窗
打开路径上数十毫秒级的主线程同步工作（AttributeGraph/sizeThatFits/CoreText/
hover 命中/CA commit/WindowServer）。本文把**当前 master 的完整渲染链**逐段拆
开，定位止住之后**暴露出来的残留风暴**，并逐条归位到路线图。

诊断方法：把外部 GPT 对 `sample` 的分析与**当前代码 `file:line`** 逐条对质（不
盲信采样统计），分出「命中且仍存 / 已止住 / 误判 / 路线图已覆盖但未实施」。结
论见 §5。

> 这是 **BS-4 编译边界内的 UI 侧工作**（纯主线程渲染链，不改数据语义），不是
> BS-4.3/4.4a 的数据管线重构。两条线互补：数据管线（D1）由 4.3/4.4a 负责，渲
> 染链（D2）由新增的 **4.10** 负责。

---

## 1. 两条成本线（关键心智模型，别再混）

外部诊断最容易犯的错：把「热键→打开」和 `load() 0.999s` 当成同一条路径。
**它们不是。**

| | D1 数据管线（冷启动 / 复制） | D2 打开渲染链（每次弹窗） |
|---|---|---|
| 触发 | app 启动 `ContentView.task`（`ContentView.swift:55-57`）；每次复制 `consume→reconcileWithStore`（`History.swift:276,291`） | 每次按热键 `Popup.handleFirstKeyDown→open`（`Popup.swift:116,75`） |
| 主线程重活 | 全表 fetch + sort + decorate-all（`History.swift:201-214`，实测 image-200 maxGap **0.999s**）；每次复制全表 refetch+resort（`History.swift:294`，maxGap **0.324s**） | 窗口操作 + 首帧布局 + 重复 select + 动画 resize + hover 抖动（`sample` ~数十 ms） |
| 路线图覆盖 | BS-4.3 / 4.4a（已规划） | **几乎未覆盖**（4.7 prewarm 只管数据侧；止血只管灾难态） |
| 测量闸门 | `G-popup-open` = `load()`（harness Step3 在建） | **无** → 需新增 `G-resident-open` |

**证伪「打开即 load」**：`ContentView.task` 只在 hosting view 首次 appear 时跑一
次；panel 在 `AppDelegate.applicationDidFinishLaunching`（`AppDelegate.swift:132`）
创建一次，`FloatingPanel.close()` 只是隐藏窗口、不拆 contentView（`FloatingPanel.swift:201`），
所以 `.task` **不会在每次打开重跑**。常驻打开不走 `load()`。外部 `sample` 看到的
打开期成本是**纯渲染链（D2）**，不是 `load()`（D1）。

**推论**：`G-popup-open` 定义为 `load()`，测的是 D1 冷启动数据成本；它**测不到**
用户 `sample` 反映的 D2 常驻打开卡顿。这是测量缺口（S17），由新增 `G-resident-open`
补上。

---

## 2. 渲染链触发时序（当前 master，带 file:line）

### 场景 A —— 按热键打开（常驻，已 warm）

```
CarbonKeyboardShortcuts.handleHotKeyEvent
 → KeyboardShortcuts.onKeyDown(.popup) → Popup.handleFirstKeyDown            Popup.swift:116
   → isClosed() → open(height:)                                            Popup.swift:118
     → Popup.open                                                           Popup.swift:75
       ① navigator.select(item: unpinnedItems.first ?? pinnedItems.first)   Popup.swift:76     ← select#1 + O(n) filter
          → select(item:) → selectWithoutScrolling + scroll(to:)            NavMgr.swift:103
            → scrollTarget = id                                             NavMgr.swift:90     ← .task(id: scrollTarget) 周期#1
       ② panel.open(height:at:)                                             Popup.swift:79
          → setContentSize / setFrameOrigin / orderFrontRegardless / makeKey()  FloatingPanel.swift:74-80  ← WindowServer key-focus IPC
   → state = .opening; KeyboardShortcuts.disable(.popup)                    Popup.swift:119-120

【window 变 key，同一事件触发两条链】
 → NSWindow.didBecomeKeyNotification
   → FloatingPanel.windowDidBecomeKey                                       FloatingPanel.swift:180
     ③ preview.enableAutoOpen(); if leadHistoryItem→preview.startAutoOpen   (lead 已被①设)   ← preview 武装#1
   → ContentView.onReceive(didBecomeKey) → scenePhase = .active             ContentView.swift:64-69
     → HistoryListView.onChange(scenePhase)                                 HistoryListView.swift:115
       ④ searchFocused=true; isKeyboardNavigating=true
       ⑤ navigator.select(item: unpinnedItems.first ?? …)                   HistoryListView.swift:119  ← select#2（重复）+ O(n) filter
          → 又一次 scrollTarget 变更 → .task(id: scrollTarget) 周期#2
       ⑥ preview.enableAutoOpen/reset/startAutoOpen                         HistoryListView.swift:120-122  ← preview 武装#2（重复）

【首帧 SwiftUI 布局】
 HistoryListView.body                                                       HistoryListView.swift:68
   ⑦ pinnedItems / unpinnedItems（各一次 O(n) filter）                       HistoryListView.swift:16-21
   ⑧ MultipleSelectionListView → ForEach(Array(items.enumerated()))         MultipleSelectionListView.swift:10  ← 全量数组分配/body
      → 每可见行 HistoryItemView → ListItemView                             HistoryItemView.swift:34
        ⑨ ColorImage.from(item.title)（非图项每渲染一次 hex 解析）          HistoryItemView.swift:40
        ⑩ ListItemTitleView: Text(verbatim:) + .lineLimit(1) + .drawingGroup()  ListItemTitleView.swift:14-20  ← 每行一个 Metal backing store
   ⑪ readHeight GeometryReader ×2 + needsResize GeometryReader              HistoryListView.swift:95,159,130-141  ← 强制 layout pass
   ⑫ .animation(.default.speed(3), value: items)                            ContentView.swift:35
 → 首帧 CA commit（WindowServer 同步）
```

首帧的同步主线程成本 = ①O(n) filter + ②WindowServer IPC + ⑤重复 select/scrollTarget
+ ⑦⑧全量分配/filter + ⑪多个 GeometryReader layout pass + ⑫动画 + CA commit。单项
都 <16ms，**但在同一次事件栈里串行叠加**就是 `sample` 看到的数十 ms。

### 场景 B —— 每次复制（resident，最高频）

```
Clipboard.checkForChangesInPasteboard（gates on main）→ Task{ await ingestor.ingest }  Clipboard.swift:218   ← 重活已 off-main（BS-2）
 → actor 单事务写 → onEvent hop 回 main → History.consume(.added/.merged)              History.swift:276
   → reconcileWithStore                                                                History.swift:291
     ⓵ 全表 context.fetch(FetchDescriptor<HistoryItem>())  ← 无 fetchLimit              History.swift:294
     ⓶ sorter.sort(sorted)  ← 双稳定排序 + byPinned 比较器内读 Defaults[.pinTo]          Sorter.swift:26-30,43
     ⓷ 重建 all/items + cleanup + select(first)                                         History.swift:300-322
     ⓸ popup.needsResize = true                                                         History.swift:323   ← 每次复制都设
       → .task(id: needsResize) → sleep10 → popup.resize → panel.verticallyResize       HistoryListView.swift:133-139 / FloatingPanel.swift:95
         → NSAnimationContext 0.2s animator().setFrame  ← 动画 CA commit（高度未变也开 CA 事务）
```

每次复制的主线程成本 = ⓵全表 fetch + ⓶双排序（含 O(n log n) 次 Defaults 读）
+ ⓷重建 + **⓸动画 resize**。前三个是 BS-4.4a 目标；⓸是路标**未覆盖**的复制期渲染风暴。

### 场景 C —— 鼠标 hover 越行

```
MouseMovedViewModifier（NSTrackingArea）→ onMouseMove → isKeyboardNavigating=false   ContentView.swift:44
ListItemView.hoverSelectionId → .onHover                                            ListItemView.swift:140
 → HoverSelectionModifier → selectWithoutScrolling(id)                              HoverSelectionModifier.swift:11   ← scrollTo 风暴已止（P1）
   → selectInHistory: leadHistoryItem=item; selection=[item]                        NavMgr.swift:190
     ⓵ selection.willSet: 旧项 selectionIndex=-1, 新项 selectionIndex=index          NavMgr.swift:16-18   ← 行重渲染
     ⓶ leadHistoryItem.didSet（id 变）: Task{ previous.cancelPreviewGeneration() }    NavMgr.swift:48-51   ← async hop
                          + preview.startAutoOpen                                    NavMgr.swift:55
```

快速划过 N 行 = N×（⓵ selectionIndex 两次写 → 行重渲染 + ⓶ leadHistoryItem 变 →
preview 取消 hop + auto-open）。`cancelPreviewGeneration` 是 async 会合并一部分，
但 selectionIndex 是同步写、逐行抖动。

---

## 3. 风暴目录（S1–S17）

| ID | 风暴 | 触发 | 现状 | 归位 |
|---|---|---|---|---|
| S1 | `load()` 全表 fetch+sort+decorate 0.999s | 冷启动 | 仍存 | **BS-4.3** |
| S2 | 打开时 select(first) 两次（`Popup.open` + scenePhase.active），两次 scrollTarget 周期 | 每次打开 | 仍存 | **4.10a** |
| S3 | preview auto-open 武装两次（windowDidBecomeKey + scenePhase.active） | 每次打开 | 仍存 | **4.10a** |
| S4 | `unpinnedItems`/`pinnedItems` 每次 body 多次 O(n) filter | 打开/hover/复制 | 仍存 | BS-6（缓存分区间） |
| S5 | 首帧全树布局 + 多个 GeometryReader 强制 layout pass | 每次打开 | 部分固有 | **4.10**（合并 GeometryReader） |
| S6 | `orderFrontRegardless`+`makeKey` WindowServer key-focus IPC | 每次打开 | 大部分固有 | **仅评估，不改**（见 §6） |
| S7 | 每可见行 `.drawingGroup()` Metal backing store + CA commit | 首帧 | 仍存（macOS 26 翻转 workaround `ListItemTitleView.swift:18-20`） | **4.10e**（评估精细化） |
| S8 | `reconcileWithStore` 每复制全表 fetch+sort 0.324s | 每次复制 | 仍存 | **BS-4.4a** |
| S9 | 每复制 `needsResize=true` → 动画 verticallyResize（CA 事务） | 每次复制 | 仍存 | **4.10b**（仅高度真变才动画） |
| S10 | 每复制 `.animation(value: items)` 触发 | 每次复制 | 与 S9 叠加 | **4.10b** |
| S11 | `Sorter.byPinned` 比较器内读 `Defaults[.pinTo]`，O(n log n) 次/sort | load/复制 | 仍存 | **先行落地（本批）** |
| S12 | hover 越行：selectionIndex 逐行写 + leadHistoryItem didSet 抖动 | hover | 仍存（scrollTo 风暴已止） | **4.10c** |
| S13 | `ForEach(Array(items.enumerated()))` 每 body 全量分配 | 每次 body | 小 | **4.10d** |
| S14 | 行 body `ColorImage.from(item.title)` 每渲染 hex 解析/位图生成 | 每次 body | 仍存（lockFocus 路径未缓存） | **先行落地（本批）**；深治见 4.10d |
| S15 | 行 body `@Default(.showApplicationIcons)` 每行读 | 每次 body | 小 | **4.10**（注入 environment） |
| S16 | decorator `init` 复制 `imageData` blob（200×~1MB≈200MB 常驻） | load | 仍存 | **BS-6** |
| S17 | **无「常驻打开」测量闸门**（`G-popup-open`=load 测不到 D2） | — | 缺口 | **新增 `G-resident-open`** |

---

## 4. 与 BS-4 编译边界的关系

S2/S3/S5/S7/S9/S10/S12/S13/S15 都是**纯主线程 UI 改动**，不改数据语义、不跨
actor、不碰 SwiftData —— 全部落在 BS-4 编译边界内，作为 **4.10** 收编（见
`step-4-data-pipeline.md` 增补节）。S11/S14 是零行为变更的纯性能微优化，先行独立
落地（本批）。S1/S8 是 4.3/4.4a；S4/S16 是 BS-6。

---

## 5. 外部 GPT 分析对质（逐条用代码核实）

**命中且仍存**（值得做）：
- 打开路径同步工作过重 → S2/S5/S6
- hover hit-testing 抖动 → S12（它没区分「scrollTo 风暴已止」与「selectionIndex
  残留」，方向对，落点需精修）
- CA backing store / 动画 commit → S9/S10/S7
- 每行 Defaults 读 → S15（小但真实）

**误判**（不要照做）：
- **W1「row body 读 SwiftData / contentData，触发 fault」** —— 证伪。行 body
  （`HistoryItemView.swift:34`→`ListItemView.swift:49`）只读 decorator 的**缓存字段**：
  `title`（stored String）、`thumbnailImage`（async）、`applicationImage`（init 时缓存
  `HistoryItemDecorator.swift:124`）、`attributedTitle`/`shortcuts`（stored）、
  `isSelected`（selectionIndex 派生）。**不直接读 `@Model` 属性**，不 fault。
- **W2「row body 读 `application` String → `NSWorkspace.urlForApplication` 每渲染」**
  —— 证伪。行用的是 `item.applicationImage`（缓存图）。慢的 `application` String
  计算属性（`HistoryItemDecorator.swift:53-65`）只在 `PreviewItemView.swift:64`（单项
  预览栏）读一次。外部把预览栏的单次调用当成了每行每帧。
- **W3「clipboard check 可能是主因」** —— 已 BS-2 搬后台（`Clipboard.swift:218`
  `Task{ await ingestor.ingest }`），外部自己也降到 P2。确认非主因。
- **W4（隐含）「打开即 load」** —— 见 §1，load 是启动期一次性。
- **「P0：延后 open 到下一 runloop（`DispatchQueue.main.async { open }`）」**
  —— **拒绝**。它只是把成本挪后，墙钟延迟不变、反而 +1 帧；对感知延迟无益，对系统
  事件响应仅边际收益。真正的解法是**减少这数十 ms 本身**（S2/S5/S9），不是 defer。

---

## 6. S6（窗口 `makeKey`/`orderFront` 的 WindowServer IPC）评估结论

**不改。** panel 必须在打开时**同步**成为 key，才能立即接收 cycle 模式后续按键
（`Popup.handleRepeatedHotKeyDown` 依赖 panel 已 key）。`FloatingPanel` 用
`.nonactivatingPanel`（`FloatingPanel.swift:27`）+ `canBecomeKey=true`（`:210`），
`orderFrontRegardless()`+`makeKey()`（`:78-79`）已是最小必要调用集。延后 `makeKey`
会破坏热键 cycle 交互。`sample` 里的 `_stealKeyFocusWithOptions`/`SLPS*` 是
`makeKey` 在 SkyLight 的固有下沉，**属固有成本，记录在案、不动**。外部「延迟
makeKey」建议同 P0 defer 一起拒绝。

---

## 7. 原始 sample 复核（2026-06-22 用户上传 `Maccy.sample.txt`）

用户上传了 GPT 分析所用的**原始** `sample`（每 1ms 一次，主线程 7519 采样）。**关键事实**：
`Identifier: org.p0deje.Maccy`、**Version 2.6.1 (60)**、`/Applications/Maccy.app` —— 这是
**发布版 2.6.1**，**没有**本仓库的 BS-1/2/3 与渲染止血（固定行高 / hover-no-scroll /
preview 取消）。Launch→sample 间隔 ~12h（**常驻**运行）。所以 sample 反映的是**未修复
发布版的常驻渲染链**：用它**校准方向**，但绝对量级不等于当前 fork（止血已大幅压低）。

### 7.1 真实热点排序（采样数；树去重后相对量级，含祖先链重复）

去掉 runloop 等待后，**实际工作几乎全在 SwiftUI 布局 + CoreText 文本测量**：

| 类别 | 代表帧（采样数） |
|---|---|
| **SwiftUI 布局 / sizeThatFits** | `LayoutEngineBox.sizeThatFits` **231**、`LayoutProxy.size(in:)` 164、`UnaryLayoutEngine.sizeThatFits` 163、`ViewLayoutEngine.sizeThatFits` 85、`StackLayout.placeChildren` 75/74/65、`_PaddingLayout` 57、`_FlexFrameLayout` 51 |
| **AttributeGraph** | `AG::Graph::UpdateStack::update` 78、`update_attribute` 71、`input_value_ref_slow` 60、`AGGraphGetValue` 46 |
| **CoreText 文本塑形** | `TRunGlue.*` 325、`TGlyphIterator` 187、`CFStringGetRangeOfCharacterClusterAtIndex` 91（grapheme cluster）、`TGlyphEncoder::RunUnicodeEncoderRecursively` 87、`TOpenType*` 94、`_NSOptimalLineBreaker` 101、`NSCoreTypesetter` 39 |

`sizeThatFits` 家族 + CoreText 塑形合计**压倒性占比**。

### 7.2 触发链：窗口帧动画 → 每帧全树 `NSHostingView.layout()`

1790 采样的 source1（display-link）子树揭露因果链：

```
CA::Display::DisplayLink::dispatch_items → -[_NSDisplayLinkForwarder displayLinkDidFire:]
 → +[NSAnimationManager performAnimations:] → +[NSAnimationContext runAnimationGroup:]
   → CABasicAnimation → -[NSWindow _setFrameCommon:display:fromServer:]        ← 窗口帧动画(verticallyResize / slideout)
     → -[NSWindow _layoutViewTree] → -[NSView layoutSubtreeIfNeeded]
       → NSHostingView.layout() → ViewGraphRootValueUpdater.render             ← 每帧重布局整棵 popup SwiftUI 树
         → AttributeGraph 更新 + Accessibility 更新 + CoreText 文本重测量
```

**一个 0.2s 的 `NSAnimationContext` 窗口帧动画（`FloatingPanel.verticallyResize` 或 slideout
宽度动画），在每帧（≈12 帧）强制 `NSHostingView.layout()` 整棵树 → 重测所有可见行文本**。
这是 sample 里布局/文本风暴的**驱动源**，即 §3 的 **S9/S10**。

### 7.3 GPT 叙事被原始帧证伪

GPT 以「热键→打开→`makeKeyWindow`/`_stealKeyFocus`/`SLS*`→CA commit」为 P0 主线。**原始
sample 里这些帧采样数 ≈ 0**：

| GPT 宣称的热点帧 | sample 实测 |
|---|---|
| `handleHotKeyEvent` / `Popup.open` / `FloatingPanel.open` | **0** |
| `makeKeyWindow` / `_stealKeyFocusWithOptions` / `SLPSStealKeyFocus` / `SLSCopyWindowRoutingRecords` | **0**（GPT 引用的这些帧**不在 sample 里**） |
| `CA::Transaction::commit` / `CABackingStore*` | **0** |
| `mouseMoved` / `onHover` / `HoverSelection` / `hitTest` | `hitTest` 仅 9 + 8 |
| `ApplicationImage` / `ColorImage` / `Defaults` / `NSColor(hexString:)` / `urlForApplication` | **0**（W1/W2 在 sample 里也不成立） |

**且 `main` 是唯一高采样的 Maccy-image 符号** —— app 自己的 Swift 代码不是瓶颈，全是
SwiftUI/AppKit/CoreText 框架工作。**结论**：GPT 的「打开路径/窗口聚焦/CA/hover」叙事
**不被原始数据支持**；真实主因是**动画驱动的每帧全树布局 + 文本测量**。GPT 看到了
layout/CA **症状**但归因到错误的**触发源**。

### 7.4 据 sample 重排 4.10 优先级 + 新增 4.10f

sample 把 **S9/S10（动画 resize → 每帧全树布局）** 钉为 **#1**，高于 S2（open 去冗余）/S6
（窗口操作，本就固有）/S12（hover）。并暴露一个 GPT 和原目录（§3）都漏掉的真实放大器：

- **新增 4.10f 列表标题测量削减** —— 行标题 `item.title` 上限
  `titlePreviewLimit = 1_000`（`HistoryItem.swift:9`），且 `ListItemTitleView` 用
  `.truncationMode(.middle)`（`ListItemTitleView.swift:12,17`）。**middle 截断要求 CoreText
  测量整个字符串**才能定中点 → 每个可见行测 ~1000 字符；单行实际只显示 ~60–80 字符。改进：
  (a) 列表标题**展示**上限降到 ~150–200 字符（完整标题仍用于预览/tooltip）；(b) 评估
  `.tail` 替 `.middle`（tail 可增量早退；但 middle 是产品意图——代码/URL 看头尾——需权衡）。
  把每行 CoreText 工作砍数倍。

**重排后 4.10 优先级**：4.10b（S9/S10 动画 resize，#1）→ 4.10f（标题测量，新增，#2）→
4.10e（drawingGroup）→ 4.10a / 4.10c / 4.10d。

### 7.5 sample 与当前 fork 的关系

sample = 发布版 2.6.1（**无**止血）。本 fork 已落：固定行高（`6bc92d7`，阻断 height 反馈
环）、`LazyVStack`、`lineLimit(1)`、preview 取消。所以 fork 上动画驱动的布局/文本成本**已
比 sample 低**，但**驱动源（窗口帧动画 → 每帧 `NSHostingView.layout`）和放大器（1000 字
middle 截断标题）仍在** —— 正是 4.10b + 4.10f 的目标。新增 `G-resident-open` 闸门
（`step-4-data-pipeline.md`）将量化 fork 上的真实残余量。

---

## 8. 关联

- 前序：`2026-06-21-render-feedback-stopgap.md`（P0/P1/P2/P3 止血）。
- 落点：`roadmap/step-4-data-pipeline.md` §4.10（增补）；闸门 `G-resident-open`
  （`roadmap/B-test-strategy.md §4` + step-4 闸门表）。
- 依据 memory：`mainthread-probe-delay-metric`、`ingest-live-path-reconcile-not-findSimilar`、
  `mixed-list-layout-storm`、`perf-harness-rework-state`。

## 9. 落地进度

- **2026-06-22 4.10b（S9/S10）landed** — `FloatingPanel.verticallyResize` 去掉 `NSAnimationContext`
  0.2s `animator().setFrame`，改为即时 `setFrame`。**行为变更（路标 4.10b 授权）：弹窗不再有
  0.2s 的尺寸 settle 动画，改为瞬时到位（体感更跟手）。** 原动画在每帧 display-link 强制
  `NSHostingView.layout()`（整棵 popup 树 + CoreText 重测）—— 即 §7.2 的风暴驱动源与
  image/mixed 的 `G-popup-open` maxGap(800ms+)。一次 `setFrame` = 一次 layout。待 perf shard
  量化收益（image/mixed maxGap 应大幅下降）；若 UX 上仍想要动效，可改为极短时长（如 0.05s）
  作为折中。

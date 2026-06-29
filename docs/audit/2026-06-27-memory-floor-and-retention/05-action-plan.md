# 行动计划(去重,含 MB 估算与执行序)

> 从当前 135 MB 出发,逐项估算与执行序。**所有 MB 都是推断**,需 [06](06-gating-diagnostics.md) 的 MallocStackLogging 重抓确认。

## 0. 重叠警告(最重要,别算错)

**C5 / C7 / F1 共享同一个 17.5 MB 内容 blob 池,不能相加:**

| 项 | 作用 | 朴素估算 | 实际 |
|---|---|---:|---|
| C5 窗口化 | 限制**新 blob 被 fault 的速率**(冷开不全表) | 6–13 MB | |
| C7 延迟 contents | 同上,延伸到关系 | 3–8 MB | **与 C5 同池,增量** |
| F1 BS-8 blob store | 把 blob 移出 SwiftData,**逐项可回收** | 12–15 MB | **subsumes C5/C7 上限,非叠加** |

→ blob 池的去重上限 **~12–15 MB**,不是 31 MB。整个计划去重后真实可榨 **~20–35 MB**。

## 1. 优先级表(执行序)

| 序 | ID | 动作 | 估 MB | E | 风险 | 门控 D1? | 信心 |
|---|---|---|--:|---|---|:--:|---|
| 0 | **D1** | MallocStackLogging 重抓(3 时间点 + 变体) | **0(但移除 ~10 MB 不确定性)** | S | 无 | — | 高 |
| 1 | **C6** | 接上 `releaseTransientImages(.previewHidden)`(关窗释放 preview 位图) | 1–2 | S | 低 | 否 | 中 |
| 2 | **T1a** | 存+取消 12 个常驻 `Defaults.updates` Task | ~0.5 | S | 低 | 否 | 中 |
| 3 | **C5** | **接入 VisibleWindowLoader**(`History.load()` 全表→可见窗口) | **6–13** | L | **中-高**(行为) | 是 | 中 |
| 4 | **T1b** | copy storm Task coalesce(`Clipboard.swift:224`) | 0.5–3 | M | 中 | 是 | 低 |
| 5 | **C7** | 延迟 `HistoryItem.contents` fault(延伸 lazy imageData) | 3–8 | L | 中 | 是 | 中 |
| 6 | **U1** | AttributeGraph 视图树瘦身(`HelpView`/ForEach 密度) | 3–8 | M | 低(若 D1 证实 AG) | 是 | 低 |
| 7 | **F1** | BS-8 xxh3 哈希 + 持久化 fingerprint 列 + **独立 blob 存储** | subsumes 3/5(12–15 MB 上限) | L | 中 | 是 | 中 |

## 2. 各项要点

### D1 —— MallocStackLogging 重抓(先做,见 [06])
零代码改动。把 41.7 MB 盲区从推断变实测;分解地板/单项/斜率;**定论 blob 能否回收**(决定 C5 够不够还是必须 F1)。

### C6 —— `.previewHidden` 接线(免费,S)
- `HistoryItemDecorator.swift:217` 的 `.previewHidden` case **零生产调用者**(workflow grep 确认)。
- 在 `FloatingPanel.close()`(`:217-224`)和 `SlideoutController` 的 togglePreview-close 里,对**上一个 previewedItem** 调 `releaseTransientImages(.previewHidden)`。
- 低风险:重 preview 会重新解码(previewDelay 隐藏延迟;缩略图在 ThumbnailCache 不受影响)。
- 守卫:`previewImageGenerationTask == nil`(别和在飞的 async preview 竞争)。

### T1a —— 12 个常驻 Task 存+取消(S)
- `History.init`(`:169-203` ×6)+ `AppDelegate`(`:80-121` ×6)的 `Defaults.updates` fire-and-forget Task,**句柄未存、未取消、整会话常驻**。
- 存进 `@ObservationIgnored private var defaultTasks: [Task<Void,Never>]`,`deinit` cancel。或合并成单个监听。
- 直接内存仅几十 KB;价值是降 always-live 基线 + Swift 6 并发审计前置。

### C5 —— 接入 VisibleWindowLoader(L,首选内容杠杆)
- `History.load()`(`:213-219`)用裸 `FetchDescriptor` 全表 fault → 换成 `Storage.newBackgroundContext()` + `VisibleWindowLoader.fetchWindow`(`Storage+Background.swift:47-75`)取可见窗口,主线程只装饰可见项,尾部低优预取。
- **冷开 O(n) → O(v)**。
- **行为风险(必须审计)**:`updateUnpinnedShortcuts`(`:814-825`)给前 9 个**可见**项分配快捷键前缀;scroll-to-selection;items-transition 动画(`ContentView.swift:41`);以及所有遍历 `all`/`items` 假设完整的路径:`limitHistorySize`(`:231`)、`findSimilarItem`(`:728`)、togglePin 排序(`:711`)、search `within: all`(`:104`/`:794`)、PasteStack/PinsView。VisibleWindowLoader 把 pin 分区延后给调用方(`Storage+Background.swift:33-38`),尾部合并必须保持 pin 顺序。
- **注意**:LazyVStack(`MultipleSelectionListView.swift:9`)已只构建可见行 view body → C5 对 **SwiftUI view body 成本**无收益;收益在 (a) decorator 壳 + `@Model` 壳 + app 图标 + observation registrar + ForEachState identity 数组,(b) **限制新 blob 被 fault 的速率**。
- **注意**:因 SwiftData 无单行 fault-out(见 [03](03-retention-root-cause.md) §4),已 fault 的 blob 不因窗口化而释放 → 6–13 MB 的**低端**更可能,除非配合 F1。

### T1b —— copy storm coalesce(M)
- `Clipboard.swift:224` 每个 `changeCount` 变化 spawn `Task { await ingestor.ingest(request) }`,request 带**全部** pasteboard Data blob。快 copy 时队列里留 N 份完整 payload。
- 存 Task 句柄,新 copy 时 cancel-and-replace,**只留一个在飞**。语义上 changeCount guard 已保证只处理最新,但取消时序不能丢合法的新 changeCount。
- 收益随 均blob × 在飞copies 缩放,仅当 copy 快于串行执行器排空时(需 D1 的 idle-vs-storm 抓取确认)。

### C7 —— 延迟 `contents` fault(L)
- 把已落地的 lazy `imageDataCache`(`HistoryItemDecorator.swift:83-91`)延伸到 `contents` 关系:冷开和稳态都不全表 fault `HistoryItemContent`。
- 触碰 `@Model` accessor 和 dedup signature 路径,中等风险。
- 与 C5 同池(增量收益,3–8 MB 是"也延迟关系 vs 只窗口化"的差额)。

### U1 —— AG 视图树瘦身(M)
- 目标 `non-object` 里 ~25–30 MB 的 AG 图节点体。
- `HelpView<...HStack<TupleView<...KeyboardShortcutView...>>>` 1280B×101、密集 `DynamicViewList<TypedElement>`/ForEach-over-KeyShortcut 是每行 AG 放大器。
- 坍缩 ListItemView 树(减少嵌套 ModifiedContent/HStack/ForEach)、提高 LazyVStack 复用、无快捷键的行不渲染 KeyboardShortcutView。
- **需 D1 证实 AG 占比**;若 D1 显示盲区其实是别的(隐藏 Data 路径/不 purge 的 CoreText 缓存),U1 可能近无效或更大。

### F1 —— BS-8 哈希 + 持久化 fingerprint + 独立 blob 存储(L,可能强制)
- xxh3/wyhash 替 FNV-1a(`ClipboardByteProcessor.cpp:78-84`,向量化、avalanche 强);`HistoryItemContent` 加持久化 `(size, fingerprint)` 列(轻量迁移);`dataLikelyEqual` 双侧传指纹。
- **+ 独立 blob 存储**:把大内容移出 SwiftData 的 `_KKMDBackingData`,用文件/独立表按 id 索引。这是唯一在保持 `@Model` 身份下逐项回收 blob 的 sound 路径(SwiftData 无单行 fault-out)。
- subsumes C5/C7 的 blob 上限(~12–15 MB),非叠加。

## 3. 算式

```
当前 135 MB(6h)
 - C5  内容窗口化 ..............  -6~13
 - C7  延迟 contents(同池增量)..  -3~8    [注意与 C5 共享池]
 - U1  AG 视图树瘦身 ............  -3~8
 - C6  preview 关闭释放(免费)..  -1~2
 - T1  并发卫生 .................  -~1
 ───────────────────────────────────────
 去重后现实总收益 ...............  -20~35
 → 稳态 ~100–115 MB

 + F1  blob 池压到 ~3-5 MB(独立存储)  再 -8~12
 → ~85–95 MB(现实稳态目标)

 80 MB = 还要 U1 落到上限 + 小历史 + 短会话(乐观天花板)
 50 MB = 135 - 85 = 地板之下,数学不可能
```

## 4. 执行纪律(沿用 master plan)

- TDD(行为变更先失败测试)→ 最小正确实现 → 聚焦测试 → 提交(信息含 roadmap 项,如 `feat(bs6.x): ...` 或新编号 `perf(mem27-C5): ...`)→ 推 CI → CI 绿即过。
- **无本机工具链**(`CLAUDE.md`):lint/compile 只在 CI(~11 min)显现;push 前自检(grep privacy:、awk length>120、doc 挂载、@Sendable self 捕获)。CI 坑见 `15-progress-and-resume.md` §5。
- **UX 门禁**(弹窗热键、预览、滚动)用户择机手测,不阻塞推进。
- 每步范围限于当前 step + 其测试;偏离先记进审计文档再提交。

## 5. 建议起手

1. **D1**(用户在 macOS 跑 MallocStackLogging 重抓,零代码)—— 最高 ROI 的下一步,解锁所有数字。
2. **C6**(免费,S)—— 不依赖 D1,可立即做。
3. **T1a**(免费,S)—— 不依赖 D1,可立即做。
4. D1 结果回来后,据归因决定 **C5 先做还是直接 F1**:
   - 若 blob 可被窗口化释放 → C5 + C7。
   - 若 blob 被 `_KKMDBackingData` 死死 pin 住 → 跳到 F1(独立 blob 存储)。

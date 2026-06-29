# 已完成 / 待办 / 继续做 —— 对照 06-25 master plan

> 把 06-25 master plan(已删除)的每一项映射到 2026-06-27 的当前状态。**这是"做了什么、还做什么"的单页总账。** 注意:该 plan 多处状态已被 06-28 gap-audit 进一步推翻(见 [`../2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md`](../2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md))。
> 状态图例:✅ DONE(CI 绿) · ⏸️ DEFERRED(有理由暂缓) · 🔼 REOPENED/ELEVATED(06-27 升级优先级) · 🆕 NEW(06-27 新增) · ❌ CLOSED(已无效)

## 1. D1 —— MallocStackLogging 重抓:`⏸️ → 🔼 关键前置`

06-25 把 D1 降级为"不再关键"(依据 2 分钟 102 MB 基线)。**06-27 数据推翻该降级**:

- 6h = 135 MB(+33 MB 滞留斜率),2 分钟基线**掩盖了斜率**;
- 41.7 MB `non-object` 盲区比 06-25 的 20.2 MB **翻倍**,且仍是未归因的最大桶;
- 必须分解"地板 62 MB vs 单项成本 vs 6h 斜率",现在只有两点(2min/6h),**无空基线**。

→ **D1 重新升为关键前置**。在它之前,所有 MB 估算都是推断,地板带 ±10 MB 不确定性。协议见 [06](06-gating-diagnostics.md)。

## 2. P0 tier —— 全部 ✅ DONE(C5 除外,见 P1)

| ID | 问题 | 状态 | 提交 / 说明 |
|---|---|---|---|
| M1 | HotKey 重注册泄漏 ~43 MB | ✅ DONE | `bs6.13`,CI green `28163959693` |
| M2 | KeyboardLayout TIS 泄漏 | ✅ DONE | `0686630`;18,417 个 `TSMInputSource` leak → 基线 ~13 |
| M3 | sessionLog 强引用 `@Model` | ✅ DONE | `7c3e57d`;改为 `[Int: PersistentIdentifier]`。**06-27 确认仍是 PersistentIdentifier(非 @Model),杠杆关闭** |
| M4 | ApplicationImageCache 无界 + fd | ✅ DONE | `1a6d465`;NSCache(128)+ fd defer + `[.delete,.rename]` + logger。**06-27 确认仍 bounded** |
| M5 | ignoredRegexps 无界 | ✅ DONE | `6f0ce23`;NSCache(64)+ Defaults 重建。**06-27 确认仍 bounded** |
| M6 | bulk 循环无 autoreleasepool | ✅ DONE | `57d3053`;load/clear/clearAll |
| M7 | withLogging 4 次 fetchCount | ✅ DONE | `faf5e4d`;`#if DEBUG` 门 |
| M8 | updateUnpinnedShortcuts churn | ⏸️ DEFERRED | KeyShortcut 非 Equatable,低价值 |
| M9 | ColorImage 仅 countLimit | ✅ DONE | `18c336e`;ColorSwatch totalCostLimit + drawingHandler |
| M10 | settingsWindowController 常驻 | ✅ DONE | `6193256`;willCloseNotification → nil |

**06-27 关键结论:`unbounded-caches` 杠杆整体 ❌ CLOSED**——5 个缓存(sessionLog + 4 cache)全部已 bounded,heap 只 96 NSImage(153 KB)。**别再投入这条。**

## 3. P1 tier —— C1/C2/C3 ✅,C4/C5 ⏸️(C5 应 🔼)

| ID | 问题 | 状态 | 说明 |
|---|---|---|---|
| C1 | 内存脚手架(MemoryGovernance/VisibilityTracker/DecodedImageCache) | ✅ DONE | `a524dd8` + `7ef4a88` + `9fd186e`(id-only protocol,别把 decorator 拉成 @MainActor) |
| C2 | decorator `releaseTransientImages(_:)` + 去常驻 | ✅ DONE | `a524dd8`;imageDataCache 已 lazy(`HistoryItemDecorator.swift:83-91`) |
| C3 | 视图接线 + 内存压力挂载 | ✅ DONE | `9ae4644`;HistoryItemView onAppear/onDisappear + AppDelegate MemoryGovernor |
| C4 | 观察环 + token | ⏸️ DEFERRED | `isInvalidated` 守卫已限制,低价值 |
| **C5** | **接入 VisibleWindowLoader** | ⏸️ → **🔼 首选** | **死代码**(Storage+Background.swift:47-75,仅测试调用)。06-27 升为**首选内容 blob 杠杆**(6–13 MB)。是 L + 高行为风险(见 [05](05-action-plan.md)) |

## 4. P2 tier —— S1/S2/S3 ⏸️(不变)

| ID | 问题 | 状态 | 说明 |
|---|---|---|---|
| S1 | 搜索 actor 化 | ⏸️ DEFERRED | 已设计(`p2-search-off-main-design` 记忆,workflow + 对抗验证,朴素版 5 bug,可靠版可直实现)。当前小历史搜索 sub-ms,低价值 + 复杂 |
| S2 | copy 路径 title/RTF/HTML off-main | ⏸️ DEFERRED | copy 路径最后一处主线程阻塞 |
| S3 | ignoredRegexps 扫描移入 ingest actor | ⏸️ DEFERRED | M5 已做缓存,本步做离主 |

## 5. P3 tier —— F1 🔼(可能强制),其余 ⏸️

| ID | 问题 | 状态 | 说明 |
|---|---|---|---|
| **F1** | **BS-8 C++ 哈希(xxh3)+ 持久化 fingerprint 列** | ⏸️ → **🔼 可能强制** | 06-27 发现 SwiftData 无单行 fault-out API → **把大内容移出 SwiftData 的独立 blob 存储**(F1 的延伸)可能是唯一 sound 的 blob 回收路径。从"可选"升为"可能强制" |
| F2 | BS-7 Swift 6 严格并发 | ⏸️ DEFERRED | 大工程,前置 P0/P1/P2 |
| F3 | 单例掩盖 ARC 清理簇 | ⏸️ DEFERRED | 随 F2 一并做(12 个常驻 Task 等) |
| F4 | 安全/防御 trap | ✅ DONE(部分) | `8f38224`:ImageDownsampler NaN/∞ + String.shortened 负长度。C++ null guard 跳过(Swift Data 桥不传 null+count>0) |
| F5 | SwiftData `#Index` 宏 | ⏸️ DEFERRED | 大历史查询加速 |
| F6 | ThumbnailCache 磁盘索引 | ⏸️ DEFERRED | 写频繁才值得 |
| F7 | PassthroughImageProcessor 守护 | ⏸️ DEFERRED | 防 BS-2 wiring 失败静默回退 |
| F8 | 杂项(BinaryInsertion / processPendingChanges / Timer tolerance) | ⏸️ DEFERRED | |

## 6. 06-27 新增项 🆕

| ID | 问题 | 估 MB | E | 说明 |
|---|---|--:|---|---|
| **C6 🆕** | 接上 `releaseTransientImages(.previewHidden)` | 1–2 | S | enum case 在 `HistoryItemDecorator.swift:217` 已定义,**零生产调用者**。`FloatingPanel.close()`(`:217-224`)关窗时调用。**免费** |
| **C7 🆕** | 延迟 `HistoryItem.contents` fault | 3–8 | L | 把已落地的 lazy imageDataCache(`:83-91`)延伸到 `contents` 关系,冷开/稳态不全表 fault。与 C5 同池,增量收益 |
| **U1 🆕** | AttributeGraph 视图树瘦身 | 3–8 | M | `HelpView<...>` 1280B×101、密集 ForEach 是每行 AG 放大器。坍缩 ListItemView 树、提高 LazyVStack 复用、无快捷键行不渲染 KeyboardShortcutView。需 D1 证实 AG 占比 |
| **T1 🆕** | 并发卫生:存+取消 12 个常驻 Task + copy coalesce | ~1 | S–M | `History.init`/`AppDelegate` 的 `Defaults.updates` 句柄存起来 + dealloc 取消;`Clipboard.swift:224` copy Task 合并(cancel-and-replace),限制在飞 blob |

## 7. 已无效 / 撤销的分析项(06-25 已核实,06-27 复核仍成立)

- ❌ KeyboardLayout TIS = 36.6 MB 盲区?否(~575 KiB)。盲区是独立 non-object。
- ❌ `imageDataCacheLoaded` 非 `@ObservationIgnored`?否,它是。
- ❌ ForEach 用 `@Model` 做 identity?否,用 `id: \.element.id`(UUID)。
- ⚠️ 06-27 新增:**"无界缓存"杠杆整体关闭**(sessionLog + 4 cache 全 bounded)。
- ⚠️ 06-27 新增:**`mainContext.reset()` 是陷阱**,别用来回收 blob。
- ⚠️ 06-27 新增:**SwiftData 无单行 fault-out** → F1 独立 blob 存储可能强制。

## 8. 一页总账

```
DONE (CI 绿, ~24 commits through 8f38224 + 06-26/27 preview work):
  M1 M2 M3 M4 M5 M6 M7 M9 M10  C1 C2 C3  F4(部分)  + preview 系统改造

DEFERRED (有理由):
  M8  C4  S1 S2 S3  F2 F3 F5 F6 F7 F8

REOPENED / ELEVATED (06-27 升级):
  D1 (MallocStackLogging)  ⏸️→🔼 关键前置
  C5 (VisibleWindowLoader) ⏸️→🔼 首选内容杠杆
  F1 (BS-8 blob store)     ⏸️→🔼 可能强制

NEW (06-27):
  C6 (.previewHidden 接线)  C7 (延迟 contents fault)  U1 (AG 视图树瘦身)  T1 (并发卫生)

CLOSED (别再做):
  unbounded-caches 杠杆整体(sessionLog + ApplicationImageCache/ignoredRegexps/ColorImage/ThumbnailCache 全 bounded)
```

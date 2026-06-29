# 33 MB/6h 滞留增长:根因

> 06-25(2 分钟)= 102 MB → 06-27(6 小时)= 135 MB。**+33 MB,且 leaks 仅 19 KB(不是泄漏)**。本文定位滞留的结构性根因。

## 1. 根因:`mainContext` 是进程级累积器,从不回收

**验证(workflow grep 全仓)**:

```swift
// Maccy/Storage.swift:14-15
var context: ModelContext { container.mainContext }   // 单例 mainContext,创建一次
```

全仓搜索 `refresh(`、`refreshAllObjects`、`mainContext =`、`.reset()`、`automaticallyMergesChanges` → **只命中后台 context 创建点**(`Storage+Background.swift:18`、`ClipboardIngestor.swift:110`),**没有任何 `mainContext` reset/refresh 路径**。

机制:
1. `History.load()`(`History.swift:213-219`)用裸 `FetchDescriptor<HistoryItem>()`(`:214`,无 `fetchLimit`/`fetchBatchSize`/`returnsObjectsAsFaults`)→ fault + 物质化**全部** 185 个 `HistoryItem`。
2. 任何读 `item.contents` / `item.imageData`(`HistoryItemDecorator` 渲染、`Clipboard.copy` 回填、`generateTitle`)会进一步 fault 每个项目的 `HistoryItemContent` 行 + 其 `__DataStorage._bytes` blob。
3. **物质化后,`mainContext` 的行缓存(`_KKMDBackingData`)永久持有这些 blob**——删除项的 `@Model` 对象从 store 移除了,但它在活动 `mainContext` 里物质化的行缓存**从不清理**。
4. 6 小时里,`consume()` / `insertIncrementally` / `mergeDuplicateIfNeeded` 持续 fault 新行;旧行不释放 → **单调增长**。

heap 证据:**624 个 `HistoryItemContent` + 624 个 `_KKMDBackingData` 全部非常驻 fault**(对应 556 个 `__DataStorage._bytes` blob = 17.5 MB)。624/185 ≈ 3.4 内容/项,符合 `@Relationship(.cascade)` 多类型结构——**不是孤儿,是全表 fault**。

`non-object` 盲区同步增长(06-25 的 20.2 MB → 06-27 的 41.7 MB):一部分是 AG 图随交互重建碎片化,一部分是 CoreText/CoreSVG shaping 缓存随新内容膨胀。

## 2. 33 MB 增长的三段分解(地板分析 agent 推断)

| 机制 | ~MB | 说明 |
|---|--:|---|
| `HistoryItemContent` blob fault 累积 | ~15 | 6h 的 copy 活动,每个新内容行 + Data blob 被 fault 进 mainContext 不释放。均 31.5 KB/blob |
| CoreText / CoreSVG(SF Symbol)shaping 缓存膨胀 | ~10 | `CTRun`(839)、glyph storage 随新文字/字体组合累积,框架缓存,仅在内存压力时部分可 purge |
| AttributeGraph / `MALLOC_SMALL` 碎片化与滞留 | ~8 | zone 35% 碎片(32M/60M);6h 的开/关窗、预览切换、列表重建 churn AG 子图(1530 AGSubgraph),留下稀疏使用的 resident-dirty 页 |

## 3. 为什么不能直接 `mainContext.reset()`(陷阱)

`reset()` / `refreshAllObjects()` 看似能清行缓存,但:

1. **重新 fault 全表** → 下次开窗重新触发 `History.load()` 的全表 fetch + 装饰,**直接退回当初 `History.swift:218` 辛苦优化掉的冷开卡顿**(那是 0.999s 分解的来源,见 [[render-chain-sample-root-cause]])。
2. **破坏增量 `consume` 路径** —— `BackgroundClipboardIngestor` 的 `consume`/`reconcileWithStore` 假设 `decorator.item`(`@Model`)在主线程存活;reset 会让所有 decorator 持有的 `@Model` 失效。
3. ** invalidate 在飞编辑** —— `mergeDuplicateIfNeeded` 等路径假设上下文状态连续。

**结论:reset 是用冷开卡顿 + 正确性风险换内存的亏本买卖。别走。**

## 4. SwiftData 没有"单行 fault-out"API(关键限制)

这是整个 blob 回收问题的硬约束:

- `ModelContext.refresh(_:mergeChanges:)` 是**从 store 重填**缓存(更满),**不是清空到 fault**。
- SwiftData **没有** Core Data 那种 `context.refresh` 把对象 fault 回空值的等价能力,也没有按关系/属性 fault-in/fault-out 的细粒度控制。

**后果**:光把 decorator 窗口化(C5)**释放不了**底层 `_DataStorage._bytes` blob——只要 `mainContext` 的 `_KKMDBackingData` 还持有该行,blob 就在。窗口化只能省 decorator 壳 + `@Model` 壳 + app 图标 + observation registrar + 缩小 SwiftUI ForEachState identity 数组(这些都真实可省),**但 blob 池不动**。

→ 这意味着两条路:
- **保守**:C5(窗口化)+ C7(延迟 `contents` fault)能限制**新 blob 被 fault 的速率**(冷开不全表 fault),但已 fault 的不回收。收益偏中低端(6–13 MB)。
- **彻底**:**F1/BS-8 把大内容移出 SwiftData**,用独立 blob 存储(文件或独立表)按 id 索引。这是唯一能在保持 `@Model` 身份的同时逐项回收 blob 的 sound 路径。把 F1 从"可选结构性优化"**升为"可能强制项"**。

## 5. 次要滞留源(都已 bounded,贡献小)

- **263 个 Task stack**(263 KB 直接 + continuation 帧计入 `non-object`):12 个常驻 `Defaults.updates` 监听(`History.init` ×6 + `AppDelegate` ×6,句柄未存未取消)+ copy storm 每事件 spawn(`Clipboard.swift:224`,跨 actor hop 保留 blob)+ `NavigationManager` 每选择 spawn(`:49`)。
- **`releaseTransientImages(.previewHidden)` 零调用者**:enum case 在 `HistoryItemDecorator.swift:217` 定义了,但 `FloatingPanel.close()`(`:217-224`)**从不调用** → 每个 preview 过的 decorator 留一份解码 preview 位图。heap 只 96 NSImage(153 KB)+ IOSurface 2.8 MB dirty,贡献小但**免费可修**(C6)。

这些是卫生项,不解释 33 MB 主增长(主增长是 mainContext blob 累积)。

## 6. 验证假设的最小实验

定位"谁 pin 住 17.5 MB blob"的两个判别实验(详见 [06](06-gating-diagnostics.md)):

1. **滚览实验**:instruments/allocations 跟踪 phys_footprint,从头滚到底再等待。若 `__DataStorage` resident 单调增长不回落 → 确认 row-cache 累积(来自 `Clipboard.copy` / 渲染 fault),并量化 per-scroll 增量。
2. **近空 store 实验**:用 `enable-testing` 内存库或清空 DB 跑同一 6h 场景。若 blob 池随之消失 → 确认是历史内容 fault,不是别的 Data 引用路径。

这两个实验 + MallocStackLogging 一起,能把"mainContext 不可回收 blob"从推断变成定论。

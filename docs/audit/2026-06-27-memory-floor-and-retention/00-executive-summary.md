# 执行摘要:能不能压到 50–80 MB?

> 用户问题(2026-06-27):上传了一份 ~6 小时长运行的内存抽样,问"是否还有继续大幅优化的空间,想压到 50–80 MB"。
> 本文给结论。数据支撑见 [01](01-dump-decomposition-06-27.md),地板见 [02](02-framework-floor.md),滞留根因见 [03](03-retention-root-cause.md)。

## 1. 判定

| 目标 | 判定 | 依据 |
|---|---|---|
| **50 MB** | ❌ **不可能** | 框架不可压缩地板 ≈ **62 MB**(任何剪贴板内容之前)。50 MB 在地板之下 |
| **80 MB** | ⚠️ **乐观天花板** | 仅在完整 roadmap(BS-2 后台 context + BS-8 独立 blob 存储)+ 视图树瘦身 + 小历史 + 短会话齐备时摸得到。当理想上限,不当承诺 |
| **现实稳态** | ✅ **~85–100 MB** | 从当前 135 MB 可再榨 ~20–35 MB。诚实可达 |

## 2. 06-25 以来发生了什么(为什么结论变了)

06-25 的恢复指南(已删除)依据一份**短启动(2 分钟)**抽样得出"基线 ~102 MB、目标基本达成、D1 不再关键"。**这个判断被 06-27 的长运行抽样推翻**:

| 指标 | 06-25(2 分钟) | 06-27(~6 小时) | 含义 |
|---|---|---|---|
| `phys_footprint` | 102 MB | **135.5 MB** | +33 MB,**滞留累积** |
| peak | 191 MB | 229.3 MB | |
| **SWAPPED(压缩冷页)** | 0 | **58.6 MB** | 长运行产生大量冷页 |
| leaks | 14 KB | **19 KB** | 都可忽略 → **不是泄漏** |
| heap `non-object` 盲区 | 20.2 MB | **41.7 MB** | 翻倍 + 增长 |

**关键认知翻转**:2 分钟抓取的 102 MB **掩盖了滞留斜率**;6 小时才暴露出真实稳态在 135 MB 且仍在涨。所以"<100 MB 基本达成"是**假信号**。

## 3. 135 MB 到底是什么(都不是 Maccy 的锅)

- **`non-object` 盲区 41.7 MB**(109K 个分配,heap 归不了类)——按 zone 相关性推断 **~66% 是 AttributeGraph 视图图节点体**(AG zone 占 109K 中的 72K),其余是 CoreText/CoreSVG(SF Symbol)缓存 + Metal 描述符。**没开 `MallocStackLogging`,所以是推断不是实测。**
- **`__DataStorage._bytes` 17.5 MB**(556 个剪贴板内容 blob,均 31.5 KB)——全表 fault 进 `mainContext` 后**永不释放**。根因:`History.load()` 全表 fetch(`History.swift:213-219`)+ `mainContext` 从不 reset(`Storage.swift:14-15`,grep 全仓确认无 reset/refresh 路径)。
- 框架结构性 ~6.7 MB(Swift metadata / methodCache / Metal)+ SwiftUI 可分类节点 ~5 MB。
- **Maccy 自己的模型对象仅 ~0.15 MB**(624 `HistoryItemContent` + 185 `HistoryItem` + 185 `HistoryItemDecorator`)。135 MB 里 **~95% 是框架工作集 + 内容 blob + 视图图深度**。

## 4. 已完成 vs 待办(详见 [04](04-status-vs-master-plan.md))

**06-25 之后已落地并 CI 全绿**(意味着旧审计里这些"杠杆"已关闭,**别再做**):
- ✅ `sessionLog` → `PersistentIdentifier`(不再持有 `@Model`)—— M3
- ✅ 5 个"无界缓存"全部 → `NSCache`:ApplicationImageCache(128)、ignoredRegexps(64)、ColorImage(64+cost)、ThumbnailCache(两层 256/64MiB)—— M4/M5/M9
- ✅ `imageData` 已 lazy(BS-6)、HotKey + TIS 泄漏已修(M1/M2)、autoreleasepool(M6)、MemoryGovernance + VisibilityTracker + `releaseTransientImages`(C1/C2/C3)、安全守卫(F4)
- 06-26/27 另做了 preview 系统改造(可配置预览尺寸/文本上限、即时 snap+淡入、previewed item 与 lead 选择解耦)

**最大未做杠杆**:`VisibleWindowLoader`(`Storage+Background.swift:47-75`)**是死代码**——只有测试调用,从没接进 `History.load()`。接入它是首要内容 blob 杠杆(C5,6–13 MB)。

**重新升为关键前置**:`MallocStackLogging=1` 重抓(D1)。06-25 降级它,06-27 数据重新升回来。

## 5. 两个反直觉的坑

1. **SwiftData 没有单行 fault-out API**(`refresh` 是从 store 重填,不是清空)。所以光把 decorator 窗口化**可能释放不了底层 blob**——`mainContext` 的 `_KKMDBackingData` 行缓存可能仍持有它。可能必须走 **BS-8 独立 blob 存储**(把大内容移出 SwiftData,按 id 索引)。这把 F1 从"可选结构性优化"升为"可能强制项"。
2. **`mainContext.reset()` 是陷阱**——会在下次开窗时重新 fault 全表,直接退回当初 `load():218` 辛苦优化掉的冷开卡顿,并破坏增量 `consume` 路径。**别走这条捷径**去回收 blob。

## 6. 现实路径(详见 [05](05-action-plan.md))

去重后真实可榨 ~20–35 MB(注意 C5/C7/F1 共享同一个 17.5 MB blob 池,**不能相加**):

1. **接入 `VisibleWindowLoader`**(C5,load 全表→可见窗口):**6–13 MB**(主杠杆,L 工作量)
2. 延迟 `HistoryItem.contents` fault(C7,同池增量):3–8 MB(L)
3. AttributeGraph 视图树瘦身(U1):3–8 MB(M,需 D1 证实 AG 占比)
4. 接上 `releaseTransientImages(.previewHidden)`(C6,代码已存在零调用):1–2 MB(**免费**,S)
5. 并发卫生(12 个常驻 `Defaults.updates` Task + copy 合并):~1 MB(S–M)

→ 135 → ~100–115 MB;跑完 BS-2/BS-8 把 blob 池压到 ~3–5 MB 再多省 ~8–12 MB → ~85–95 MB。

## 7. 下一步建议

**先做 [06](06-gating-diagnostics.md) 的 MallocStackLogging 重抓**(零代码改动,macOS 上跑)。在那之前,上面每个 MB 数字都是推断,地板本身带 ±10 MB 不确定性。重抓能:
1. 把 41.7 MB `non-object` 盲区从"推断 ~66% 是 AG"变成**实测调用点归因**;
2. 分解"地板 vs 单项成本 vs 6h 滞留斜率"(现在只有 2 分钟和 6 小时两点,无空基线);
3. **定论 17.5 MB blob 到底能不能释放**——这决定"接入 VisibleWindowLoader 就够"还是"必须上 BS-8"。

重抓之后再按 [05](05-action-plan.md) 的顺序动代码。

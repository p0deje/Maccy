# 06-27 dump 完整分解

> 源文件:`docs/maccy.{footprint,heap,leaks,sample,vmmap.full,vmmap.summary}.txt`,抓取时间 2026-06-27 11:55:17,进程启动 05:52:28(**~6 小时运行**),macOS 26.5 (25F71),ARM64,Maccy 2.6.1 (60)。

## 1. 顶层物理内存

```
phys_footprint:         135.5M        ← 真实账单
phys_footprint (peak):  229.3M
Dirty      76.9M   +   Swapped/compressed  58.6M   ≈  135.5M
Writable regions: Total 310.0M  written 103.2M(33%)  resident 75.9M(24%)  swapped_out 54.7M(18%)
```

- **phys_footprint = dirty + swapped**(macOS 把压缩/换出的脏页也算进来,因为它们代表真实内存压力)。
- 实际驻留可写只有 75.9 MB;swapped 的 58.6 MB 是被压缩到磁盘的冷脏页。
- 对比 06-25(2 分钟):102 MB、swapped **0**、leaks 14 KB → **6 小时涨了 33 MB,且产生了 58.6 MB 压缩冷页 = 典型滞留累积**。

## 2. leaks:可忽略(19 KB)

```
410 leaks for 19,136 total leaked bytes   ← 全程仅 19 KB
```

构成(全是系统框架,非 Maccy):
- `NSXPCConnection`(`com.apple.linkd.autoShortcut` / AppIntents)—— 系统 XPC,~3 个 root cycle × ~4.7 KB
- `AXObserverCookie`(辅助功能)—— 系统
- `TSMInputSource` ~57 个 × 32 B —— 键盘布局(M2 已修主源;残余是基线 IME,不增长)
- `StorageSettingsPane.ViewModel` observation 环 —— 小

**结论:135 MB 不是泄漏。** 这是和 06-24(213 MB / leaks 821 KB)最本质的区别——那时候 HotKey + TIS 是真泄漏,现在泄漏已清,剩下的是真实占用 + 滞留。

## 3. heap:87 MB / 292,686 个分配

### 3.1 按字节数排序的 top 类

| 类 | 字节 | 数量 | 均值 | 归属 | 性质 |
|---|--:|--:|--:|---|---|
| **`non-object`** | **41.7 MB** | 109,261 | 382 B | **盲区**(无 MallocStackLogging) | ~66% AttributeGraph 图节点(见 [02](02-framework-floor.md)) |
| **`__DataStorage._bytes`** | **17.5 MB** | 556 | 31.5 KB | Foundation `Data` | **剪贴板内容 blob**(可干预) |
| Swift Metadata | 3.3 MB | 235 | — | libswiftCore | 结构性 |
| `Class.methodCache._buckets` | 2.1 MB | 2,723 | 771 B | libobjc | 结构性 |
| `MTLResourceList` | 1.3 MB | 26 | — | Metal | 结构性 |
| Closure context | 1.1 MB | 11,662 | 94 B | Swift | 异步/闭包 |
| `_DictionaryStorage<ObjectIdentifier, AnyTrackedValue>` | 892 KB | 872 | — | SwiftUI/AG | 视图图 |
| `CFString` | 575 KB | 10,596 | 55 B | CoreFoundation | |
| `_ContiguousArrayStorage<AccessibilityAttachmentStorage>` | 444 KB | 192 | — | SwiftUI | 视图图 |
| `CTRun` | 368 KB | 839 | 448 B | CoreText | 文字 shaping |
| `_CTNativeGlyphStorage._advanceWidths` | 358 KB | 69 | — | CoreText | |
| `Task stack` | 263 KB | 263 | — | 并发 | **263 个常驻/在飞 Task** |
| `SVGAttribute` / `SVGPathCommand` | ~270 KB | 2,711+835 | — | CoreSVG | SF Symbol |
| `icu::UnicodeSet` | 87 KB | 387 | — | libicucore | Unicode/regex |

### 3.2 Maccy 自身类(极小)

| 类 | 字节 | 数量 | 均值 |
|---|--:|--:|--:|
| `HistoryItemContent` | 49.9 KB | 624 | 80 B |
| `_KKMDBackingData<HistoryItemContent>` | 39.9 KB | 624 | 64 B |
| `HistoryItemDecorator` | 47.4 KB | 185 | 256 B |
| `HistoryItem` | 14.8 KB | 185 | 80 B |
| `_KKMDBackingData<HistoryItem>` | 11.8 KB | 185 | 64 B |
| `_SetStorage<ContentSignatureEntry>` | 58.7 KB | 178 | — |
| `_ContiguousArrayStorage<ContentSignatureEntry>` | 30.2 KB | 176 | — |
| Maccy 全部模型对象合计 | **~0.15 MB** | | |

**624 `HistoryItemContent` vs 185 `HistoryItem`** = 每项 ~3.4 个内容行(每条 copy 有 text/rtf/html/file-path 等多个 pasteboard 类型,见 `HistoryItem.swift:88` `@Relationship(deleteRule:.cascade)`),**不是孤儿**。**全部 624 个内容 + 624 个 `_KKMDBackingData` 都 fault 进 `mainContext` 且常驻**——这是 17.5 MB blob 的来源。

### 3.3 SwiftUI 视图图密度(AG 放大器)

heap 显示一个**极重的每行视图树**:`HelpView<...HStack<TupleView<...KeyboardShortcutView...>>>` 泛型节点 **1280 B × 101 个**,外加大量 `DynamicViewList<TypedElement>` 变体(5238 + 5026 + 1814 个)。这说明每行的 AttributeGraph 子图远超一个简单 List 行所需——这是 `non-object` 盲区里 AG 占大头的直接证据,也是 [05](05-action-plan.md) U1(视图树瘦身)的目标。

## 4. vmmap:区域与 malloc zone

### 4.1 malloc zone 表(精确)

| Zone | Virtual | Resident | Dirty | Swapped | Allocs | Allocated | 碎片 |
|---|--:|--:|--:|--:|--:|--:|--:|
| **DefaultMallocZone** | 133.4M | 53.3M | **52.6M** | **39.5M** | 215,319 | 60.0M | **32.1M (35%)** |
| DefaultPurgeableMallocZone | 20.0M | 320K | 320K | 2000K | 16 | 20.0M | 0% |
| **AttributeGraph** | 16.0M | 4176K | 4080K | 80K | **72,405** | 2495K | 1665K (41%) |
| AttributeGraph graph data | 2336K | 1136K | 1136K | 688K | 2,355 | 828K | 996K (55%) |
| QuartzCore | 1936K | 1360K | 1360K | 416K | 2,591 | 215K | 1561K (88%) |

- **DefaultMallocZone** 是主战场:60 MB 实际分配 + **32 MB 碎片(35%)** + 39.5 MB 换出。降碎片 = 减少分配数量/抖动(215K 个分配!)。
- **AttributeGraph zone:72,405 个分配** —— 这就是 heap `non-object` 109K 里的 ~66% 来源(72,405/109,261)。AG 图节点是无类标签的 C malloc,落到 `non-object`。

### 4.2 非堆区域(footprint 贡献)

| 区域 | Virtual | Resident | Dirty | 性质 |
|---|--:|--:|--:|---|
| `mapped file` | 617.6M | 46.1M | 0 | **clean 共享,不计入 footprint** |
| `__TEXT` | 1.2G | 473.2M | 0 | clean(首次触碰 COW 才计入,见 [02](02-framework-floor.md)) |
| `__AUTH_CONST` | 88.6M | 52.2M | 64K | 框架常量 |
| `MALLOC_SMALL` | 125.1M | 52.0M | 51.9M | 主堆(35% 碎片) |
| `ImageIO` | 6.2M | 5.8M | 0 | 0 dirty,全 swapped——图片解码缓存 |
| `IOSurface` | 3.1M | 2.9M | 2.8M | 图层 backing(窗口缓冲) |
| `CoreAnimation` | 2.5M | 1.8M | 1.8M | |
| `CG raster data` | 1.3M | 1.3M | 1.3M | 光栅图 |

**注意**:mapped file 617M / `__TEXT` 1.2G 的 virtual 很吓人,但它们 resident 且 clean、dirty=0,**不计入 phys_footprint**。真正吃 footprint 的是 `MALLOC_SMALL`(dirty 52M + swapped 34M)和框架可写状态。

## 5. sample(CPU)

CPU sample 中 Maccy 自身帧仅 3 行(1051 行里),与 06-24"97% 空闲"一致——**进程基本空闲,footprint 却随时间涨 = 滞留,不是 churn**。

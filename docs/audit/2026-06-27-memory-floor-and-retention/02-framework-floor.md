# 不可压缩地板 ≈ 62 MB

> 本文论证:即便历史为空、窗口最小,Maccy 的 `phys_footprint` 也降不到 ~62 MB 以下。这直接判了"50 MB 数学上不可能"。

## 1. 地板构成(实测分解)

| 组件 | MB | 可减 | 依据 |
|---|--:|---|---|
| **框架 `__TEXT`(首次触碰 COW)** | **~45** | 否 | AppKit+SwiftUI+SwiftData+SwiftUICore+AttributeGraph+CoreText+CoreSVG+SFSymbols+Metal/AGXMetalG17G+CoreUI+SkyLight 等。vmmap `__TEXT` 1.2G virtual / **473M resident**;ReadOnly libs `resident=491.9M(27%)`。首次使用时 dyld shared cache 页 COW 进程私有页,**计入 phys_footprint 且无法 evict** |
| **框架可写状态** | **~10** | 否 | `__DATA` 1785K + `__DATA_DIRTY` 1940K + `__AUTH` 687K + `__AUTH_CONST` 64K + shared memory 5248K + unused-but-dirty shlib 174K(vmmap.summary 实测) |
| **AttributeGraph 最小图(一个窗口)** | **~5** | 部分 | AG zone 4.1M resident / 72K allocs + graph-data 1.1M dirty。一个 SwiftUI 窗口的最小 AG 图 |
| **libmalloc + zone 元数据 + page table + Stack + IOAccelerator 非图基线** | **~2** | 否 | MALLOC metadata 880K + page table 769K + Stack 192K + IOAccelerator 112K 等 |
| **Swift runtime metadata / ObjC method-cache 预热** | **~1** | 否 | Swift Metadata 3.3M(冷启更低,~1M)、methodCache 2.1M,加载后常驻 |
| **合计** | **~62 MB** | | 任何剪贴板内容**之前** |

## 2. 为什么 `__TEXT` 计入 footprint 且不可减(关键误解澄清)

很多人以为"框架代码是共享的、clean 的,不计入我的内存"。**半对**:

- dyld shared cache 把系统框架映射成共享只读段,虚拟地址很大(1.2G),**初始 resident 但 dirty=0**,确实不立即计入。
- **但**首次执行/读取时触发 **copy-on-write**:页变进程私有 dirty 页,**计入 `phys_footprint`**。
- macOS **不提供**把 SwiftUI+SwiftData+AppKit 应用跑成"无窗口/headless"的官方路径。窗口一开,AG/CoreText/CoreAnimation 全线 COW 触碰 → ~45 MB 框架 TEXT 变成进程私有。
- 这 45 MB **无法 evict**(不是 purgeable,不是 clean cache)——除非进程退出。

→ 这就是地板的硬核:你**无法把框架代码挪出 footprint**。

## 3. 50 MB 为什么数学上不可能

```
目标 50 MB  <  地板 ~62 MB        ← 在地板之下
缺口 = 62 - 50 = 12 MB(还要从不可压缩地板里抠,做不到)
```

即便把 135 MB 里所有可干预项(内容 blob + AG 图 + 缓存)全压到 0,也到不了 50 MB——因为 62 MB 地板在内容之前就存在了。

唯一能逼近 50 MB 的场景是**窗口关闭 / 仅菜单栏模式**(AG 图 + IOSurface 窗口缓冲会消失),但即便那样 50 MB 也不保证,且失去了产品形态。

## 4. 80 MB 的预算压力

```
地板 62 MB  +  内容 blob(可见项 ~3-5 MB) + AG 图超出最小部分 + 缓存 + 并发  =  80 MB
预算余量 = 80 - 62 = 18 MB,要装下:全部剪贴板内容 + 完整 AG 图 + 所有缓存
```

18 MB 是**很紧的预算**:
- 小历史 + 无图 + 短会话:装得下。
- 185 项 + RTF/图 payload + 6h 运行:装不下(当前就是 135 MB),必须 BS-8 把 blob 移出 SwiftData。

所以 80 MB 是"小历史 + 短会话 + 完整 roadmap"的乐观上限,**不是稳定稳态目标**。

## 5. 41.7 MB `non-object` 盲区的归因(地板分析 agent 推断)

> ⚠️ **推断,非实测**——没开 MallocStackLogging。见 [06](06-gating-diagnostics.md)。

按 zone 相关性 + heap 类计数交叉:

| 推断归属 | ~MB | 依据 |
|---|--:|---|
| **AttributeGraph 视图图节点体**(无类标签 C malloc) | **25–30** | AG zone **72,405 个分配** = `non-object` 109K 的 **66%**;4.1M resident。SwiftUI 每行重视图树(`HelpView<...>` 1280B×101)直接放大 |
| CoreText shaping 缓存(`CTRun`/`CTLine`/glyph) | 3–5 | heap CTRun 839/375KB + glyph storage;随文字渲染增长 |
| CoreSVG / SF Symbol 缓存 | 1–2 | SVGAttribute 1876、SVGPathCommand 835;CoreGlyphs.car 映射 6.1M resident |
| Metal / GPU 资源描述符 | ~2 | MTLResourceList 1.3M + AGXMetalG17G heap |
| Swift 闭包 / 异步 continuation 帧 | ~1 | Closure context 1.1M + 263 Task stack |

**~25–30 MB 是 AG 图节点体**,随**已实现(realized)的视图节点数**线性增长。这意味着**视图树瘦身(U1)能减一部分**(理论上 30–45%),但有一个 **~17–20 MB 的 AG 不可减核**(一个活 SwiftUI+AG 窗口的最小图)。

→ 这也解释了为什么"接入 VisibleWindowLoader"能减 AG:可见窗口缩小 → 已实现视图节点数减少 → AG 图节点体减少。但 LazyVStack 已经只构建可见行的 view body,所以 AG 的主要削减来自**每行视图树复杂度**(U1)而非行数(C5 对 AG 的贡献比预想小)。

## 6. 结论

- **地板 ~62 MB 是硬的**(45 框架 TEXT COW + 10 框架可写 + 5 AG 最小 + 2 malloc/io)。±~5 MB 不确定性,需 [06](06-gating-diagnostics.md) 的空历史/窗口关闭基线确认。
- **50 MB 不可达**(地板之下)。
- **80 MB 需要把 62 之外压到 18 MB 以内**——紧,且依赖完整 roadmap。
- **41.7 MB 盲区主要是 AG 视图图 + CoreText/SVG 缓存**,可减 ~30–45%,但留 ~17–20 MB AG 不可减核。

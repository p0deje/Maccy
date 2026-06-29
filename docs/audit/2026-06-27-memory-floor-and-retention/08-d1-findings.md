# D1 实测发现(2026-06-27 22:40 捕获)— 推翻部分 06-27 推断

> 用户在 macOS 跑了 capture-d1.sh(`captures/d1-20260627-224003/`),带 MallocStackLogging=1。
> **这是第一份实测 heap 归因数据**,推翻了 06-27 的两个关键推断。MSL 使 footprint 膨胀
> (~30-40 MB 开销),故 footprint 数值当上限看;**heap 的类型/zone 归因是可靠的**(heap
> 用了 MSL 回溯,派生 815-826 个类型名)。
>
> 已知捕获缺陷:`malloc_history` 调用错误(`--eventsByStack` 非合法 mode → 输出 1.9 KB
> 用法说明)。所以无 per-stack call-tree;但 heap 的 zone/library 归因已足够定性。脚本已
> 修正为 `-callTree`(见 capture-d1.sh)。Group E 滚动抓取受限于"按 Enter 时弹窗失焦关闭",
> 数据不完整但够用。

## 1. Footprint(MSL 膨胀,当上限;相对差可靠)

| 组 | 状态 | phys_footprint(MSL) | 估算真实值(MSL−~30-40MB) |
|---|---|---:|---:|
| A | 刚启动、弹窗关闭 | 78 MB | ~40-48 MB |
| B | 弹窗打开、~20 项 | 92 MB | ~55-62 MB |
| Dclosed | 用后关闭 | 89 MB | ~52-59 MB |
| E-top/E-50 | 滚动全历史 | 163-166 MB | ~120-130 MB(≈ 6h 135 MB 稳态) |

- A→B:+14 MB(MSL)/ heap +7.8 MB —— 打开弹窗 + 可见行的 AG/SwiftUI 簿记。
- B→Dclosed:−3 MB —— 关窗只回收窗口缓冲/IOSurface;AG 节点 + fault 的 blob 留下(+11 MB 净滞留 vs 地板)。
- E 达到 ~120-130 MB 真实 = 6h 稳态,证实"滚全历史即达稳态"。

## 2. Heap 归因(B,弹窗打开,46.5 MB / 168K 节点)—— **无单一大户**

最大单项 ~1 MB(AG zone),其余全 <0.8 MB。**46 MB 是 168K 个小分配的长尾**,非几个大桶:

| 节点类型 | 数 | 字节 | 说明 |
|---|---:|---:|---|
| non-object in zone AttributeGraph | 26,302 | ~0.98 MB | **AG-named zone 仅 ~1 MB**(非 06-27 推断的 25-30 MB) |
| Closure context | 7,694 | 0.75 MB | Swift 闭包 |
| CFString | 5,905 | 0.42 MB | |
| SwiftUI.HelpStyleConfiguration (TypedElement×2) | ~4,800 | ~0.46 MB | **`.help()` 的 AG 节点**——U1 的目标(此为 pre-U1 安装版) |
| Swift._SetStorage / _DictionaryStorage(各种) | — | ~1 MB | Swift 运行时簿记 |
| AGSubgraph / AGSubgraphCreate2 | ~1,700 | ~0.15 MB | AG 图节点 |
| libicucore(unicode/text shaping) | 1,789 | 0.29 MB | CoreText 相关 |
| MTLPipelineDataCache(Metal) | 1,373 | 0.09 MB | Metal 管线缓存 |
| _ModelMetadata / KnownKeysDictionary(SwiftData) | ~1,700 | ~0.15 MB | SwiftData 元数据 |
| __DataStorage | 610 | **~48 KB** | **非 17.5 MB**——blob 仅在图片多的大历史才大 |

**Leaks:292 leaks / 19 KB**(全是 `com.apple.linkd.autoShortcut` XPC/dispatch 系统循环)——
非泄漏,06-27 结论复核成立。

## 3. 推翻的 06-27 推断

| 06-27 推断 | D1 实测 | 影响 |
|---|---|---|
| non-object 41.7 MB,~66% 是 AG | **AG-named zone 仅 ~1 MB**;non-object 是跨 AG/SwiftUI/Swift-runtime/Metal/CoreText 的**长尾** | **U1 式视图瘦身无法有效削减**(U1 本身只省 ~0.2-0.5 MB HelpStyleConfiguration) |
| __DataStorage 17.5 MB(内容 blob)是主滞留 | 此捕获 **__DataStorage ~48 KB**;17.5 MB 仅图片多的大历史才有 | **F1 blob 存储仅对图片重度用户有用**(~17.5 MB),文本历史≈0 收益 |
| 有可榨的"大户" | **无单一大户**;46 MB 是 168K 小分配长尾 | 没有可集中回收的桶 |

## 4. 修正后的真实分解(窗口打开、真实历史)

```
~120-130 MB(6h/D1-E 稳态)
 = ~45-60 MB  框架 working-set(AppKit+SwiftUI+SwiftData+AG+CoreText+Metal 脏页)  [不可回收]
 + ~46 MB     heap 长尾(SwiftUI/AG/Swift-runtime/SwiftData 簿记,168K 小节点)    [几乎不可回收,非大户]
 + ~17.5 MB   SwiftData 内容 blob                                                 [仅图片重度用户;F1 可回收]
 + ~5-10 MB   MSL/测量/其他
```

**菜单栏形态(弹窗关闭):~40-60 MB 真实** —— 很便宜。

## 5. 结论:100 MB 目标对内存回收不可达

- **窗口打开 + 真实历史 ≈ 110-130 MB 是 AppKit+SwiftUI+SwiftData 剪贴板管理器的框架成本**,
  非 Maccy 代码可回收。app 侧可回收 = U1(已做,~0.2 MB)+ F1(仅图片重度,~17.5 MB)。
- 文本用户:无有效杠杆。图片重度用户:F1 省 ~17.5 MB(135→117 MB),仍未到 100 MB。
- **C5(VisibleWindowLoader)确证无内存价值**:AG 窗口化收益 ~0(LazyVStack 已回收),
  blob 仍被 pin;且损 UX(搜索漏项)。**正式放弃 C5 作内存杠杆**。
- **F1 降级为"仅图片重度用户可选"**,非强制。

## 6. 建议方向

1. **接受 ~110-130 MB(窗口开)/ ~40-60 MB(菜单栏)为框架现实**。100 MB 不是内存优化的目标。
2. 若用户图片重度 → **F1 blob 存储**是唯一结构内存杠杆(~17.5 MB,UX 安全)。
3. 否则**转向 UX/性能路线图**(搜索 off-main 等),那里有真实价值;内存侧已榨干(U1 done)。
4. (可选)用修正的 `-callTree` 重抓可得 per-stack call-tree,但 heap 已定性地结论,call-tree
   只会细化"哪个 SwiftUI view 分配最多",不改长尾结论。

## 7. 用户决定(2026-06-27)

- **走 A:转向 UX/性能路线图**,持续做未完成的性能优化(冷开 `load()` 延迟是首要响应性目标)。
- **B(F1 blob 存储)记录待后做** —— 用户图片重度场景下值得(~17.5 MB,UX 安全),非现在。
  内存侧 code 工作到此为止;F1 是唯一留作"之后"的结构内存项。


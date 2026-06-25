# 实测内存画像 — Maccy(2026-06-24)

> ⚠️ **2026-06-25 更正(以本文为准的更新见下)**:用户用**短启动(2 分钟)**重抓了一份,实测 **phys_footprint ~102 MB**(213MB 是 2 天积累)。**"36.6MB 盲区"主要是 HotKey 泄漏(已修,bs6.13)+ ~20MB 基线框架开销(不可降)**——不是神秘泄漏。**D1(MallocStackLogging 重抓)不再关键**,内存目标在启动态基本已达。完整对照与恢复指南:`docs/audit/2026-06-25-performance-analysis/15-progress-and-resume.md`。
>
> 下方 §1–7 是 2026-06-24 的原始分析(213MB 长运行画像),保留作历史;其"盲区阻塞 <100MB、需 D1"的结论**已被 2026-06-25 复核推翻**。

> 本文档记录 **2026-06-24** 用 `vmmap` / `heap` / `leaks` / `sample` 实测的 Maccy 内存构成,用以校准 `docs/audit/2026-06-14/05-memory-caching.md`(理论 worst-case)与 `docs/audit/2026-06-14/roadmap/step-6-memory.md`(BS-6 计划)的假设。**结论先行**:BS-3 已修掉 BS-6 当初针对的三条 critical 巨型图像占用;实测 213MB 稳态主要由 **HotKey 泄漏 + 无法归因的盲区 + 框架/运行时开销** 构成,**不是** BS-6 目标的图像/缓存。本画像驱动 `01-memory-plan.md` 新增 `bs6.13`–`bs6.16`。

## 0. 抓取条件与方法

- **进程**:Maccy 2.6.1 (60),pid 92601,ARM64,macOS 26.5 (25F71)。
- **启动 → 抓取**:2026-06-22 21:56 → 2026-06-24 22:18,**运行 ~2 天**(长寿命稳态,非冷启)。
- **样本**(均在 `docs/`):
  - `maccy.footprint.txt`(类别汇总,3KB)
  - `maccy.vmmap.summary.txt` + `maccy.vmmap.full.txt`(区域/zone,8.8KB / 1.3MB)
  - `maccy.heap.txt`(按类聚合,1.3MB)
  - `maccy.leaks.txt`(泄漏图,1.35MB)
  - `maccy.sample.txt` + 根目录 `Maccy.sample.txt`(CPU 采样,208KB / 2.5MB,20:30 与 22:18 两个时刻)
- **方法**:静态分析上述 dump(本机无 Xcode/`malloc_history`,见 `CLAUDE.md`)。`heap` 因 `MallocStackLogging` 关闭,有 38.4MB "non-object" 不可归因 —— 见 §6 盲区。

## 1. 顶层数字

| 指标 | 值 | 来源 |
|---|---|---|
| **phys_footprint(稳态)** | **213.3 MB** | vmmap header / footprint.txt |
| phys_footprint **peak** | **415.1 MB** | 同上 |
| DIRTY | 61.0 MB | vmmap SUMMARY |
| **SWAPPED(压缩冷页)** | **152.4 MB** | vmmap SUMMARY |
| RESIDENT | 683.2 MB | vmmap SUMMARY(含 COW 共享框架 text) |
| VIRTUAL | 3.2 GB | vmmap SUMMARY(绝大部分是 dyld 共享缓存 / 字体 / SF Symbols,**0 dirty,不可降**) |

**关键恒等**:`phys_footprint(213MB) ≈ DIRTY(61MB) + SWAPPED(152MB)`。即 **~152MB 是被压缩器压扁的"冷驻留对象"** —— 强烈信号:App 长期持有大量不活跃对象图,系统不得不压缩它们。这是"驻留型"足迹特征(见 §5 CPU 印证),不是高频 churn。

## 2. heap 分解(malloc 堆,~130MB;可归因 88.9MB + 盲区 38.4MB)

| 类别 | 大小 | 实例 | 备注 |
|---|---|---|---|
| **`CarbonKeyboardShortcuts.HotKey.carbonHotKey`** | **43.5 MB** | **783** | **泄漏,非工作集**。仅 1 个 `KeyboardShortcuts.HotKey` wrapper 却有 783 个 Carbon `EventHotKeyRef` 存活 → 每次重新注册未释放上一个。**占可归因堆 49%、全部 malloc 节点 34.7%**。 |
| **non-object(不可归因)** | **36.6 MB** | 176646 | MallocStackLogging 关闭,heap 无法映射类型/回溯。盲区,需重抓。 |
| Swift Metadata | 4.2 MB | 300 | 泛型 SwiftUI 类型元数据,固定开销 |
| MTLResourceList | 2.7 MB | 58 | Metal/GPU 资源描述符,驱动开销 |
| `Class.methodCache._buckets` | 2.1 MB | 2906 | objc 方法缓存,随类数增长,固定 |
| `_DictionaryStorage<ObjectIdentifier, SwiftUI.AnyTrackedValue>` | 2.07 MB | 2180 | SwiftUI/AG 观察追踪字典,**随同时存活的视图/装饰器数增长** |
| Closure context | 1.76 MB | 18778 | Swift 闭包捕获盒,弥散 |
| CoreText(`CTRun`+`_advanceWidths`+`_origins`+`_CTNativeGlyphStorage`) | ~1.7 MB | — | 文本布局缓存,绑定窗口动画重排风暴(`titlePreviewLimit=1000` + `.middle`,见 MEMORY.md) |
| 其余(CFString / 各类 SwiftUI 存储 / TSMInputSource / NSKeyValueDependency / SVGAttribute …) | 各 < 1MB | — | 弥散的系统/框架开销 |
| **`NSImage` + `CGImage` + image reps 合计** | **~182 KB** | — | **图像在快照里几乎为零**(NSImage 仅 131 实例 @160B=20KB) |
| **SwiftData + CoreData 合计** | **< 0.3 MB** | — | `_ModelMetadata` 140KB 最大;持久层**不是**问题 |
| `HistoryItemContent`(@Model shell) | 67 KB | 853 | 仅对象壳 80B/个;**载荷字节不在堆里** |
| `HistoryItemDecorator` | 60 KB | 242 | **仅 ~242 个装饰器**(小历史),非 999 |

> **堆口径注意**:heap 只数 malloc-zone 节点(131.6MB),不含 mmap 文件页、SwiftData SQLite、GPU 纹理。213MB phys − 130MB malloc ≈ 80MB 是非堆(CoreAnimation backing / IOSurface / ImageIO / 框架 DATA / 栈)。

## 3. vmmap 分解(DefaultMallocZone 是唯一有意义杠杆)

| zone / 区域 | dirty+swap | 备注 |
|---|---|---|
| **`DefaultMallocZone`** | **45.5M dirty + 112.2M swapped ≈ 158M** | 382327 分配,104.9M 已分配,**52.8M 碎片(34%)**。Maccy 自有对象图 + HotKey 泄漏 + 框架驻留都在此。**112M SWAPPED = 实写入后被压缩驱逐的真实足迹**。 |
| `MALLOC_SMALL`(聚合) | ~125M dirty+swap(46.7M dirty) | 499 区域,大量 2-4MB slab —— **每条目对象图持久驻留 + 高碎片**的典型形状(非单个巨块) |
| `MALLOC_LARGE`(聚合) | 36.0M(全 swapped,0 dirty) | 10 个大块,全是冷的大缓冲(富文本解析/图像解码/批量 fetch),用完即驱逐 |
| `AttributeGraph` zone | 4.4M dirty + 2.6M swapped;149624 分配 | SwiftUI 视图图。对一个剪贴板列表偏大 → 列表视图图被密集保留/重建 |
| mapped file(Emoji / SF Symbols / 系统库 __TEXT 等) | 数百 MB virtual | **0 dirty,COW 共享,不可降、不应追** |
| `Memory Tag 22` | 64M virt / 48K phys | 预留未用区域,虚拟占位,非足迹问题 |

> WebKit/WebCore(~58MB resident text)+ JavaScriptCore(~27MB)+ WebKit(~22MB)被映射进剪贴板 App。**Maccy 代码无任何 `WKWebView`/`import WebKit`**(仅一个 pasteboard UTI 字符串 `customWebKitPasteboardData` + 注释)→ WebKit 是**被其它框架传递性拉入**(很可能 AppKit 的 `NSAttributedString(html:)` 路径)。resident text 是 COW 共享,phys_footprint 影响有限,**剪除 ROI 低且风险高**,仅作记录。

## 4. leaks(总计 802 KB ≈ 足迹的 0.4% — 对稳态目标**不值得**专项修)

| 根 | 字节 | 性质 |
|---|---|---|
| `TSMInputSource`(×18417) | 576 KB | CoreText/IME 框架静态缓存,App 代码无关,**误报噪声** |
| **`HistoryItem` ↔ `HistoryItemDecorator` 观察环**(×14) | 201 KB | **唯一可归因于 Maccy 的环**:HistoryItem → `_$observationRegistrar.extent` → `ObservationRegistrar.Extent` → 闭包 → decorator → `__strong _item` → 回 HistoryItem。decorator **强持有** `@Model item` 且观察它 → 成环 |
| `NSXPCConnection`(×3,`com.apple.linkd.autoShortcut`) | 14 KB | App Intents/Shortcuts 框架侧,非 Maccy 发起 |
| `Logger.Storage`(×1 + 环内) | 8 KB | os.Logger 存储 |

> 0 个泄漏提及 NSImage/ColorImage/CGImage/DispatchSource/regex/pasteboard/sqlite → **图像/OCR/正则/剪贴板子系统对泄漏报告零贡献**(分配后正确释放)。peak(415M)−current(213M)= 200M 是**已释放的瞬态**(图像解码/Vision/pasteboard 快照),非泄漏。

## 5. CPU 采样(97% 空闲)—— 印证"驻留型"足迹

- 主线程 ~85% 阻塞在 `mach_msg2_trap`(runloop 等事件)。**进程 ~97% 空闲**。
- 唯一周期性实工作:`Clipboard.checkForChangesInPasteboard` 定时器 → `BackgroundClipboardIngestor.ingest` → **`findDuplicate(of:)`(187 采样,最热叶)**。每次复制都扫一遍现有历史的签名/内容工作集 → 把整表工作集反复 touch、常驻。这正是 BS-4 `SignatureIndex`(O(hits))要消除的全表扫描。
- **足迹 1.75h 内从 213→313MB 涨 100MB,CPU 全程空闲** → 内存被**持有**而非反复分配(churn 会有 CPU,这里没有)。**把内存工作当"驻留/工作集"问题处理,不是"churn"问题。**
- 主线程无图像解码/Vision/OCR 热路径(渲染链风暴窗口已关);vImageConverter 仅 CA commit 内零星 1 采样叶。

## 6. 与 `05` 审计 / BS-6 假设的对账

`05`(2026-06-14)与 `step-6-memory.md` 基于理论 worst-case(`size=999`、20% 图、retina、全浏览+预览)估算 **~12.8 GiB**。**BS-3 已落地后,三条 critical 的巨型占用已消失**:

| `05`/BS-6 假设 | 理论值 | 实测状态(2026-06-24) |
|---|---|---|
| `img-decoded-nsimage-retained`(critical) | 9.6 GiB | **已修(BS-3)**:`decodedImage` 字段已删,解码走 off-main `imageProcessor` |
| `img-preview-fullscreen-bitmap`(critical) | 2.6 GiB | **已修(BS-3)**:`previewImageSize` 封顶 800²(非全屏 visibleFrame) |
| `img-fullres-dup-storage`(critical) | 600 MiB | **部分修**:`imageData` 改懒加载 `imageDataCache`,但**一旦加载仍常驻**(BS-6 bs6.4 要改为按需重取/可 nil) |
| `all-realized-decorators`(critical) | 全 999 装饰 | 实测仅 **242 装饰器**(小历史);大历史场景仍是结构风险 → 条件性 track |
| 图像+缓存合计 | GB 级 | **实测 ~182 KB** |

**因此 BS-6 当初针对的"图像巨型占用"在实测快照里几乎不存在**。实测 213MB 的真实构成是:

1. **HotKey 泄漏 43.5MB**(§2)— 完全不在 BS-6。
2. **盲区 36.6MB**(§2)— 需重抓。
3. **框架/运行时 ~50MB**(SwiftUI 观察字典/闭包/CoreText/Metal/方法缓存/Swift 元数据)— 大部分结构性。
4. **碎片 ~28MB**(DefaultMallocZone 34%)。
5. **非堆 ~80MB**(CoreAnimation/IOSurface/ImageIO/框架 DATA/栈)。

## 7. 真实杠杆排序(驱动 `01-memory-plan.md`)

| 排序 | 杠杆 | 预期稳态收益 | 对应计划步 |
|---|---|---|---|
| 1 | **修 HotKey 泄漏**(Popup enable/disable 循环,`Popup.swift:84/123`) | **~40MB** | `bs6.13` |
| 2 | **重抓盲区并削减 36.6MB non-object** | 取决于归因,可达 **10–30MB** | `bs6.0` / `bs6.15` |
| 3 | **BS-6 核心**(可视区/告警回收、缓存封顶、`sessionLog` 迁移、`autoreleasepool`) | 稳态 ~5–15MB + **压峰值 415→<250MB** | `bs6.1`–`bs6.12` + `bs6.14` |
| 4 | AttributeGraph/CoreText/视图图削减 | ~5–10MB | `bs6.16` |
| 5 | 观察环修正(正确性 + 释放模型图) | ~0.2MB 直接 + 间接 | `bs6.14` |

**诚实预期**:bs6.13(HotKey)→ 稳态 ~150–170MB;+ BS-6 核心 → ~130–150MB 且峰值显著降;**硬性 <100MB 稳态依赖于盲区(36.6MB)归因结果** —— 必须先 `bs6.0` 重抓。

---

*所有数字直接取自 `docs/maccy.*.txt` 与根 `Maccy.sample.txt`;file:line 引用均为当前 HEAD(`3aa2501`)。*

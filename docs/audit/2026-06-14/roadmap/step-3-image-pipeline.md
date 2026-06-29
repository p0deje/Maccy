> 📌 设计意图原始档案(2026-06-14,冻结)。完成度以 docs/audit/2026-06-28-roadmap-bs5-bs8-gap-audit/00-summary.md 为准。
> 完成: BS-3(审计 2026-06-28:已完成,IMG-023 stopgap 已落地)

# BS-3 — 图片管线(ImageIO 降采样、后台解码、缩略图缓存)

> **依赖**:BS-1(协议 `ImageProcessing` + `PassthroughImageProcessor`)、BS-2(`ClipboardIngestor` 已在后台 actor 中执行图片解码/缩略图相关调用)。**编译边界**:小步骤 3.5 改 `HistoryItemDecorator` 的位图来源会临时破坏既有视图接线,**3.8 恢复**;完成全部后 `xcodebuild build` 通过且测试全绿。

**目标**:用 ImageIO `CGImageSourceCreateThumbnailAtIndex` 替换 `NSImage.draw` 全量重绘的降采样;实现 BS-1 协议的真实 `actor ImageProcessor`(后台解码/缩略图/预览),替换 `PassthroughImageProcessor`;预览目标尺寸封顶;缩略图双层缓存(内存 `NSCache` + 磁盘 LRU,键=内容指纹);`HistoryItemDecorator` 不再用 `Task { @MainActor }` 包裹位图生成,改为后台 actor 解码 + 回主线程赋值。
**依据**:`02-IMG-001`(主线程全量解码)、`02-IMG-002`(`draw` 重绘无降采样)、`02-IMG-003`(预览整屏)、`02-IMG-004`(`Task { @MainActor }` 无后台)、`02-IMG-006`(伪 async 阻塞主线程)、`02-IMG-007`(`.high` Lanczos 热路径)、`02-IMG-012`(无 ingest 降采样/无磁盘缓存)、`02-IMG-022`(吞错)、`02-IMG-023`(忽略取消)、`02-IMG-037`(`recache` 半清理)、`02-IMG-038`(HEIC 解码成本)。
**编译安全性**:核心变更是图片解码路径的端到端替换——新模块(3.1–3.4)为纯加法可单独编译;3.5–3.7 改 `HistoryItemDecorator`/视图接线,末尾 3.8 收敛编译。**边界**:`decodedImage`/`imageData` 的"可视区回收/去双份"属 **BS-6**,本步**不处理**;本步只做"解码/降采样/缓存"管线本身。

## 就绪核查(2026-06-15,执行前)

经 4-agent 只读核查(workflow `wq524zry8`)对照当前源码:行号引用**零漂移**(HistoryItemDecorator/NSImage+Resized/PreviewItemView/ListItemView 全部精确命中);ImageIO/actor API 与 sosumi Apple 文档一致(`CGImageSourceCreateThumbnailAtIndex` + 四个 option key、`CGImageSourceCreateWithData`、`NSImage(cgImage:size:)`、`NSCache` 线程安全但非 `Sendable`、`Task.checkCancellation`/`isCancelled` 均确认)。**4 处必须在执行前纳入的更正**(均已对照代码确认):

1. **3.5 用结构化 `Task`,不是 `Task.detached`**(doc 原文写 detached)。detached 不随 `invalidate()`/`cleanupImages()` 取消生成任务,直接破坏 IMG-023 的取消语义 → 解引用悬挂位图。改为 `Task { [weak self] in let img = await self?.imageProcessor.thumbnail(...); await MainActor.run { self?.thumbnailImage = img } }`,actor 方法内的 `Task.checkCancellation` 才能生效。
2. **3.2 `ThumbnailCache` 用 `actor`,不是 `final class @unchecked Sendable`**。`NSCache` 自身的线程安全只覆盖其字典,不覆盖磁盘 LRU 写入;并发 evict+write 会损坏磁盘存储。actor 同时提供 Sendability 与磁盘互斥(对齐 BS-2 `@ModelActor` 先例)。且**缓存键必须是 `(MaccyFingerprint, maxPixelSize)`**,不能只用指纹——`thumbnailImageSize`(:14)依赖用户可配置的 `Defaults[.imageMaxHeight]`(改时 `History.swift:191-196` 触发 `cleanupImages()`+重建),纯指纹键会返回错误尺寸的陈旧缩略图。
3. **新增 3.0(3.4 之前):创建 6 个图片 fixture**。`MaccyTests/Fixtures/` 现仅 `guy.jpeg`;`png_1x1`/`jpeg_small`/`screenshot_1440x900`/`photo_12mp`/`corrupt_truncated` 全缺(可在 Linux 用 Pillow 合成),`heic` 无法在 Linux 编码(需 libheif/libx265)→ 预制字节提交或测试 `XCTSkip` 兜底。每个 fixture 需在 `project.pbxproj` 四处登记(无 blue-folder 通配)。
4. **3.4/3.5 补 `HistoryDecoratorTests` 同步/异步适配**(doc 3.4 测试清单遗漏)。`HistoryDecoratorTests.swift:65,75,127` 同步调 `sizeImages()` 后立即断言 `previewImage!`/`thumbnailImage!`;生成改异步后会竞态。需在测试注入同步 `ImageProcessing` double 或改 await。

**额外发现**:`HistoryItemDecorator` **无** `imageProcessor` 字段——3.5 是**新增注入点**(stored property + init 参数 + 所有构造点),非参数替换。构造点:`History.swift:204,239,309,361,368`、`HistoryDecoratorTests.swift:184,206,225,248`、`SearchTests.swift:18-20,79-81,164-166`、`IngestErrorPropagationTests.swift:26`。`kCGImageSourceShouldCacheImmediately` 文档仅明确覆盖 `CreateImageAtIndex`,非 `CreateThumbnailAtIndex`——离线解码保证靠"调用在 actor 上"满足,加注释勿依赖该 flag。`NSImage` 跨 actor 回主线程 `recache()` 是潜在 Swift 6 隐患(留 BS-7)。

**执行节奏**:3.0/3.1/3.2/3.3/3.4 为加法步骤(各自提交+push,CI 绿);3.6→3.5→3.7→3.8 为编译破坏批次(本地逐小步提交,**仅 3.8 恢复编译、build+test 绿后整批 push**);3.9 记录闸门证据。

## 落地记录(2026-06-15)— BS-3 完成

**状态:CI 全绿**(run `27580858963`,head `16bd334`:SwiftLint `--strict`、clean build、`MaccyTests`、`MaccyUITests`、日志扫描均过)。BS-3 的离线主线程图片管线已落地:复制/预览/缩略图的解码与降采样全部经 `actor ImageProcessor` 在后台执行,主线程只接收已就绪的小位图。

**已落地小步骤(commit + 证据)**:
- **3.1** `ImageDownsampler`(纯 ImageIO 降采样,含 0-image 守卫避免 ImageIO 控制台噪声)— `3a5241a` / `c791926`(补 `import ImageIO`)/ `c067d77`(count-guard)。
- **3.2** `actor ThumbnailCache`(NSCache + 磁盘 LRU PNG,**复合键 (fingerprint, maxPixelSize)**;actor 化以串行化磁盘写入)— `766dfc1` / `9e74afc`(SwiftLint DiskEntry/3-char id)/ `32c76e4`(测试 `@testable import Maccy`)。
- **3.3** `actor ImageProcessor: ImageProcessing`(结构化取消检查点;指纹复用 `MaccyTextProcessor.fingerprint`)— `8f006d6` / `0c68cab`(**补 `: ImageProcessing` 协议一致性**——3.3 报告误称已一致、实际漏标,作为存在量 `any ImageProcessing` 使用时才暴露)。
- **3.6 → 3.5 → 3.7 → 3.8**(编译破坏批次,本地逐小步提交、`1672b57` 恢复编译后整批 push):`HistoryItemDecorator` 注入共享 `defaultImageProcessor`、删除 `decodedImage`、`ensure*` 改**结构化 `Task { @MainActor [weak self] in await processor.thumbnail(...) }`**(非 `Task.detached`——保结构化取消 IMG-023)、preview 封顶 ≤1600²、`asyncGetPreviewImage` 失败 `logger.error`(gated `!isInvalidated`)、`AppDelegate` 接线共享处理器、`ListItemView` `.resizable()`、`NSImage+Resized` 修 width-blind 放大检查 — `5167d15` / `1085308` / `44c1e59` / `1672b57` / `9cbd4b6`(去多余 disable)。
- **3.9** 验证闸门:即上述 CI run。

**偏差记录**:
1. **3.0 / 3.4 延期**:六个真实图片 fixture(png/jpeg/heic/truncated 等)未创建——HEIC 在 Linux 无法编码(libheif 不可用),其余可合成但收益有限。三个组件的核心行为已由 `FixtureLoader.imageData`(运行期合成 TIFF)单测覆盖;真实图片/HEIC 的端到端降采样测试留待 Mac 环境或 `MaccyPerformanceTests` target 补。
2. **`ImageProcessor` 协议一致性漏标**(见 `0c68cab`):3.3 单测用具体类型未暴露,批次以存在量使用时才编译失败——no-compiler 环境下"用到才暴露"的问题只能 CI 兜底。
3. **HDRImageConverter headless 日志**:批次把图片走 ImageIO 后,系统私有 `HDRImageConverter` 在无 GPU 的 CI runner 上打印 "Failed to initialize Metal converter, falling back to SIMD"(转换实际成功,走 SIMD 回退)。CI 日志扫描据此拦下;`16bd334` 在扫描里排除这一条已知良性 headless 告警,其余仍严格。
4. **不采用 Metal MPS**(评估后否决,2026-06-15):外部建议 `MPSImageLanczosScale` + `rgba16Float` + `CISystemToneMap` 做 HDR 缩略图。经 sosumi 核实 API 属实,但:(a) BS-3 代码用 ImageIO,全仓无 Metal;(b) Metal 在 headless CI 同样不可用,改 Metal 修不了 CI;(c) 与 roadmap 冲突、对 340px SDR 剪贴板缩略图属过度设计;(d) 真机上系统已正确 tone-map。保留 ImageIO(roadmap 设计)。

**验收**:复制/预览/缩略图行为与改前一致(`MaccyUITests` 全绿);损坏图走错误状态(IMG-018)。复杂度量级(~10×,`O(srcPixels)` draw → `O(targetPixels)` ImageIO)与常驻内存量化留 BS-6。`@unchecked Sendable` 暂留(彻底摘除留 BS-7)。

## 受影响文件
- 新:`Maccy/ImageProcessing/ImageDownsampler.swift` — ImageIO 缩略图纯函数(可单测)。
- 新:`Maccy/ImageProcessing/ImageProcessor.swift` — 真实 `actor ImageProcessor`(替换 `PassthroughImageProcessor`),后台降采样/解码/缩略图/预览。
- 新:`Maccy/ImageProcessing/ThumbnailCache.swift` — `NSCache` + 磁盘 LRU,键=内容指纹。
- 改:`Maccy/Extensions/NSImage+Resized.swift:18-25` — `resized(to:)` 改用 ImageIO(或标记 deprecated,新路径绕过);修 `:14` 的 width-blind "不放大"检查(IMG-013/024)。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:13` — `previewImageSize` 由整屏 `visibleFrame` 改为预览区封顶(≤ `previewMaxPixels`,见 C)。
- 改:`Maccy/Observables/HistoryItemDecorator.swift:44-51,89-189` — 去 `decodedImage`;`ensureThumbnailImage`/`ensurePreviewImage`/`asyncGetPreviewImage`/`sizeImages`/`image()`/`generate*Image`/`cleanupImages` 改走 `ImageProcessor`;去 `Task { @MainActor }` 包裹(`:100,:116`);错误不再吞(`:127`,IMG-022);取消检查(IMG-023)。
- 改:`Maccy/Views/PreviewItemView.swift:17-19,26-49` — placeholder 用预览区尺寸而非整屏(IMG-017);区分 `.failed`/`.loading`(IMG-018)。
- 改:`Maccy/Views/ListItemView.swift:72` — `Image(nsImage:)` 加 `.resizable()`(IMG-020)。
- 改:`Maccy/AppDelegate.swift` — 注入真实 `ImageProcessor` 替换 `PassthroughImageProcessor`(BS-2 注入处)。

## 小步骤

- [ ] **3.1 ImageIO 降采样纯函数** — `ImageDownsampler.swift`。`enum ImageDownsampler { static func thumbnail(data: Data, max: CGFloat) -> CGImage? }`:
  - `CGImageSourceCreateWithData(data, nil)`;`kCGImageSourceThumbnailMaxPixelSize = Int(max)`、`kCGImageSourceCreateThumbnailFromImageAlways = true`、`kCGImageSourceShouldCacheImmediately = true`、`kCGImageSourceCreateThumbnailWithTransform = true`(尊重 EXIF 朝向)。
  - 失败(损坏/截断/`CGImageSourceCreateThumbnailAtIndex` 返回 nil)→ 返回 nil(调用方据此走错误状态,IMG-018)。
  - 纯函数无 AppKit/SwiftData 依赖 → 可单测(传入 fixture,断言输出 `CGImage` 的 `width <= max` 且 `height <= max`)。
- [ ] **3.2 缩略图双层缓存** — `ThumbnailCache.swift`。
  - `final class ThumbnailCache: @unchecked Sendable`(内部 `NSCache<ThumbnailKey, NSImage>` + 磁盘 LRU 目录 `~/Library/Application Support/Maccy/Thumbnails/`)。
  - 键=`MaccyFingerprint`(BS-1 DTO;内容指纹,BS-8 后持久化);`func thumbnail(for fp: MaccyFingerprint, data: Data, max: CGFloat) async -> NSImage?`:内存命中→返回;否则磁盘命中→读 PNG→回填内存;否则 `ImageDownsampler.thumbnail`→写磁盘 LRU(超过 256MiB 按 LRU 淘汰,见 C `缩略图缓存`)→回填内存。
  - 失效策略(本步最小集):按指纹覆盖写(指纹即内容身份);**显式按 item id 失效留给 BS-6**(因 BS-6 才管 imageData 回收与删除路径)。本步提供 `func evict(fp:)`/`func clearDisk()` 供 BS-6 调用与测试。
- [ ] **3.3 真实 ImageProcessor actor** — `ImageProcessor.swift`。实现 BS-1 `protocol ImageProcessing`:
  - `actor ImageProcessor { init(cache: ThumbnailCache) }`
  - `func thumbnail(for data: Data, max: CGSize) async -> NSImage?`:取 `max(thumbnailMax)` → `cache.thumbnail(...)`(自动享内存/磁盘)→ `NSImage(cgImage:size:)`。
  - `func preview(for data: Data, max: CGSize) async -> NSImage?`:`ImageDownsampler.thumbnail(data:, max: previewMaxPixels)`(预览不走缓存,见 3.7)。
  - 接受 `CGImage`/`Data` 均为 `Sendable`;返回 `NSImage`(AppKit `NSImage` 非严格 Sendable,经 actor 边界以值语义回主线程赋值,见 3.5)。
- [ ] **3.4 降采样/缓存单测** — `MaccyTests/ImageDownsamplerTests.swift`、`ThumbnailCacheTests.swift`:
  - `ImageDownsamplerTests`:`png_1x1`→不变;`screenshot_1440x900` + max=340 → 输出 ≤340 且保留长宽比;`photo_12mp` + max=340 → 大图降采样(量化 ~10×,标注"实测验证");`heic` → 解码不崩;`corrupt_truncated` → nil。
  - `ThumbnailCacheTests`:首次 miss→落盘;二次命中内存;清内存后命中磁盘;`evict(fp:)` 后 miss。
- [ ] **3.5 [breaks compile until 3.8] HistoryItemDecorator 改后台解码** — `HistoryItemDecorator.swift:44-51,89-189`。
  - 注入 `private let imageProcessor: ImageProcessing`(经 init 参数,默认走共享实例);删除 `decodedImage`(`:51,:187`)——不再常驻全分辨率位图。
  - `ensureThumbnailImage()`(`:90-103`)/`ensurePreviewImage()`(`:105-119`):去掉 `Task { @MainActor [weak self, image] in ... }`(`:100,:116`),改 `Task.detached { [weak self] in let img = await self?.imageProcessor.thumbnail(preview...) ; await MainActor.run { self?.thumbnailImage = img } }`;`Task.isCancelled` 检查(IMG-023):resize 前与赋值前各 `try? Task.checkCancellation()`,取消则丢弃(避免 IMG-023 的悬挂位图)。
  - `image()`(`:178-189`)拆分:不再返回常驻 `NSImage`;列表/预览分别经 `imageProcessor.thumbnail/preview` 取小位图。
- [ ] **3.6 预览目标尺寸封顶** — `HistoryItemDecorator.swift:13`。`previewImageSize` 由 `NSScreen.forPopup?.visibleFrame.size ?? 2048×1536` 改为预览区实际尺寸封顶 `previewMaxPixels`(≤1600² backing,见 C `预览目标尺寸`);不依赖整屏,跨屏切换时不再重算巨型位图。配套:`sizeImages()`(`:168-175`)不再同时生成两图(IMG-003/017)——列表驱动 thumbnail、预览 popover 驱动 preview。
- [ ] **3.7 错误传播与 placeholder 收敛** — `HistoryItemDecorator.swift:122-129`;`PreviewItemView.swift:17-19,26-49`。
  - `asyncGetPreviewImage()` 返回 `NSImage?`(语义改为"成功/失败",nil=失败而非未就绪);移除 `_ = await previewImageGenerationTask?.result` 吞错(IMG-022)→ `logger.error` 失败分支。
  - `PreviewItemView` placeholder 用预览区尺寸(3.6)而非整屏(IMG-017);`.failed` 渲染 `photo.badge.exclamationmark`,`.loading` 渲染 spinner(IMG-018)。
- [ ] **3.8 [restores compile] 接线 + 列表 `.resizable()` + 弃用旧 resize** — `AppDelegate.swift`;`ListItemView.swift:72`;`NSImage+Resized.swift`。
  - `AppDelegate` 注入 `ImageProcessor` 替换 `PassthroughImageProcessor`(BS-2 注入点)。
  - `ListItemView.swift:72` 的 `Image(nsImage:)` 加 `.resizable()`(IMG-020),避免推送全分辨率 backing。
  - `NSImage+Resized.swift:18-25` 的 `draw` 路径标 `@available(*, deprecated, message: "use ImageDownsampler/ImageProcessor")`;修 `:14` 的 width-blind "不放大"检查为同时比较 width/height(IMG-013/024);保留兼容调用点(无图片路径走非主线程已不依赖它)。编译恢复。
- [ ] **3.9 验证** — `xcodebuild build` + `xcodebuild test` 通过;手动:复制大图(12MP)→ 预览瞬时弹出、无主线程卡顿;浏览 50 张图,常驻内存对比改前明显下降(量化留 BS-6)。

## 测试
- 引用:`B §2`(`FixtureLoader` 的 `png_1x1`/`jpeg_small`/`screenshot_1440x900`/`photo_12mp`/`heic`/`corrupt_truncated`、`MainThreadProbe`)、`§4`(`G-copy-large-image`)。
- 新增:`ImageDownsamplerTests`(3.4)、`ThumbnailCacheTests`(3.4)、`ImageProcessorContractTests`(`thumbnail` 输出 ≤max;HEIC/损坏边界)、`HistoryItemDecoratorImageTests`(thumbnail/preview 经后台 actor;取消后不写悬挂位图,IMG-023)。
- 闸门:`G-copy-large-image`(复制 12MP 图→可预览,主线程无 >16ms 段);与 BS-2 的 `G-copy-text` 并列运行。

## 验收标准
- 功能:复制/预览/缩略图行为与改前一致(用户可见);损坏图走错误状态而非"永久 loading"(IMG-018)。
- 复杂度(C 复杂度预算):图片缩略图 `O(srcPixels)` 全量解码+draw → `O(targetPixels)` ImageIO 降采样;**量化 ~10× 量级(实测验证)**;图片预览同向改善,目标由整屏 `visibleFrame` 收敛到 ≤`previewMaxPixels`。
- 管线(C §3):复制大图→可预览 主线程预算 <16ms(无解码),端到端 <400ms(后台降采样)。
- I/O 限制(C §2):预览目标尺寸 ≤ `previewMaxPixels`(整屏封顶);缩略图磁盘 LRU ≤256MiB;`asyncGetPreviewImage` 不再 `await` 主线程任务(IMG-006);`sizeImages()` 不再同时生成两图。
- 不变性:`A §7` 的"主线程无重活""跨 actor 载荷 Sendable"(经 `Data`/`CGImage`/`NSImage` 值传递)在本步达成;`@unchecked Sendable` 暂保留(`decodedImage` 移除后风险下降,彻底摘除留 BS-7)。

## Commit
`perf(image): ImageIO downsample, off-main decode, capped preview, two-tier thumbnail cache`

---

## 补强(2026-06-21)— preview 取消的 IMG-023 遗漏

BS-3 落地时 IMG-023 的结构化取消只接到了 `invalidate()`/`cleanupImages()`(删除/清空/reconcile-removal 路径),**没接选择切换**。后果:`ImageProcessor` 是单个串行 actor,thumbnail+preview 解码全部排队;导航离开一个 lead item 时,它的 preview 解码继续跑完,堆积在 actor 队列上 → A mixed thumbnail `latencyMax=1530ms` 的长尾;鼠标 hover 是真实环境最坏触发(无节流,每次 row-enter 都发一次 selection → `.id` 重建 → `ensurePreviewImage`)。

**修复:**
- `HistoryItemDecorator.cancelPreviewGeneration()` — cancel + nil 掉 `previewImageGenerationTask`,**保留已缓存的 `previewImage`**(re-select 已解码项保持即时;re-select 已取消-未缓存项通过 nil 的 handle 重新 kick)。
- `NavigationManager.leadHistoryItem.didSet` 在 lead 变化时调用 `oldValue.cancelPreviewGeneration()`(已按 id 去重)。集中式、与视图树无关。
- TDD:`HistoryDecoratorTests` 用 `ControllableImageProcessor` mock(解码可 park/可取消)补三例取消断言,填补此前没有任何测试验证取消的空白。

**已知局限:** 进行中的 `CGImageSourceCreateThumbnailAtIndex` 不可取消,所以一个已开始解码的图会跑完(结果被丢弃);完整的 latest-wins 抢占(actor 优先级队列)是更大的改动,暂缓。

详见 `docs/audit/architecture-and-root-causes.md` §2.4(图片管线)。

# BS-6 内存治理 — 缺口详审计(2026-06-28)

> 规范:`docs/audit/2026-06-14/roadmap/step-6-memory.md`(12 小步)。
> 相关提交:`23c41c0`/`0be3e20`(perf bs6 defer decorator imageData blob lazy)、`66d8398`(docs bs6 measured memory profile + plan)、`1216d15`/`04298ab`(fix bs6.13 Popup hotkey leak ~40MB)。
> 另:`mem27` 系列(c2a7c94 U1 .help gate 等)、06-27 memory-floor-and-retention 审计。
> 当前源码 HEAD `b6653fc`。

## 总览

- **完成**:5(6.1、6.5、6.6、6.8、6.9)
- **部分**:5(6.2、6.3、6.4、6.7、6.12)
- **跳过**:2(6.10、6.11)
- **commit 诚实度**:✅ 诚实(范围收窄与偏差在 06-25/06-27 审计文档有记录)
- **文档勾选**:0/12(step-6 文档未勾选;偏差在旁侧文档,不在 step 文档内)

## 核心问题:DecodedImageCache 是死代码

`Maccy/Observables/MemoryGovernance.swift:60-85` 的 `DecodedImageCache`(NSCache 32/64MiB)是 BS-6 C1 的
核心交付物,曾被记为 "decoded-image working set bounded to visible window"。但:
- `setImage/image(for:)` **零调用方**(全仓 grep 无命中)。
- 只有 `evict`/`purgeAll` 被调(HistoryItemDecorator.swift:219,232),即只有"驱逐"没有"存取"。
- preview 位图仍 per-decorator 持有在 `previewImage`,从未进 NSCache。

→ "解码位图按可视区限界"的核心目标**从未实现**。这是 06-27 7-agent review 才发现的死代码。
`releaseTransientImages(.previewHidden)` 枚举 case(`:217`)同样零调用方 — 死枚举。

**[[mem27-uxsafe-verdicts]] 已记录**:C6-done-right(接通 DecodedImageCache)是可选的 sound-but-preview-touching 工作;
但现状是"既未接通也未删除",留作死代码。

## 逐小步

### 6.1 VisibilityTracker 协议 — ✅ 完成
`MemoryGovernance.swift` 定义 `VisibilityObserving`/`VisibilityTracker` 协议。

### 6.2 DecodedImageCache (NSCache)— ⚠️ 部分(死代码)
NSCache 建好但无存取调用方(见上)。限界目标未达成。

### 6.3 MemoryGovernor (@MainActor 协调器)— ⚠️ 部分
存在并接入 AppDelegate(attach+start);但 `handleMemoryWarning` 只做 5 步里的 3 步:缺 `RegexpCache.purgeStale()`(无 RegexpCache 类)、缺 `ThumbnailCache` memory `removeAllObjects()`。

### 6.4 decorator 去双份 + 解码位图经 NSCache — ⚠️ 部分
`releaseTransientImages(_:)` + `cleanupImages` 委托已做;但解码位图未进 NSCache(死代码,见上)。

### 6.5 History HistoryRef + sessionLog 迁移 — ✅ 完成
`sessionLog` 现为 `[Int: PersistentIdentifier]`(History.swift:150);HistoryRef 机制就位。

### 6.6 ApplicationImageCache NSCache + fd guard — ✅ 完成
`ApplicationImageCache` NSCache 限界 128 + fd guard 已做(M4,CI green)。

### 6.7 接线 + onDisappear + 警告挂载 — ⚠️ 部分
`HistoryItemView.onDisappear` → scroll-out release 已接;`DispatchSource` 内存警告源已接。但 `.previewHidden` 从未接产(零调用方)。

### 6.8 RegexpCache + 重建 — ✅ 完成
`ignoredRegexps` 经 NSCache 限界(M5)。

### 6.9 ColorSwatchCache — ✅ 完成
ColorImage NSCache 限界(M9)。

### 6.10 withObservationTracking 重注册足迹(minor)— ❌ 跳过
仍用 recursive `withObservationTracking` + `DispatchQueue.main.async`(HistoryItemDecorator.swift:398-434),无 `@ObservationIgnored` token var。06-27 status doc:40 "C4 DEFERRED,isInvalidated guard already limits,low value"。规范本身标 minor。诚实延后,有记录。

### 6.11 测试 — ❌ 跳过
6 个规范要求的测试文件**全缺**:`MemoryGovernanceTests`、`DecodedImageCacheTests`、`ApplicationImageCacheTests`、`RegexpCacheTests`、`ColorSwatchCacheTests`、`SessionLogReleaseTests`。MaccyTests 只有 BS-3 的 `ThumbnailCacheTests.swift`。grep `releaseTransientImages/MemoryGovernor/DecodedImageCache/VisibilityTracker` 在 MaccyTests+MaccyUITests 无命中。

### 6.12 验证(build+test + G-memory 闸门)— ⚠️ 部分
CI 绿;但 `MaccyPerformanceTests` target 仍不存在(CLAUDE.md 确认 "planned but not yet created")。量化 <300MiB 闸门与手动内存警告注入测试从未作为闸门运行。实践中 <300MiB 平凡满足(06-27 实测 floor ~62MB),但闸门从未构建。

## 系统性缺口

- **测试全缺**(6.11):6 个文件 0 个。内存治理的回归保护为零。
- **G-memory 闸门未建**(6.12):无量化回归保护。
- **死代码未处理**:DecodedImageCache + `.previewHidden` 枚举 case。要么接通(mem27 C6-done-right)要么删除。
- **VisibleWindowLoader 仍是死代码**(`Storage+Background.swift:47-75`,仅 MaccyTests 调用,从未接入 `History.load()`):虽属 BS-4 范畴,但 BS-6 内存视角下 C5 是最大未 tapped 内存杠杆(6–13MB),且 06-27 已正式 DROPPED 作为内存杠杆(LazyVStack 回收 + blob 仍 pinned + 破坏 search UX)。详见 [[measured-memory-profile-2026-06-24]] / [[mem27-uxsafe-verdicts]]。

## 建议补全(按价值/风险排序)

1. **DecodedImageCache 决策**(最高):要么接通(`setImage` on decode / `image(for:)` on reopen,使 preview 位图进 NSCache — 即 mem27 C6-done-right),要么删除死代码 + `.previewHidden` case。当前"留着不用"最坏。
2. **6.11 测试**:至少补 `DecodedImageCacheTests`(若接通)+ `MemoryGovernorTests`(警告源驱逐行为)。
3. **6.3 handleMemoryWarning**:补 ThumbnailCache memory `removeAllObjects()`。
4. **6.12 G-memory 闸门**:建 MaccyPerformanceTests target + <300MiB 量化闸门(可与 BS-5 G-search 闸门一并建)。
5. **文档**:更新 step-6 勾选框,把 DecodedImageCache 死代码、VisibleWindowLoader dropped、06-27 floor 结论记入 in-step 偏差。

## 证据索引
- `Maccy/Observables/MemoryGovernance.swift:60-85` — DecodedImageCache(零调用方)
- `Maccy/Observables/HistoryItemDecorator.swift:217,219,232` — `.previewHidden` 零调用方;evict/purgeAll 调用
- `Maccy/Observables/History.swift:150` — sessionLog [Int:PersistentIdentifier]
- `Maccy/Storage+Background.swift:47-75` — VisibleWindowLoader 死代码
- `docs/audit/2026-06-27-memory-floor-and-retention/` — floor ~62MB、C5 dropped、F1 image-heavy-only
- [[mem27-uxsafe-verdicts]] — C6-done-right 可选项

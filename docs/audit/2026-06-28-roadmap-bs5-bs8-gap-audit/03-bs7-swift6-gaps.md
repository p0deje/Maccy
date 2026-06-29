# BS-7 Swift 6 严格并发 — 缺口详审计(2026-06-28)

> 规范:`docs/audit/2026-06-14/roadmap/step-7-swift6.md`(17 小步 7.1–7.17)。
> 相关提交:`194676f`(bs7.1)→ `011949f`(bs7.2)→ `9f0fac0`/`cb34320`/`6f0be24`/`c453318`(Popup 级联)→ `cd18026`/`1c8f0f9`/`0f00cb1`(no-unsafe)→ `05b3d94`(eliminate @unchecked + flip to 6.0/complete)→ `31a9f60`(complete 24 violations)→ 多个 fix(bs7)(c6193c7…efc19f7)。
> 当前源码 HEAD `b6653fc`。CI run `28322047363`(efc19f7)= success 9m8s;HEAD `b6653fc` 也绿。

## 总览

- **完成**:13(7.1、7.2、7.3、7.5、7.6、7.7、7.8、7.9、7.12、7.14、7.16、7.17 + 7.10 取代)
- **部分**:3(7.4、7.11、7.15)
- **跳过**:1(7.13)
- **取代**:1(7.10,合理)
- **commit 诚实度**:✅ 诚实(`05b3d94` 明说 "complete mode will surface a new wave of violations... fixed next")
- **文档勾选**:0/17
- **核心目标达成**:✅ Swift 6.0 complete 模式 CI 绿,`@unchecked Sendable`/`nonisolated(unsafe)` 实际归零

**这是四个大步骤里最扎实的一个。** 核心目标(切到 complete 模式、去 unsafe)真做到了。缺口集中在"规范唯一的行为级改动 + 测试 + 清理"。

## 逐小步

### 7.1 构建设置归一化 — ✅ 完成
`project.pbxproj:1821/1849/1874/1899/2056/2092` 6 个配置全 `SWIFT_VERSION=6.0` + `SWIFT_STRICT_CONCURRENCY=complete`(超规范的 5)。gnu++0x→gnu++17。

### 7.2 隔离标注准备(类型级 @MainActor + Sendable struct)— ✅ 完成
AppState/History/Clipboard 类型级 @MainActor;Signature/ContentSignature/ContentIndex :Sendable。

### 7.3 去 decorator/AppDelegate 的 @unchecked — ✅ 完成
grep `@unchecked Sendable|nonisolated(unsafe)` in Maccy/ = 0 实际标注(仅 5 处注释说明)。

### 7.4 Singleton @MainActor + ApplicationImage DispatchSource→.main — ⚠️ 部分
ApplicationImage 已 @MainActor,但 `ApplicationImage.swift:76` 仍 `queue: DispatchQueue.global()` + `:79` 内层 `DispatchQueue.main.async` — 正是 7.4 要替换为 `queue:.main` 的模式。经 main hop 隔离安全(故 complete 编译过),但规范的改法未做。

### 7.5 @Model/ModelContext 不跨域;OnNewCopyHook;sessionLog→ItemID — ✅ 完成
OnNewCopyHook 已删(BS-2 取代);sessionLog 现为 `[Int: PersistentIdentifier]`;AppIntent perform() @MainActor。

### 7.6 裸 Task{} 显式化 — ✅ 完成
类型级 @MainActor 使裸 Task{} 继承隔离(规范允许)。

### 7.7 跨域闭包隔离 — ✅ 完成
NSEvent monitor / 通知值 / Timer / paste / KVO 全经 fix(bs7) 系列处理。

### 7.8 @objc + 隔离对齐 — ✅ 完成

### 7.9 deinit/release 路径审查 — ✅ 完成
`31a9f60` 用 `MainActor.assumeIsolated`(同步断言,非 async hop)处理 Popup nonisolated deinit。

### 7.10 C++/ObjC 桥 nonisolated + SendableWrappers.swift — 🔄 取代(合理)
`ClipboardDataProcessor` 是 enum,static func 默认 nonisolated;`MaccyTextProcessor.mm` 纯函数桥 complete 编译过。未建 `SendableWrappers.swift`(规范标条件性,桥已证线程安全)。目标达成无包装。

### 7.11 值类型 Sendable — ⚠️ 部分
Search/SoftwareUpdater @MainActor ✓;Notifier 经 `OSAllocatedUnfairLock`(`31a9f60`,取代规范的 @MainActor,目标达成)。**但** `Sorter.swift:6`、`Throttler.swift:4` 仍是裸 class(规范要 @MainActor/actor);Selection/KeyShortcut/SearchResult 无显式 :Sendable(Swift 6 隐式,但规范要显式)。仅因 HistoryItem nonisolated + main 上下文使用而编译过。

### 7.12 AppIntent 默认执行器 + DTO 投影 — ✅ 完成
Get/Delete/Select `perform()` @MainActor;Clear `await` AppState.shared.history.clear()。

### 7.13 Combine/Observation 线程收敛 — ❌ 跳过(规范唯一行为级改动)
**这是规范里唯一的运行时行为级改动**,要求把 recursive `withObservationTracking` + `DispatchQueue.main.async { self.synchronize...() }` 模式替换为 computed mirror / AsyncStream。
**现状**:`HistoryItemDecorator.swift:398-431`(`synchronizeItemPin`/`synchronizeItemTitle`)与 `AppDelegate.swift:229-240`(`synchronizeMenuIconText`)**仍用原模式**。模式仍工作(非正确性 bug),但规范的重构 + `ObservationMirrorTests` 从未做。

### 7.14 entitlements/Info.plist 审查 — ✅ 完成

### 7.15 删冗余 per-method @MainActor — ⚠️ 部分
AppDelegate 清到 0;**但** HistoryItemDecorator 仍 12、History 仍 40(共 52 冗余)。规范要删"大部分"的 62 个,只清了 AppDelegate。

### 7.16 审查 C++ 标准 — ✅ 完成
留 gnu++17(规范允许)。

### 7.17 全量验证 — ✅ 完成
CI 绿(complete 模式)。MaccyPerformanceTests target 仍不存在(预存,非 bs7 回归)。

## 主要缺口

1. **7.13(规范唯一行为级改动)跳过**:recursive obs+main.async 模式仍在。`ObservationMirrorTests` 未建。
2. **4 个规范要求的测试文件全缺**:`SendableBoundaryTests`、`ObservationMirrorTests`、`ClipboardIsolationTests`、`AppIntentDtoTests`。无替代边界/镜像/隔离测试。最明显的"测试脏活静默丢"信号。
3. **7.15 部分**:52 个冗余 per-method @MainActor 仍留。
4. **7.11 部分**:Sorter/Throttler 未 @MainActor/actor 化。
5. **7.4 部分**:ApplicationImage DispatchSource 仍 `.global()` + main.async hop。
6. **无偏差记录**:跳过的 7.13、缺的 4 测试、部分的 7.15/7.11/7.4 从未在 audit docs 记为偏差。06-27 一份记忆文档 `04-status-vs-master-plan.md:56` 甚至误记 "BS-7 DEFERRED" — 与实际的 complete 模式构建矛盾(已过时)。
7. **无正式 BS-7 收尾 commit**:规范设想的最终 `build(swift6): migrate...` commit 从未做;工作碎在 ~25 个 commit 后转向 bs5。

## 建议补全(按价值/风险排序)

1. **7.13 obs 收敛**(规范唯一行为级):把 synchronizeItemPin/Title/MenuIconText 改 computed mirror 或 AsyncStream + 建 `ObservationMirrorTests`。改动面中、是规范核心行为项。
2. **4 个测试文件**:至少补 `SendableBoundaryTests`(并发安全回归保护)与 `ObservationMirrorTests`。
3. **7.15 清理**:删 History/HistoryItemDecorator 的 52 个冗余 per-method @MainActor(类型级已覆盖)。低风险纯清理。
4. **7.11**:Sorter/Throttler 标 @MainActor 或改 actor;Selection/KeyShortcut/SearchResult 显式 :Sendable。
5. **7.4**:ApplicationImage DispatchSource 改 `queue:.main`。
6. **文档**:更新 step-7 勾选框(13✓ 3⚠ 1❌ 1🔄),记 7.13 跳过偏差。

## 证据索引
- `Maccy.xcodeproj/project.pbxproj:1821,1849,1874,1899,2056,2092` — SWIFT_VERSION=6.0 + complete
- grep `@unchecked Sendable|nonisolated(unsafe)` Maccy/ → 0 实际标注
- `Maccy/Observables/HistoryItemDecorator.swift:398-431` — 7.13 recursive obs+main.async 仍在
- `Maccy/Application/ApplicationImage.swift:76,79` — 7.4 DispatchSource.global()+main.async
- `Maccy/Sorter.swift:6`、`Maccy/Throttler.swift:4` — 7.11 裸 class
- per-method @MainActor 计数:HistoryItemDecorator=12、History=40(7.15 未清)
- `MaccyTests/` — SendableBoundaryTests/ObservationMirrorTests/ClipboardIsolationTests/AppIntentDtoTests 全缺
- step-7-swift6.md — 17 勾选框全 `[ ]`

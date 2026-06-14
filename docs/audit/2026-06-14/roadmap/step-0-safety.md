# BS-0 — 安全止血与构建卫生

> **依赖**:无。**编译边界**:每个小步骤独立可编译;完成全部后 `xcodebuild build` 通过、既有测试全绿。

**目标**:消除"崩溃 / 丢数据 / 静默失败 / 构建方言"四类已确认问题,为后续重构提供安全网。
**依据**:`07-F-032`(V-3 确认)、`07-F-001`(V-4 确认)、`07-F-002/003`(V-5 确认)、`07-F-017`、`99`(gnu++0x)。
**编译安全性**:均为局部修复,不改公共签名(除 `recoverContainer` 内部实现),末尾必然可编译。

## 受影响文件
- 改:`Maccy/Extensions/Collection+Surrounding.swift:18-32` — 修 `item(before:where:)` 首 index trap。
- 改:`Maccy/Storage.swift:37-72` — `recoverContainer` 不再删库,改隔离+询问。
- 改:`Maccy/Observables/History.swift:135,142,206-207,212,230-241,263-265,284,458`、`Maccy/Clipboard.swift:208`、`Maccy/Models/HistoryItem.swift:45,261,266` — `try?` 改为捕获+日志+按需传播。
- 改:`Maccy/Models/HistoryItem.swift:260-267` — `dataFromFileIfAllowed` 不在 `try?` nil 时 fallthrough。
- 改:`Maccy.xcodeproj/project.pbxproj:1676,1739` — `gnu++0x` → `gnu++17`。

## 小步骤

- [x] **0.1 修 `item(before:)` 首 index trap** — `Collection+Surrounding.swift`。在 `firstIndex` 之后、`index(offsetBy:-1)` 之前加 `guard currentIndex > startIndex else { return nil }`。原因:`Collection.index(_:offsetBy:)` 非可选,负向越界即 trap(见 V-3)。
- [x] **0.2 加回归测试** — `MaccyTests/CollectionSurroundingTests.swift`:`before_firstVisible_returnsNil_notTrap`,构造 `[a,b,c]`,`item(before: a, where: { _ in true })` 期望 `nil`(不崩溃)。
- [x] **0.3 `recoverContainer` 改隔离策略** — `Storage.swift`。失败时把现有 store 文件(`-sqlite/-shm/-wal`)移动到 `<dir>.corrupted-<stamp>/`(stamp 由调用方传入,避免在库内用 `Date.now`),新建空 store,并通过回调(新增 `init` 参数 `onCorruption: ((URL) -> Void)?`)通知 UI 弹确认;**不再无条件删除**。`preconditionFailure` 保留为最终兜底。
- [x] **0.4 加恢复测试** — `MaccyTests/StorageRecoveryTests.swift`:注入坏 store → 断言文件被**移动**到 `.corrupted-*` 而非删除,且返回可用 in-memory/空 container。用可控时间戳参数避免依赖系统时钟。
- [x] **0.5 错误不再静默** — 在 `History.insertIntoStorage`/`delete`/`clear`/`clearAll`/`findSimilarItem` 与 `Clipboard`/`HistoryItem` 的 `try?` 处,改为 `do/catch`:`logger.error(...)` 记录;写路径失败时**回滚内存态**(从 `all`/`items` 移除未持久化的项)并通过新的 `@MainActor var lastPersistError` 暴露给 UI 可选提示。读路径失败仅记日志并返回空。
- [x] **0.6 修 `dataFromFileIfAllowed` fallthrough** — `HistoryItem.swift:260-267`。`try? url.resourceValues` 返回 nil 时,**视为未通过大小校验**,返回 nil,不进入 `Data(contentsOf:)`。
- [ ] **0.7 统一 C++ 方言** — `project.pbxproj`。两个 `gnu++0x` config 改 `gnu++17`(与 Maccy 目标 `gnu++14` 对齐,并为 BS-8 预留)。
- [ ] **0.8 全量验证** — `xcodebuild build` + `xcodebuild test` 通过;手动:首项按 ↑ 不崩;模拟坏 store 不丢历史。

## 测试
- 引用:`B-test-strategy.md` 的 `FixtureLoader`(合成坏 store)、`HistoryBuilder`。
- 新增:`CollectionSurroundingTests`、`StorageRecoveryTests`、`IngestErrorPropagationTests`(覆盖 0.5)。
- 闸门:无新增性能闸门(本步骤不改性能特性)。

## 验收标准
- 功能:首项 ↑ 返回 nil 不崩;容器损坏→隔离非删除;save 失败有日志且内存态回滚;`gnu++17` 编译通过。
- 复杂度:不变(均为常数修复)。
- 管线:不变。
- I/O 限制:文件读取 `try?` nil 时不再无界读取(0.6)。
- 不变性:`A-architecture-target.md §7` 的"容器失败不删库""不再 try? 静默"在本步达成。

## Commit
单个 commit:`fix(safety): crash on first-item up, store recovery data loss, swallowed persist errors, c++ dialect`。

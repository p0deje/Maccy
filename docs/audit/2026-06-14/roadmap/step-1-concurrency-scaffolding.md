# BS-1 — 并发脚手架(纯加法)

> **依赖**:BS-0。**编译边界**:**仅新增文件/类型,不修改任何既有调用点**;全程可编译,既有测试全绿。

**目标**:为 BS-2~8 提供"目标态"的骨架——后台 context、Sendable DTO、去重索引、ingest 协议与适配器、测试设施。本步骤**不接线**,只把零件造好。
**依据**:`A-architecture-target.md`(架构)、`04`/`08`(去重与 context)。
**编译安全性**:零既有签名变更;新类型未使用至多产生 `unused` 警告(可 `// swiftlint:disable:next unused_declaration` 临时抑制,BS-2 接线后移除)。

## 受影响文件(全部新增)
- 新:`Maccy/Persistence/Storage+Background.swift` — 后台 context 工厂。
- 新:`Maccy/Ingest/Dtos.swift` — DTO + `IngestRequest/Plan/Result` + `StoreEvent`。
- 新:`Maccy/Ingest/SignatureIndex.swift` — 内存去重索引(纯值类型)。
- 新:`Maccy/Ingest/ClipboardIngestor.swift` — `protocol ClipboardIngestor` + `MainActorIngestorAdapter`(桥接既有 `History`,行为不变)。
- 新:`Maccy/ImageProcessing/ImageProcessing.swift` — `protocol ImageProcessing` + 适配器占位(实现在 BS-3)。
- 新:`MaccyTests/Support/*` — doubles/fixtures(见 `B-test-strategy.md §2`)。

## 小步骤

- [ ] **1.1 后台 context 工厂** — `Storage+Background.swift`。为 `Storage` 扩展:
  - `func newBackgroundContext() -> ModelContext`(封装 `container.newContext()`,设 `automaticallyMergesChangesFromParent = true` 与 `undoManager = nil`)。
  - 文档约定:返回的 context 仅在调用方 actor 内使用,禁止跨域。
- [ ] **1.2 DTO 定义** — `Dtos.swift`。全部 `struct ... : Sendable`(字段见 `A §4`):
  - `ContentDTO(type, value: Data?, fingerprint: UInt64?, size: Int)`
  - `ClipboardItemDTO(contents: [ContentDTO], application: String?, source: PasteboardSource)`
  - `SignatureDTO(entries: [ContentSignatureEntry])` + `ContentSignatureEntry(type, fingerprint: UInt64?, size)`
  - `MaccyFingerprint(size: Int, hash: UInt64)`
  - `ItemSnapshotDTO(id, title, firstCopiedAt, lastCopiedAt, numberOfCopies, pin, application, textPreview: String, imageFingerprint: UInt64?)`(**不含大 blob**)
  - `StoreEvent`:`enum { added(ItemSnapshotDTO), merged(ItemSnapshotDTO), removed(UUID), cleared }`
  - `IngestRequest`/`IngestPlan`/`IngestResult`(见 `B §3`,含 `metrics: { dedupHits, bytesHashed, parseMs }`)。
- [ ] **1.3 去重索引(纯值类型)** — `SignatureIndex.swift`。
  - `struct SignatureIndex: Sendable` 内部 `[SignatureDTO: UUID]`(key 用稳定哈希);提供 `lookup(_:) -> UUID?`、`register(_:id:)`、`remove(id:)`、`bulkRegister(_:)`。
  - 纯函数,无 AppKit/SwiftData 依赖 → 可单测。
- [ ] **1.4 ingest 协议 + 主线程适配器** — `ClipboardIngestor.swift`。
  - `protocol ClipboardIngestor: Sendable { func ingest(_ request: IngestRequest) async -> IngestResult }`
  - `@MainActor final class MainActorIngestorAdapter: ClipboardIngestor`:内部转发到既有 `History.shared.add`(行为完全不变),仅把结果包成 `IngestResult`。**本步骤不接线**(BS-2 才让 `Clipboard` 使用它),保证既有行为零变化。
- [ ] **1.5 图片处理协议** — `ImageProcessing.swift`。
  - `protocol ImageProcessing: Sendable { func thumbnail(for data: Data, max: CGSize) async -> NSImage?; func preview(for data: Data, max: CGSize) async -> NSImage?; func recognizeText(in data: Data) async -> String? }`
  - 占位实现 `PassthroughImageProcessor`:沿用既有 `NSImage(data:)`+`resized` 路径(行为不变,BS-3 替换)。
- [ ] **1.6 测试设施** — `MaccyTests/Support/`:`PasteboardSimulator`、`HistoryBuilder`、`FakeClock`、`IngestorSpy`、`FixtureLoader`(含 `heavy_text.txt` 与合成图片 fixture 路径)、`MainThreadProbe`。
- [ ] **1.7 单元测试** — `SignatureIndexTests`(查/注册/移除/批量)、`DtoRoundTripTests`(DTO 与 `@Model` 互转,见 1.8)、`ImageProcessingContractTests`(占位实现与既有行为一致)。
- [ ] **1.8 投影函数(纯)** — `Dtos.swift` 附加:`func snapshot(of item: HistoryItem) -> ItemSnapshotDTO`(在 item 所属 context 上读轻量字段);`func contentDTOs(of item: HistoryItem) -> [ContentDTO]`。这两个是 BS-2/4 的复用基础。
- [ ] **1.9 验证** — `xcodebuild build` 通过(新类型未接线,允许 unused 警告);新单测全绿;既有行为未变(适配器/Passthrough 不改路径)。

## 测试
- 引用:`B-test-strategy.md §2`(全部 doubles)、`§3`(数据流抽象)。
- 新增:`SignatureIndexTests`、`DtoRoundTripTests`、`ImageProcessingContractTests`。
- 闸门:无(本步骤不改运行时行为)。

## 验收标准
- 功能:新增类型齐全且可单测;`MainActorIngestorAdapter`/`PassthroughImageProcessor` 行为与既有路径逐字节一致(契约测试)。
- 复杂度:`SignatureIndex.lookup` 目标 O(签名数)哈希查询;`bulkRegister` O(n)。
- 管线:无变化(未接线)。
- I/O 限制:`ItemSnapshotDTO` 不含大 blob;`ContentDTO.value` 受 `maxValueSize` 既有上限。
- 不变性:`A §7` 的"跨 actor 载荷 Sendable"由 DTO 类型保证;"`@Model` 不跨域"由投影函数(1.8)在边界完成。

## Commit
`feat(concurrency): scaffolding — background context, sendable DTOs, signature index, ingest/image protocols, test doubles`

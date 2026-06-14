# Maccy 性能修复路线图 — 索引与使用说明

> **给执行 agent**:本目录是一份**工程化、可逐步迭代**的修复路线图。每个大步骤(BS-x)结束时**必须能编译且测试通过**;大步骤内部的**小步骤可以中途不可编译**。小步骤用 `- [ ]` 勾选语法跟踪。

## 阅读顺序(必读)

1. **`A-architecture-target.md`** — 目标架构(actor/context/数据流/DTO 边界)。所有大步骤的目标态。
2. **`B-test-strategy.md`** — 测试抽象(test doubles/fixtures/数据流抽象/性能闸门)。每个大步骤引用这里的设施。
3. **`C-complexity-and-limits.md`** — 全局复杂度预算、I/O 限制、管线时延预算、内存预算。
4. **大步骤文档** `step-0-safety.md` → `step-8-cpp.md`(按依赖顺序执行)。

每份大步骤文档结构固定:目标 / 依据(finding id)/ 编译安全性 / 依赖 / 受影响文件(file:line)/ 小步骤 / 测试 / 验收标准 / 复杂度估计 / 管线估计 / I/O 限制。

## 编译边界规则(关键)

- **大步骤(Big Step,BS-x)= 编译边界**:完成其全部小步骤后,`xcodebuild build` 通过且既有测试全绿。每个大步骤结束 **commit 一次**。
- **小步骤**:可中途不可编译(如新增半成品模块、改签名中途)。但应尽量在每个小步骤内保持可运行,便于二分定位。
- 若某小步骤必然破坏编译,须在该小步骤内标注 `[breaks compile until 小步骤N]`,并在所属大步骤末尾恢复编译。

## 约定

- **引用既有代码用 `file:line`**(如 `History.swift:106`),**不粘贴原文**,减少上下文重复。
- **引用审计发现用 finding id**(如 `07-F-032`),指向 `docs/audit/2026-06-14/0[1-8]-*.md`。
- **新代码**:展示**签名/骨架**(接口、DTO、关键算法),不写空壳占位。
- **新文件路径**:`Maccy/` 下按职责分目录(`Maccy/Ingest/`、`Maccy/ImageProcessing/`、`Maccy/Persistence/` 等)。

## 大步骤总览与依赖

| 大步骤 | 目标 | 编译安全性 | 依赖 | 文档 |
|---|---|---|---|---|
| **BS-0** Safety & hygiene | 止血:崩溃/丢数据/构建方言 | 每个小步骤独立可编译 | — | `step-0-safety.md` |
| **BS-1** Concurrency scaffolding | 新增后台 context、DTO、actor 协议、test doubles(**仅新增,不改调用点**) | 全程加法,零破坏 | BS-0 | `step-1-concurrency-scaffolding.md` |
| **BS-2** Ingest → actor | 把摄取管线搬进 actor,主线程只持轻量 observable | 末尾恢复编译 | BS-1 | `step-2-ingest-to-actor.md` |
| **BS-3** Image pipeline | ImageIO 降采样、后台解码/OCR、缩略图缓存 | 末尾恢复编译 | BS-1,BS-2 | `step-3-image-pipeline.md` |
| **BS-4** Data pipeline | 增量插入、去重签名索引、分批 fetch、单事务摄取、预加载 | 末尾恢复编译 | BS-2 | `step-4-data-pipeline.md` |
| **BS-5** Text & search | 搜索搬后台、UTF-8/高亮索引修正、截断单位统一 | 末尾恢复编译 | BS-2 | `step-5-text-search.md` |
| **BS-6** Memory governance | NSCache、可视区/告警回收、去双份 | 末尾恢复编译 | BS-3 | `step-6-memory.md` |
| **BS-7** Swift 6 | strict concurrency minimal→targeted→complete | 每级编译通过 | BS-1~BS-6 | `step-7-swift6.md` |
| **BS-8** C++ extensions | xxh3、指纹持久化、(可选)pHash/RE2/vImage | 末尾恢复编译 | BS-4 | `step-8-cpp.md` |

依赖图:

```
BS-0 ──┐
       ├─→ BS-1 ──┬─→ BS-2 ──┬─→ BS-3 ──→ BS-6
                 │           ├─→ BS-4 ──→ BS-8
                 │           └─→ BS-5
                 └──────────── BS-7(随各阶段增量推进)
```

推荐执行序:**BS-0 → BS-1 → BS-2 → BS-3 → BS-4 → BS-5 → BS-6 → BS-7 → BS-8**。BS-7 贯穿,每完成一个大步骤可顺手收紧一级 strict concurrency。

## 术语

- **DTO**:Sendable 值类型,跨 actor 边界传递(从 `@Model` 拷贝出标量/数据)。
- **签名(Signature)/指纹(fingerprint)**:用于去重的内容摘要(见 `HistoryItemEngine.swift`、`ClipboardDataProcessor.swift`)。
- **主上下文(mainContext)**:绑定主队列的 SwiftData context,仅供 UI 轻量读。
- **后台上下文(background context)**:`container.newContext()`,供 actor 做重读/写。
- **预加载(pre-warm)**:弹窗打开前后台预取可见窗口并预解码,首屏拿到就绪数据。

## 度量基线(实施前后对比,见 `C-complexity-and-limits.md`)

- 弹窗冷开→首屏可交互:主线程挂钟 + main run-loop 占用。
- 复制大图→可预览时延;大历史(1000 条)搜索 P95;常驻内存(重度浏览 5 min)。
- Instruments:主线程 >16ms 帧数。

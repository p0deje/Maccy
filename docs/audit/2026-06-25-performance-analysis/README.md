# Maccy 性能与内存占用全面分析报告

**分析日期**: 2026-06-25  
**分析范围**: Maccy 主仓库 `/lzcapp/document/Projects/Maccy/Maccy/` 全部源码及现有审计文档  
**分析方式**: 只读分析,未修改任何代码;使用 7 个 agent 进行三轮交叉验证(架构映射 → 双管线深潜 → 交叉验证 → 综合)  
**本地构建/运行**: 无(本机无 Xcode/macOS 工具链);所有性能数据引用自 `docs/audit/2026-06-24/` 的实测结果与 CI 记录

## 文档索引

| 文件 | 内容 |
|------|------|
| [00-executive-summary.md](00-executive-summary.md) | 执行摘要:最大机会、预期收益、整体判断 |
| [01-methodology.md](01-methodology.md) | 方法论、数据来源、限制与假设 |
| [02-top-issues.md](02-top-issues.md) | 按影响 ×  effort 排序的前 10 大问题 |
| [03-module-analysis-history.md](03-module-analysis-history.md) | `History` / `SwiftData` / `Storage` 模块分析 |
| [04-module-analysis-search.md](04-module-analysis-search.md) | `Search` 模块分析 |
| [05-module-analysis-image.md](05-module-analysis-image.md) | 图片管线 (`ImageProcessing`, `ThumbnailCache`) 分析 |
| [06-module-analysis-ui.md](06-module-analysis-ui.md) | UI / `HistoryItemDecorator` / `ApplicationImageCache` 分析 |
| [07-module-analysis-ingest.md](07-module-analysis-ingest.md) | `Clipboard` / `ClipboardIngestor` / `SignatureIndex` 分析 |
| [08-cpp-rust-rewrite-plan.md](08-cpp-rust-rewrite-plan.md) | C++/Rust 重写候选评估与优先级 |
| [09-swift-quick-wins.md](09-swift-quick-wins.md) | 无需跨语言的 Swift 快速优化清单 |
| [10-roadmap-alignment.md](10-roadmap-alignment.md) | 与现有 BS-1 ~ BS-6 roadmap 的对齐关系 |
| [11-unresolved-questions.md](11-unresolved-questions.md) | 仍需实测验证的未决问题 |
| [12-module-complexity-table.md](12-module-complexity-table.md) | 各模块时间/空间复杂度总表 |
| [13-memory-audit.md](13-memory-audit.md) | 内存风险专项审计：按 severity × effort 排序的剩余内存占用风险 |
| [13a-memory-arc-lifecycle.md](13a-memory-arc-lifecycle.md) | 内存专项：ARC、生命周期、retain cycle、observer |
| [13b-memory-cache-and-storage-tiers.md](13b-memory-cache-and-storage-tiers.md) | 内存专项：多级存储、缓存策略、缓存命中率 |
| [13c-memory-reclamation-and-concurrency.md](13c-memory-reclamation-and-concurrency.md) | 内存专项：回收、UI/图片加载、并发与内存 |
| [13d-memory-layout-and-safety.md](13d-memory-layout-and-safety.md) | 内存专项：内存布局、数据结构、边界安全 |
| [13e-memory-cross-validation.md](13e-memory-cross-validation.md) | 内存专项：交叉验证结果、分歧与缺口 |
| [14-master-plan.md](14-master-plan.md) | **新执行总纲**：整合本分析 + 2026-06-24 实测，按 P0–P3 tier 的全面优化计划（取代旧 step-by-step，含已核实更正） |

## 核心结论(一句话)

Maccy 已经从全 `@MainActor` 管线演进为“后台 ingest actor + ImageIO 图片管线”, 致命瓶颈已被 roadmap 的 BS-1~BS-4 解决。当前最大的剩余杠杆全部位于 Swift 代码中: **`History.load()` 全表装饰、主线程搜索、图片/图标缓存无界、sessionLog 强引用模型、FNV 哈希重复计算**。C++ 仅在**哈希/指纹引擎**上有明确 ROI; 图片解码不应迁往 C++。

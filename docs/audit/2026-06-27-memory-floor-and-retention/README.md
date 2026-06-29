# Maccy 内存地板与滞留增长分析(2026-06-27)

**分析日期**: 2026-06-27
**数据来源**: 用户 2026-06-27 11:55 重抓的 6 份抽样文档(`docs/maccy.{footprint,heap,leaks,sample,vmmap.full,vmmap.summary}.txt`,**~6 小时运行时长**)+ 7-agent workflow 对**当前源码**(HEAD `4c8c7b6`)逐条验证
**分析方式**: 只读;7 个 agent(5 个杠杆验证 + 地板分析 + 综合),338K tokens,125 次工具调用
**上位文档**: [`../architecture-and-root-causes.md`](../architecture-and-root-causes.md)(单一权威架构与根因参考)。本组文档修正了 2026-06-25 系列(已删除)里被新数据推翻的判断(尤其"目标在 102MB 基本达成")。

## 本组文档解决什么

用户在 06-27 上传了一份 **~6 小时长运行**的内存抽样,问"能否压到 50–80 MB"。本组文档基于**实测数据 + 当前源码验证**给出诚实结论,并**修正 06-25 系列里已被新数据推翻的判断**(尤其"目标在 102MB 基本达成")。

## 文档索引

| 文件 | 内容 |
|------|------|
| [00-executive-summary.md](00-executive-summary.md) | **执行摘要**:50/80/85–100 的判定、06-25 以来发生了什么、一句话结论 |
| [01-dump-decomposition-06-27.md](01-dump-decomposition-06-27.md) | 135 MB dump 的完整分解(heap / vmmap / leaks 三表) |
| [02-framework-floor.md](02-framework-floor.md) | **不可压缩地板 ≈ 62 MB** 的构成与证明,以及"50 MB 数学上不可能"的算式 |
| [03-retention-root-cause.md](03-retention-root-cause.md) | **33 MB/6h 滞留增长**的根因:`mainContext` 是进程级累积器、从不 reset |
| [04-status-vs-master-plan.md](04-status-vs-master-plan.md) | **已完成 / 待办 / 继续做**:把 06-25 master plan 每一项映射到当前状态 |
| [05-action-plan.md](05-action-plan.md) | 去重后的优先级计划(含 MB 估算、重叠警告、执行序) |
| [06-gating-diagnostics.md](06-gating-diagnostics.md) | **MallocStackLogging 重抓协议**(3 时间点 + 变体),每个 MB 估算的前置 |

## 一句话结论

**135 MB 不是泄漏**(leaks 仅 19 KB),而是"`History.load()` 全表 fault + `mainContext` 从不回收 + 框架缓存随运行时长膨胀"的**结构性滞留**,叠在一个 **~62 MB 不可压缩框架地板**之上。

- **50 MB** —— 在地板之下,**数学上不可能**(窗口打开时)。
- **80 MB** —— 乐观天花板,需跑完整 roadmap + 视图树瘦身 + 小历史 + 短会话。
- **现实稳态目标:~85–100 MB**(从当前 135 MB 再榨 ~20–35 MB)。

**唯一被重新升为"关键前置"的动作**:开 `MallocStackLogging=1` 重抓(06-25 曾降级为"不再关键",06-27 数据重新把它升回来 —— 见 [06](06-gating-diagnostics.md))。

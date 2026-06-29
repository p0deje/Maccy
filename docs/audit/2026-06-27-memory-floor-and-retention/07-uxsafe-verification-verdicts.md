# UX-safe 杠杆复核结论(7-agent workflow,2026-06-27)

> 在用户的硬约束(**UX 体验 > 内存占用;不要冷启动——那不是优化**)下,
> 用 `mem27-uxsafe-verify` workflow(7 agent,282K token,128 次工具调用)逐项把
> [05-action-plan.md](05-action-plan.md) 的杠杆对 HEAD(`4c8c7b6`)重新核实。
> **本文件是"别再查这些"的定论**——每条都读真实代码 + grep 验证。

## 0. 一句话结论

代码侧**UX 安全的内存优化已基本榨干**。剩下唯一一个真·零风险杠杆是 **U1**
(已做,`c2a7c94`,CI run `28291627420`)。其余要么 ~0 MB(单例/COW/fault-out),
要么损 UX(重解码闪烁 / 搜索漏项 / 冷开重载),要么有正确性风险(中途取消事务)。
**要到 ~100 MB,只剩两条路:D1(用户 MSL 重抓)或 F1(独立可回收 blob 存储)。**

## 1. 逐项定论

| ID | 审计主张 | 复核结论 | 真实 MB | 为什么 |
|---|---|---|---:|---|
| **T1a** | History.init + AppDelegate 共 12 个常驻 `Defaults.updates` Task,句柄未存未取消 | **SKIP** | ~0 | 拥有者全是单例(History.shared、AppDelegate 经 @NSApplicationDelegateAdaptor)→ 永不 deinit → 存句柄+cancel 买不到 0 字节 always-live。key 各不相同(无重复订阅)。**冷启动门控它们会让设置开关静默失效——违反 UX 约束** |
| **T1b** | Clipboard.swift:224 `Task { await ingestor.ingest(request) }` copy storm | **SKIP** | ~0 | `BackgroundClipboardIngestor` 是 actor → ingest 已串行;cancel-and-replace 可能在事务中途取消并破坏 dedup 索引(BS-2 crash 类)。单例 owner,队列 ms 级排空 |
| **C5** | 接入 VisibleWindowLoader,`History.load()` 全表 → 可见窗口 | **GATED on D1;作为内存杠杆不 sound** | ~0(blob 不动) | 窗口化 `all` 只释放轻量 decorator 壳——SwiftData **无单行 fault-out**,17.5 MB `__DataStorage` blob 仍被 mainContext pin(全仓 grep 零 reset/refresh)。且窗口化会让搜索漏掉窗口外项(UX 退化)、scrollTarget/limitHistorySize/syncAllToStore/reconcile 全假设 `all` 完整。释放 blob 唯一路 = `context.reset()`(冷开重载,**被禁**)或 F1 |
| **naive C6** | 关窗时 `.previewHidden` nil 掉 previewImage | **SKIP——UX 退化** | ~0(实测) | **`DecodedImageCache` 是死代码**(`setImage`/`image(for:)` 零调用者,只有 evict/purgeAll 被调)→ `preview(for:max:)` 不缓存 → nil 掉 previewImage 使重开变成完整重解码 → 灰色 ProgressView 闪烁,直接退化 `463feb1` 刚做的 snap-open+淡入。heap 只有 96 NSImage/153 KB,预览位图本就不是贡献者 |
| **Hunt#2** | scrollOut 时清 `imageDataCache`(原始 blob ~1MB/图) | **SKIP** | ~0 | `imageDataCache = item.imageData` 与 @Model backing **Data-COW 共享** + 读取它会把 blob **fault 进 mainContext**(永不 fault-out)→ 清 decorator 引用释放 ~0 字节。与 C5 同根因 |
| **U1** | ListItemView.swift:141 `.help(help ?? "")` 每行无条件 | **DONE `c2a7c94`** | ~0.05–0.10 | HistoryItemView/FooterItemView/PasteStackItemView 从不传 `help:` → 每行实例化空 `HelpView` AG 节点(dump 里 1280B×101)。按非空 key 门控 → 纯垃圾清除 + 减 AG churn(内存+卡顿双赢),零 UX 变化。**审计"KeyboardShortcutView 每行"标题是错的**——它被 `if !shortcuts.isEmpty` 正确门控,只有 pin 行显示 |

## 2. 关键反直觉发现

- **`DecodedImageCache`(C1 脚手架)整体是 vestigial**:NSCache 32/64MiB 建好了,
  但 `setImage`/`image(for:)` 全仓零调用者,只有 `evict`/`purgeAll` 被调。它从没存过
  任何预览位图。→ C1-C3 的"decoded-image working set bounded to visible window"目标
  实际未生效(预览位图是 per-decorator 永久持有,直到 scrollOut/invalidate)。
  - **C6-done-right**(可选,sound):把 `startPreviewGeneration` 解码结果存进
    DecodedImageCache,`asyncGetPreviewImage` 先查缓存 → 重开 = 缓存命中(无重解码闪烁),
    `.previewHidden`/`.scrollOut` 的 evict 才有意义,预览位图被 bound 到 NSCache LRU。
    但**触碰刚打磨好的预览路径**,价值实测 ~0(当前 few 位图),按 UX>内存 暂不动。

- **审计"无界缓存杠杆关闭"**复核仍成立(sessionLog + 4 cache 全 bounded,heap 96 NSImage)。

- **SwiftData 无单行 fault-out** 是几乎所有 blob 回收问题的硬约束,复核确认全仓零
  reset/refresh 路径(只 newBackgroundContext 创建点)。

## 3. 到 100 MB 的分叉(真实设计/权衡)

135 MB 分解:`~62 MB` 框架地板(不可动)+ `17.5 MB` SwiftData blob(仅 F1 可回收)+
`41.7 MB` non-object 盲区(INFERRED ~66% AG,**需 D1 实测归因**)+ `~14 MB` Swift/SwiftUI/App 结构。

| 路径 | 动作 | UX | 工作量 | 门槛 |
|---|---|---|---|---|
| **D1** | 用户在 macOS 跑 MallocStackLogging(3 时间点 + 滚览实验,见 [06](06-gating-diagnostics.md)) | 无(零代码) | ~30 min 用户操作 | 归因 41.7 MB 盲区 + 定论 blob 可回收性,决定 C5 够不够还是必须 F1 |
| **F1** | 大内容移出 SwiftData `_KKMDBackingData`,独立 id-key 可回收存储(类 ThumbnailCache 磁盘 LRU) | **安全**(按需 re-fault,非冷启动) | 大(schema 迁移 + BlobStore + 改 HistoryItem.imageData/contents 读写 + ingest/copy 路径;碰 [[swiftdata-pending-vs-saved-predicate]]) | 唯一 sound 的逐项 blob 回收路径;re-fault on demand = 不冷启动 |

**建议**:D1 先做(最高 ROI、零代码、解锁所有数字);D1 若证 blob 被 pin 不可窗口化回收 → F1。

## 4. 本次落地

- `c2a7c94 perf(mem27-U1): gate ListItemView .help ...` —— CI run `28291627420`。
- 记忆:`mem27-uxsafe-verdicts`(定论)+ `roadmap-current-position` / `measured-memory-profile-2026-06-24` 更新。
- 未触碰:预览路径(C6-done-right sound 但触碰刚发布的预览,按 UX>内存 暂缓)、
  C5/F1( gated on D1 / 大工程)、T1a/T1b/Hunt#2(0 MB 或风险)。

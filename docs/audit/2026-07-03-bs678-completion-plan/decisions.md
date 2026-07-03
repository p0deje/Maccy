# ADR 集 — BS-6/7/8 完成决策(2026-07-03)

> 4 个真实决策叉点。会话中向用户提问,60s 未回应,代为决定如下。
> **用户回归后请优先复核。** 推翻 ADR = 改本文件 + 调整 README 序列中对应小步;若对应小步已实施,需 revert。

---

## ADR-001:`DecodedImageCache` — 删除(DELETE)【2026-07-03 修订】

> **✅ 2026-07-03 修订,2026-07-04 用户确认:DELETE。** 原决策"接通"改为**删除**。深入分析发现:接通(保留 32 项可重用,countLimit=32/64MiB)会**增加**内存 —— 对比当前已"可视区限界"的实现(per-decorator `previewImage` + scrollOut `releaseTransientImages` + BS-3 预览封顶),接通只为换**边际 re-show 收益**(scrollBack 时少一次解码)。这与 06-27 实测内存权威("预览位图非杠杆"、"DecodedImageCache 可选/低价值")**直接冲突**。删除还避免触及**最高风险的预览渲染路径**(无本地工具链验证,UI 测试未必覆盖 → 假绿风险)。当前实现已限界于可视区,删除是更严谨的选择。下接的"原接通理由"保留作历史参考。

> —— 原 ADR-001(接通)历史参考:——

**状态**:代为决定(用户离席)。**语境**:BS-6 6.2/6.4。

**决策**:接通 `DecodedImageCache` —— 预览解码位图经 NSCache(`setImage` 于 decode 后,`image(for:)` 于读侧),使 spec 的 headline 目标"decoded-image working set bounded to visible window"真正落地,并消除死代码。

**背景**:
- `DecodedImageCache`(`MemoryGovernance.swift:62-91`)已建(countLimit=32 / totalCostLimit=64MiB),但 `setImage`/`image(for:)` **零调用方**,仅 `evict`/`purgeAll` 被调。当前是"留着不用"的最坏状态:广告一个未兑现的限界保证。
- 冻结 spec(06-14 step-6)把它列为 headline 交付物。
- 更新的 06-27 内存权威(7-agent 实测)判定:预览位图**不是**内存杠杆(F1 image-heavy-only 才是;框架底 ~62MB),`DecodedImageCache` 收益 ~1-2MB,`C6-done-right` 标 "sound-but-preview-touching, optional"。

**考虑的替代**:
- (B)删除 + 记偏差(接受 06-27)。更简单、无新测试、但正式放弃冻结 spec 的 headline 交付物。

**理由**:用户的明确优先级是"**严格按照文档** / 补全缺失 / 尽可能做到最完美、最严谨"——这些在 BS-6 上指向**交付 spec**而非放弃。接通以**使用**的方式消除死代码,~1-2MB 内存收益虽小但真实,且预览路径风险由 TDD 闸门(先 `DecodedImageCacheTests`)与既有 `ImageDecodePerformanceTests`/预览 UI 测试覆盖。06-27 的 demotion 针对**内存 ROI**,非正确性;在 spec-完成目标下接通成立。

**后果**:
- 触及预览渲染路径(项目最高 blast-radius 面,per mem27)。缓解:failing 测试先行 + 既有预览测试。
- 新增 `DecodedImageCacheTests`(淘汰/evict/purgeAll/读 API)。
- 偏差记录:在 step-6 注明"接通而非遵循 06-27 demotion;内存 ROI 低,spec-完成为主"。

**推翻信号**:若用户优先 06-27 实测内存判定 → 改 (B) 删除(删 `MemoryGovernance.swift:62-91` + 两处 `evict` 调用 + `purgeAll` 调用 + `.previewHidden` case + header 注释,记偏差)。

---

## ADR-002:8.5 fingerprint 回填 — 惰性 signal-to-actor(后台 context 单事务)

**状态**:代为决定。**语境**:BS-8 8.5。

**决策**:实现惰性回填。main 读侧(ContentSignature/Index 构建)发现 nil 列大行(≥16KiB)时,收集其 `persistentID` 并向 ingest actor 投递回填任务;ingest actor 在**后台 context** 单事务内 `fingerprint = nil` 守卫下写入并 `save()`。幂等(仅当仍 nil)、`save()` 先于任何 predicate 再读(SwiftData pending-vs-saved)、每行一次性(失败行不重试)。

**背景**(确认的缺口):
- `HistoryItemContent.fingerprint` 列(`:33`)仅 `init`(`:41`)为新行赋值;全仓 grep `.fingerprint =` **无任何回写旧 nil 行**。
- 读路径:`ContentSignature`(`HistoryItemEngine.swift:129-130`)回退**重 hash**;`ContentIndex`(`:155`)直接带 nil → `dataLikelyEqual` 落全 `==`。即**老用户历史的去重退化为全字节比较**(每 contains 检查),热路径。
- spec 8.5 原文:"首次 add/load 命中 nil 时,在后台 context 单事务内回填该行的 fingerprint(惰性回填,不全表扫)"。

**考虑的替代**:
- (B)冷开批量预填。概念简单,但首启可能重 hash 数百 MB + "PersistentIdentifier remapped to temporary identifier during save" 中断风险(会杀掉整个测试类)。
- (C)延后记偏差。留正确性退化。

**理由**:这是真实正确性退化("补全缺失" + 正确性优先),且 spec 明确开惰性后台回填方子。"strictly follow docs" = 本决策。跨域写回是难点(@Model 不能 main 内联写跨后台)——signal-to-actor 尊重两域隔离。

**后果/风险**:
- 跨域:ContentSignature/Index 在 main 构建(读 mainContext fault);回填必须 signal 到 ingest actor 后台 context。后台 save 后 mainContext 旧 nil fault **不会自动刷新** —— 需在 reconcile/consume 后让 mainContext 见到新值(_REFRESH 策略:或 mainContext.refresh(:)、或 reconcile 路径重新 fetch、或接受下次构建才生效)。**实现时需选定 refresh 策略并测**。
- 写风暴:每 copy 至多回填数行(受 copy 命中数限),可控;冷开可借 reconcile 尾队列节流。
- SwiftData 坑:回填 save 必须先于同流后续 predicate delete;批量化以避免 remap 中断。
- 测试:`FingerprintMigrationTests`(nil→回填非 nil、与新建行 dedup-equal、幂等、<16KiB 不动)。

**推翻信号**:若用户选 (C) 延后(因跨域复杂度)→ 记偏差,不实施;`FingerprintMigrationTests` 改为 documenting-current-nil 行为。

---

## ADR-003:7.13 obs 收敛 — computed-property mirror,TDD 闸门(失败回退 AsyncStream)

**状态**:代为决定。**语境**:BS-7 7.13(spec 唯一行为变更)。

**决策**:先写 `ObservationMirrorTests`(1ms 内 100 次突变,断言最终渲染态 = `@Model` 最终值)。若 `@Observable` 计算属性向 `@Model` 字段的访问**能在 SwiftUI 视图注册观察** → 删 `synchronizeItemPin/Title` 递归 + 存储属性,改 computed mirror(`var title: String { item.title }`);若**不能** → 回退 `AsyncStream`(`var titleChanges: AsyncStream<String>`,reconcile 路径推 continuation)。`AppDelegate.synchronizeMenuIconText`(NSStatusItem 非 SwiftUI 视图)保留一次性 `withObservationTracking` 无递归。

**背景**:
- `HistoryItemDecorator.swift:416-454`(`synchronizeItemPin/Title`)+ `AppDelegate.swift:245-259`(`synchronizeMenuIconText`)仍用递归 `withObservationTracking` + `DispatchQueue.main.async`/`Task{@MainActor}` 自重装。
- 非正确性 bug(onChange 下一 runloop 触发、`isInvalidated` 守卫无环),但 spec 要求替换为 mirror/AsyncStream。
- **关键风险**:递归 relay 可能正是为绕过"`@Observable` 计算属性不向 `@Model` 注册观察"的边缘情形而存在 —— 必须 TDD 闸门。

**考虑的替代**:
- (B)直接 AsyncStream。确定顺序,但视图仍需 `@State` mirror,只是搬移问题。
- (C)延后记偏差。BS-7 最扎实,7.13 非 bug。

**理由**:spec 要求 + 用户"最严谨" → TDD 闸门下的 mirror 是最小且可验证路径;失败有 AsyncStream 回退。不盲改(先证传播成立)。

**后果/风险**:
- 若 mirror 不传播而未测出 → 弹窗标题/快捷键静默停更。缓解:`ObservationMirrorTests` 是 gate;CI 必过才合并。
- `KeyShortcut.create` 在 computed getter 内读 `Defaults[.pasteByDefault]` → 每次 layout 读(cheap,不缓存)。
- AppDelegate 侧 NSStatusItem 非 SwiftUI,mirror 不适用 → 保留一次性重注册(无递归 hop)。

**推翻信号**:若用户选 (C) 延后 → 记偏差(7.13 skip,BS-7 仍 12✓),不做 mirror/AsyncStream,仅补 `ObservationMirrorTests` documenting-current 行为或跳过。

---

## ADR-004:perf 闸门 — perf-as-class 落 MaccyTests,不建独立 `MaccyPerformanceTests` target

**状态**:代为决定。**语境**:BS-6 6.12 / BS-5 G-search / spec B §4。

**决策**:G-memory/G-search 等性能闸门作为 `PerformanceTestCase` 的**子类**落在 `MaccyTests/`(既有 `ImageDecodePerformanceTests`/`TextSearchPerformanceTests`/`HistoryItemPerformanceTests` 同模式),CI 经 `-only-testing:MaccyTests/<Class>` 分片。**不**新建 `MaccyPerformanceTests` PBXNativeTarget。在 step-6/step-7/step-8 + B-test-strategy.md 记 spec reconciliation。

**背景**:
- 冻结 spec B §4 设想独立 `MaccyPerformanceTests` target;从未创建。
- **实测**:perf 测试已是 MaccyTests 中的 `PerformanceTestCase` 子类(de-facto 权威),3 个既有类跑通。
- 无本地工具链:改 `project.pbxproj` 加 target + xctestplan + scheme 仅 CI 验证,风险高、收益低。

**考虑的替代**:
- (B)严格按 spec 建 target。触 project 文件,无本地工具链下高风险。

**理由**:perf-as-class 是工作现实;既有基础设施(`PerformanceTestCase` @MainActor 基类、in-memory store、`MainThreadProbe`、`PerfHistoryFactory`)可免费复用。spec reconciliation 比 target 创建更诚实且低风险。

**后果**:
- 新 perf 测试子类化 `PerformanceTestCase` 即得 in-memory store + `Defaults[.size]=200` + `MainThreadProbe` 接线。
- 需更新 B-test-strategy.md §4 的 "独立 target" 表述(记 reconciliation)。
- 若未来需要硬 CI-shard 边界再建 target。

**推翻信号**:若有硬 CI-shard 隔离需求 → 改 (B),加 target+xctestplan+scheme(CI 验证)。

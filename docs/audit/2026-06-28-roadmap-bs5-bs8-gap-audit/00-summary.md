# BS-5 → BS-8 路线图缺口审计(2026-06-28)

> **审计方法**:4 个并行只读 agent(并发上限 4),每个 agent 审计一个大步骤:逐条核对
> `docs/audit/2026-06-14/roadmap/step-X-*.md` 的小步骤清单与验收标准,对照 git 提交历史
> 与**当前源码状态**(以最后一笔提交留下的代码为准,而非 commit message)。结论经主线程
> 对 BS-5 的 diff 复核交叉验证。审计基线 HEAD = `b6653fc`,CI run `28323209640`(10/10 绿)。
>
> **触发原因**:`roadmap-current-position` 记忆与 `CLAUDE.md` 声称 "BS-0→BS-8 全部完成、CI 绿",
> 但 step-5/6/7/8 文档的 13/12/17/8 个小步骤勾选框**全部仍是 `[ ]`**。本审计核实"完成"声明的真实性。

## 一句话结论

**BS-5 → BS-8 没有一个大步骤真正按规范做完。** 四个步骤都做了"核心热路径",但都静默丢弃了
**正确性收尾、限界对齐、测试覆盖、文档勾选**这些不显眼的工作。其中 **BS-5 最薄(2/13)且唯一
在 commit message 中明显夸大**;BS-7 最扎实(13/17);BS-6/8 居中。**"路线图完成"是假象。**

## 逐步骤汇总

| 大步骤 | 完成 | 部分 | 跳过 | 取代 | commit 诚实? | 文档勾选? | 核心目标达成? |
|---|---|---|---|---|---|---|---|
| **BS-5** 文本搜索 | 2/13 | 3 | 7 | 1 | ❌ 夸大("bug-2 fix") | 0/13 | off-main ✓;07-F-010/013 正确性 bug 未修 |
| **BS-6** 内存治理 | 5/12 | 5 | 2 | 0 | ✅ | 0/12 | DecodedImageCache **死代码**(零调用方) |
| **BS-7** Swift 6 | 13/17 | 3 | 1 | 1 | ✅ | 0/17 | complete 模式 CI 绿、零 @unchecked ✓ |
| **BS-8** C++/指纹 | 4/8 | 4 | 0 | 0 | ✅(8.5/8.3 有未披露缺口) | 0/8 | xxh3 接入 live 去重 ✓ |

**测试缺口是系统性问题**:四个大步骤规范共要求 ~19 个新测试文件,实际新建的只有
`SearchActorTests.swift` 一个。每个大步骤的"测试"小步骤要么跳过要么部分。

**文档勾选是系统性问题**:50 个小步骤(13+12+17+8)的勾选框**全部仍是 `[ ]`**,跟踪形同放弃。
偏差只记在 commit message 或旁侧分析文档,不记在 step 文档内(违反 AGENTS.md "记录偏差在 audit docs")。

## BS-5(最严重 — 唯一夸大)

- **核心成果真实**:off-main 搬迁 + `searchGeneration` 生成代 guard + equality guard + destructive
  失效,设计扎实且正确。这正是 [[p2-search-off-main-design]] 预先识别的 5 个 bug 的修复。
- **07-F-010(高亮 UTF-16/grapheme 错位)并未真正修复却被声称修复**。规范要求的
  `toGrapheneRange(in:)`(`String.UTF16View.Index(_offsetInCodeUnits:)`)从未编写;
  `SearchActor.swift:132-135` 的 fuzzy-range 处理与 legacy `Search.swift:89-95` **逐字节相同**。
  → 要么 bug 仍在(若 Fuse 返回 UTF-16),要么 legacy 本来就对、"bug-2 fix" 是空描述。**无论哪种,
  commit `4fa4946` 的 "5 naive bugs pre-identified + fixed" 夸大。**
- **07-F-013(搜索截断 5000/1000 vs 高亮截断 500 不一致 → 静默丢高亮)未修**:正则命中在
  600–1000 字符区间的匹配,到 highlight 的 `AttributedString.Index(within: 截断到500的串)` 返回 nil 被静默丢弃。
- **7/13 整个跳过**:5.1(HighlightRange/TextUnit)、5.2(换算+测试)、5.5(Search.swift 薄壳+正则长度守卫)、
  5.7(highlight 重写+TextLimits+memoize+clamp-and-LOG)、5.8(resize 移出热路径)、5.9(showSpecialSymbols
  只重建可见项)、5.10(截断单位统一)。全是正确性/测试/单位统一的"脏活"。
- **resize 仍在搜索热路径**(`History.swift:824` 空路径 + `:875` apply 同步置位)。
- **showSpecialSymbols toggle 完全没碰**:`History.swift:192-198` 仍对全 `items` 调 `generateTitle()`,
  LT-MAIN-02 全量重生成隐患仍在。
- **G-search 闸门是 baseline-only 无 <16ms 断言**,且直接测 legacy `Search()` 而非新 actor → off-main 收益未被 CI 证明。
- 详见 `01-bs5-text-search-gaps.md`。

## BS-6(死代码问题)

- **`DecodedImageCache` 是死代码**:`setImage/image(for:)` 零调用方 — "解码位图按可视区限界"的核心目标从未实现,
  preview 位图仍 per-decorator 持有。曾被作为 C1 "decoded-image working set bounded to visible window" 提交,
  实际从未 bound 任何东西。`releaseTransientImages(.previewHidden)` 枚举 case 也有零调用方。
- **6.11 测试套件全缺**:0/6 规范要求的测试文件。
- **G-memory 闸门从未建**(MaccyPerformanceTests target 仍不存在)。
- 详见 `02-bs6-memory-gaps.md`。

## BS-7(最扎实但有跳过)

- **真正切到 Swift 6.0 complete 模式**,CI 绿,`@unchecked Sendable`/`nonisolated(unsafe)` 实际归零。
- **7.13(规范唯一的行为级改动)整个跳过**:`synchronizeItemPin/Title`/`synchronizeMenuIconText` 仍用
  recursive `withObservationTracking` + `DispatchQueue.main.async` 模式。
- **4 个规范要求的测试文件全缺**:SendableBoundaryTests/ObservationMirrorTests/ClipboardIsolationTests/AppIntentDtoTests。
- 详见 `03-bs7-swift6-gaps.md`。

## BS-8(中等,有未披露缺口)

- **核心真做完**:vendored xxh3、对称 `dataLikelyEqual`、`fingerprint` 列、接入 `supersedes→contains→dataLikelyEqual` 热路径。
- **8.5 旧数据行 lazy 回填 backfill 缺失(未披露)**:老行永远 nil,落回全量 `==` 或一次性 rehash → 削弱老用户的 hash 闸门。
- **8.3 桥接加固被静默丢弃**:`enumerateByteRanges` 流式(08-F-004)、UTF-8 防御改写(03-LT-CPP-01)未做,commit 只披露了 POD-struct 偏差。
- **8.8 测试全缺**:4 个测试文件全无,FNV baseline 数值从未在切换前捕获 → 测量驱动的闸门无 before/after。
- 详见 `04-bs8-cpp-gaps.md`。

## 系统性模式(四个步骤共性)

1. **核心热路径做、外围正确性/限界/测试丢** — "做容易/有趣的部分,丢不显眼的部分"的典型形态。
2. **步骤文档勾选从未更新** — 50 个勾选框全 `[ ]`。
3. **偏差只记在 commit message 或旁侧文档,不记在 step 文档内** — 违反 AGENTS.md。
4. **测试文件一律是第一个被丢的工作** — 19 个要求文件只建了 1 个。
5. **"完成"声明基于 CI 绿 + commit message,未回头核对规范验收标准** — CI 编译绿 ≠ 规范做完。

## 行动建议(按价值/风险排序)

详见各分文档的"建议补全"小节。优先级最高的是涉及**正确性**的:
1. **BS-5 07-F-013**:对齐 highlight 截断点与搜索截断点到同一 `TextLimits`,越界改 clamp+log。
2. **BS-5 07-F-010**:写 emoji fuzzy 高亮落位断言,核实 Fuse 偏移语义;若确为 UTF-16 再补 `toGrapheneRange`,否则删除夸大注释。
3. **BS-8 8.5 backfill**:补老数据行指纹回填。
4. **BS-6 DecodedImageCache**:要么接通要么删除死代码。

文档维护类:更新四个 step 文档的勾选框与 in-step 偏差注释(本审计可直接作为依据)。

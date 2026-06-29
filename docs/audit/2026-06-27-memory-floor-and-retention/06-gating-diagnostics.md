# 门控诊断:MallocStackLogging 重抓协议

> 这是**唯一被重新升为"关键前置"的动作**(06-25 降级,06-27 升回)。在它之前,本组文档每个 MB 估算都是推断,地板带 ±10 MB 不确定性。
> 用户需在 macOS 上跑(本机无工具链,见 `CLAUDE.md`)。

## 1. 为什么必须重抓(三个待解问题)

1. **归因 41.7 MB `non-object` 盲区** —— 当前只能按 zone 相关性推断(~66% 是 AG)。MSL 把它变成**真实调用点归因**,确认是 AG 视图图、CoreText/CoreSVG 缓存、还是意外的 Data 引用路径。
2. **分解"地板 62 MB vs 单项成本 vs 6h 斜率"** —— 现在只有 2 分钟(102 MB)和 6 小时(135 MB)两点,**无空历史/无窗口关闭基线**。地板 62 MB 的不确定性 ~±10 MB。
3. **定论"17.5 MB blob 能不能回收"** —— 决定 **C5(窗口化)够不够** 还是 **必须 F1(独立 blob 存储)**。这是整个行动计划的分叉点。

## 2. 抓取协议(5 组)

### 组 A:刚启动 / 空历史 / 窗口关闭(地板基线)
```sh
# 用 enable-testing 内存库 或 清空 DB 启动;弹窗保持关闭(仅菜单栏)
MallocStackLogging=1 /Applications/Maccy.app/Contents/MacOS/Maccy &
PID=$!
# 等 ~30s 稳定
leaks $PID > /tmp/maccy/A.leaks.txt
heap $PID > /tmp/maccy/A.heap.txt
vmmap --summary $PID > /tmp/maccy/A.vmmap.summary.txt
vmmap $PID > /tmp/maccy/A.vmmap.full.txt
malloc_history $PID --eventsByStack > /tmp/maccy/A.malloc_history.txt
footprint $PID > /tmp/maccy/A.footprint.txt
```
**要回答**:空历史 + 窗口关时的 phys_footprint = 真地板。预期 ~50–60 MB(若 >70 MB,说明有常驻内容/缓存预载,需查)。

### 组 B:窗口打开 / ~20 项(单项成本)
打开弹窗、滚动到 ~20 项可见、停手等待 30s,同上 6 个命令(前缀 `B.`)。
**要回答**:每项增量成本(内容 blob + AG 行图 + decorator)。`(B - A) / 20` = 每项 MB。

### 组 C:6 小时稳态(滞留斜率)
正常使用 6 小时后,同上 6 个命令(前缀 `C.`)。**这就是当前那份 dump 的对照点,但带 MSL。**
**要回答**:6h 滞留 = C - B - (项数增量)。确认 33 MB 斜率的归因(blob fault 累积 vs CoreText 缓存 vs AG 碎片)。

### 组 D:窗口关闭 vs 打开对比
窗口打开使用后**关闭窗口**(仅菜单栏),抓一份(前缀 `D.closed`)。
**要回答**:AG 图 + IOSurface 窗口缓冲在关窗后是否回落。若回落 → 关窗模式可逼近 50–60 MB(菜单栏形态)。

### 组 E:滚览实验(blob 累积判别)
instruments Allocations 或连续抓 heap:从头滚到底,每滚 50 项抓一次 `heap | grep __DataStorage`,滚完等待 60s 再抓。
**要回答**:`__DataStorage` resident 是否**单调增长不回落** → 确认 row-cache 累积(`Clipboard.copy`/渲染 fault),量化 per-scroll 增量。若回落 → blob 不是被 row-cache pin 住,C5 会更有效。

## 3. 关键判读

| 现象 | 结论 | 对计划的影响 |
|---|---|---|
| A 组 phys_footprint ≥ 70 MB | 有预载内容/缓存,地板更高 | 80 MB 更难;先查谁预载 |
| E 组 `__DataStorage` 单调涨不回落 | blob 被 mainContext row-cache pin 住 | **C5 不够,必须 F1** 独立 blob 存储 |
| E 组 `__DataStorage` 滚出可视区后回落 | blob 可随视图回收 | **C5 + C7 足够**,F1 可延后 |
| MSL 显示 `non-object` 主导是 AG | U1(视图树瘦身)有效 | U1 提到前面 |
| MSL 显示 `non-object` 主导是 CoreText/SVG 缓存 | 框架缓存,部分可 purge | U1 无效;靠内存压力 purge + 接受 ~10 MB 框架缓存 |
| MSL 显示意外 Data 引用路径 | 找到隐藏的 blob 持有者 | 直接修,可能省更多 |

## 4. 给执行者的提醒

- **MSL 开销大**(每次 malloc 记栈),仅在诊断构建开,不要进发布。
- `malloc_history` 需要 MSL 启动的进程;冷启时带 `MallocStackLogging=1`。
- 抓完把 `/tmp/maccy/` 的 5 组文件放回 `docs/audit/2026-06-27-memory-floor-and-retention/captures/`(或新目录),更新 [01](01-dump-decomposition-06-27.md) 的数字。
- 抓取后,据 [05](05-action-plan.md) §5 的分叉决定 C5 还是 F1 先做。

## 5. 若无法跑 MSL 的退路

若 MSL 因故跑不了,退而求其次:
- 组 A/B/C/D 不带 MSL 也能抓(只少了 malloc_history)——至少能定地板 + 单项 + 斜率 + 关窗回落。
- 组 E 滚览实验 + near-empty-store 抓取能判别 blob 是否被 pin(见 [03](03-retention-root-cause.md) §6)。
- 这样能砍掉 ~一半不确定性(地板 + blob 可回收性),但 `non-object` 内部归因仍缺。

**底线**:即便只做组 A+B+C+D+E(无 MSL),也远好于现在的"两点 + 推断"。**至少把地板和 blob 可回收性这两个分叉点定下来**,行动计划才能从推断落地到实测。

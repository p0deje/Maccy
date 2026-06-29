# BS-8 C++ 扩展(xxh3 + 指纹持久化)— 缺口详审计(2026-06-28)

> 规范:`docs/audit/2026-06-14/roadmap/step-8-cpp.md`(8 小步 8.1–8.8)。
> 相关提交:`2ae210f`(test bs8.1 baseline)、`bd1faa8`(feat bs8.2 vendor xxHash + xxh3_64 additive)、`c6821c4`(perf bs8.3-8.6 xxh3 + 指纹列 + 对称 dataLikelyEqual)、`1f25102`(fix bs8 drop redundant nil)。
> 当前源码 HEAD `b6653fc`。CI run `28294966251`(1f25102)= 10/10 success。

## 总览

- **完成**:4(8.1、8.2、8.4、8.6)
- **部分**:4(8.3、8.5、8.7、8.8)
- **跳过**:0
- **commit 诚实度**:✅ 大体诚实(c6821c4 记了 UInt64-vs-MaccyFingerprint 偏差 + "8.8 refinement pending"),**但 8.5 backfill 缺失与 8.3 加固丢弃未披露**
- **文档勾选**:0/8
- **核心目标达成**:✅ xxh3 接入 live 去重热路径(`HistoryItem.supersedes → HistoryItemEngine.contains → ContentIndex.contains → dataLikelyEqual → xxh3`),非仅添加

**核心真做完**,但有几个**未披露**的正确性/完整性缺口。

## 逐小步

### 8.1 基线 benchmark(pre-xxh3)— ✅ 完成
`MaccyTests/HistoryItemPerformanceTests.swift:30-60` 加了两个 benchmark:`testMultiSameTypeLhsRehashBenchmark`(20 same-type/same-size/distinct-content lhs,暴露 08-F-001)与 `testFingerprintThroughputBenchmark`(1MB+10MB,记 GB/s)。无 .baseline(规范正确 — 算法未换)。
**遗留**:rehash-benchmark 注释现过时(post-8.6 称 lhsFingerprint 默认 nil 重 hash,但 8.6 传列值);FNV baseline 数值**从未在切换前捕获** → 8.8 的 before/after 量化丢失。

### 8.2 vendor xxHash + xxh3_64(FNV 保留)— ✅ 完成
`Processor/third_party/xxhash.h` v0.8.3(BSD-2)+ LICENSE;`ClipboardByteProcessor.cpp:105-107` xxh3_64 包 `XXH3_64bits_withSeed`;`XXH_INLINE_ALL` + `#pragma diagnostic ignored` 干净 CI 日志;`fnv1a64` 仅加 noexcept,算法逐字节不变(git diff 6528bd8 HEAD 确认)。**additive only**(此 commit 桥仍走 fnv1a64)。诚实 commit。

### 8.3 ObjC++ 桥接加固 + 新桥方法 — ⚠️ 部分(多子项丢弃,部分未披露)
- ✅ 桥从 fnv1a64 改走 xxh3_64(`MaccyTextProcessor.mm:28-32`,c6821c4)。
- ⚠️ POD-struct 方法未加(保留 UInt64 — **已记录**偏差)。
- ❌ **empty-data guard / DEBUG assert 未加**(论证 xxh3 不需要)— 未披露。
- ❌ **非连续 NSData 流式(`enumerateByteRanges`+`XXH3_64bits_update`,08-F-004)未做**(仍 `data.bytes` 直接传,.mm:29)— **未披露**。
- ❌ **UTF-8 防御改写(`index+width>limit`→`width>limit-index`,03-LT-CPP-01)未做**(`ClipboardByteProcessor.cpp:66` 不变)— **未披露**。
- ❌ 旧方法未 `__attribute__((deprecated))`。

### 8.4 dataLikelyEqual → 对称(无默认参数陷阱)— ✅ 完成
`ClipboardDataProcessor.swift:33-56` 对称、双指纹必填(无默认参数)→ 08-F-009 默认参数陷阱关闭、lhs 不再重 hash。对比 baseline 6528bd8:死掉的 2 参 `Data?/Data?` 重载 + 默认参数版(`lhsFingerprint:UInt64?=nil`)都已删。**已记录**偏差:用 UInt64? 而非 MaccyFingerprint DTO;size gate 用 `lhs.count==rhs.count` 而非 `lhsFp.size`(功能等价)。

### 8.5 HistoryItemContent.fingerprint 列 + SwiftData 迁移 — ⚠️ 部分(backfill 缺失,未披露)
- ✅ `HistoryItemContent.swift:23` `var fingerprint: UInt64?` 列(可空,lightweight 迁移,无 VersionedSchema)。
- ✅ init 为新行算指纹(:31);固定 seed `kMaccyHashSeed=0`(.mm:10,跨启动稳定)。
- ❌ **lazy 回填 backfill 缺失**:无代码为旧 nil 行写列。旧迁移行**永远 nil** → 读时落回全量 `==`(lhs in ContentIndex)或一次性 rehash(duplicateSignature)。**削弱老用户历史的 hash 闸门。**
- **commit 声称** "old rows migrate as nil" / "fallback to one-time re-hash",**但未披露规范要求的 write-back backfill 缺失。**

### 8.6 ContentSignature/ContentIndex 读持久列 + 双向 DTO — ✅ 完成
`HistoryItemEngine.swift:104-111` ContentSignature 读 `列 ?? fingerprintIfLarge` fallback;:117/:131 ContentIndex 存 `(Data, UInt64?)`;:147-159 `contains` 传双指纹给 dataLikelyEqual。lhs 不再每比较重 hash(读列)— 08-F-001 热路径修复达成。**已记录**偏差:UInt64? 而非 MaccyFingerprint?。live 路径确认接入(HistoryItem.swift:107)。

### 8.7 残留清理 + Sendable +(可选)modulemap — ⚠️ 部分
- ✅ XXH_INLINE_ALL + 线程安全(纯函数,immutable seed)— cpp 注释(承自 8.2)。
- ❌ **modulemap 未建**(规范标可选 — "若不做,记入 BS-7 todo");grep step-7-swift6.md **无此延后记录**。
- ❌ 旧 `+fingerprintForData:` 未 `__attribute__((deprecated))`(`MaccyTextProcessor.h:9`)。
- ❌ 无 `@retroactive Sendable` 扩展(因用 UInt64 而无关,但规范列了)。

### 8.8 测试 + 验证 + baseline 设定 — ⚠️ 部分(测试全缺)
- ✅ CI 编译闸门过(run `28294966251` 10/10;c6821c4 因 SwiftLint `implicit_optional_initialization`(= nil)失败,1f25102 修)。
- ❌ **4 个专用测试文件全缺**:`FingerprintMigrationTests`、`FingerprintSymmetryTests`、`DataLikelyEqualContractTests`、`Xxh3ThroughputTests`(grep 确认 0 命中)。
- ❌ 无 `.baseline` measureMetrics;无 `xxh3>=3x FNV` 断言;无 `bytesHashed~=0` 断言;无迁移正确性测试;无对称性测试。
- 8.1 benchmark 在 CI 跑了但**无量化**(无 baseline、无断言),且现测的是**新**路径(FNV baseline 丢失)。
- c6821c4 明说 "8.8 refinement pending" — 延后非静默丢,但规范验收标准未满足。

## 主要缺口

1. **8.5 backfill 缺失(未披露)**:老用户历史的 hash 闸门被削弱,旧行永远 nil 落回全量 `==` / 一次性 rehash。这是**正确性退化**,且 commit 未披露。
2. **8.3 桥接加固丢弃(未披露)**:08-F-004 流式、03-LT-CPP-01 UTF-8 防御改写、empty guard 均未做,commit 只披露了 POD-struct 偏差。
3. **8.8 测试全缺 + baseline 丢失**:4 测试文件 0 个;FNV baseline 数值切换前未捕获 → 测量驱动的闸门无 before/after,无法证明 "3-5× throughput"。
4. **8.7 modulemap 延后未记录**:规范要求记入 BS-7 todo,grep 无。
5. **过程缺口**:step-8 勾选框全 `[ ]`;偏差只在 commit message,不在 audit docs;`15-progress-and-resume.md:61` 仍标 BS-8 "未做"(过时);8.1 benchmark 注释过时。

## 建议补全(按价值/风险排序)

1. **8.5 backfill**(最高,正确性):在首次 add/load 命中 nil 列时写回指纹。否则老用户去重退化为全量比较。
2. **8.8 测试 + baseline**:补 `FingerprintMigrationTests`(迁移+backfill 正确性)、`FingerprintSymmetryTests`、`DataLikelyEqualContractTests`、`Xxh3ThroughputTests`(+ `.baseline` + `xxh3>=3x` 断言 + `bytesHashed~=0`)。
3. **8.3 UTF-8 防御改写**(03-LT-CPP-01):`index+width>limit`→`width>limit-index` — 防御性,改动小。
4. **8.7**:旧方法加 `__attribute__((deprecated))`;modulemap 决策记入 step-7 todo。
5. **8.3 empty guard**:加 `if(data.length==0)return 0` + DEBUG assert(即便 xxh3 安全,防御性)。
6. **文档**:更新 step-8 勾选框(4✓ 4⚠),记 8.5 backfill 与 8.3 加固丢弃偏差;更新过时的 `15-progress-and-resume.md`。

## 证据索引
- `MaccyTests/HistoryItemPerformanceTests.swift:30-60` — 8.1 benchmark(无 .baseline)
- `Maccy/Processor/ClipboardByteProcessor.cpp:105-107`(xxh3_64)、`:91-98`(fnv1a64 仅 noexcept)、`:66`(UTF-8 检查未改)
- `Maccy/Processor/MaccyTextProcessor.mm:10,28-32`(seed=0、桥走 xxh3)、`:29`(仍 data.bytes 直接)、`.h:9`(UInt64,无 deprecation)
- `Maccy/Core/ClipboardDataProcessor.swift:33-56` — 对称 dataLikelyEqual
- `Maccy/Models/HistoryItemContent.swift:23,31` — fingerprint 列 + init;**无 backfill 代码**
- `Maccy/Engine/HistoryItemEngine.swift:104-111,117,131,147-159` — 读列 + 双向 DTO + contains
- `Maccy/Models/HistoryItem.swift:107` — live 路径接入确认
- 无 `FingerprintMigrationTests`/`FingerprintSymmetryTests`/`DataLikelyEqualContractTests`/`Xxh3ThroughputTests`(grep 0)
- CI run `28294966251`(1f25102)= 10/10 success
- step-8-cpp.md:43-113 — 8 勾选框全 `[ ]`
- commit `c6821c4` body — 记 UInt64 偏差 + "8.8 pending",但未披露 8.5 backfill / 8.3 加固丢弃

# BS-8 — C++ 扩展(测量驱动)

> **依赖**:BS-4(签名索引/指纹缓存已接入)。**编译边界**:小步骤 8.2(替换 `fnv1a64` 调用点)、8.4(`dataLikelyEqual` API 收紧为 `MaccyFingerprint` DTO)、8.5(`HistoryItemContent` 加 `fingerprint` 列 + SwiftData 迁移)、8.6(`ContentSignature/ContentIndex` 改读持久化列)各自会临时破坏既有调用点,**末尾全部恢复**;完成全部小步骤后 `xcodebuild build` 通过且既有测试全绿(含 C++ 改动与 SwiftData 迁移)。

**目标**:把去重指纹从 FNV-1a 串行(约 1 GB/s)升级到 xxh3/wyhash(SIMD,约 25–35 GB/s),并把 lhs 指纹从"内存缓存"(BS-4 的过渡态)推进到**SwiftData 持久化列**——使每次复制时 lhs 侧零重哈希,`G-copy-text` 的 `bytesHashed` 趋近 0。同时加固 ObjC++ 桥的空/连续性守护与 Sendable 边界。机会型扩展(pHash / RE2 / vImage / SIMD 子串)**仅在基准证明原生不足后**按 ROI 次第下沉,**UTF-8 前缀算法(V 系列确认正确)不改**。

**依据**:`08-F-001`/`03-LT-CPP-03`(V-2 确认,指纹非对称重哈希)、`08-F-002`(FNV 弱雪崩)、`08-F-003`/`03-LT-CPP-02`/`03-LT-CPP-07`(FNV 串行不可向量化)、`08-F-004`/`03-LT-CPP-04`/`03-LT-CPP-05`(桥无空/连续守护)、`08-F-008`(桥 `data.bytes` 契约)、`08-F-009`(`dataLikelyEqual` 默认参数陷阱)、`08-F-010`/`03-LT-MAIN-03`(桥 Swift 6 Sendable)、`08-F-006`/`99`(C++ 方言,BS-0 已统一为 `gnu++17`)、`08-F-007`(无 modulemap)、`08-F-011`/`03 Bench-1`(基准不覆盖非对称重哈希)、`08-F-012`(UTF-8 状态机已验证正确,不动)、`A §4`(`MaccyFingerprint` DTO)、`C §2`(哈希阈值 16 KiB 与目标算法)。

**编译安全性**:`ClipboardByteProcessor.cpp/.hpp` 与 `MaccyTextProcessor.h/.mm` 的签名变更、`ClipboardDataProcessor.dataLikelyEqual` 双向 `MaccyFingerprint` 化、`HistoryItemContent` 加列与轻量迁移、`ContentSignature/ContentIndex` 改读 `content.fingerprint` 列——既有调用点(`HistoryItemEngine.swift:162-164`、`ClipboardDataProcessor.swift:39-68`、`HistoryItemContent.swift:14-23`)在 8.8 全部对齐。`validUTF8PrefixLength`(`ClipboardByteProcessor.cpp:19-76`)经 `08-F-012` 全边界验证正确,**本步不触碰**。

## 机会矩阵(按基准次第,可选;先做最高 ROI 的 O-007)

| 机会(08-O-id) | 现状成本 | C++ 方案 | 预期 | 复杂度 | 前置(基准) |
|---|---|---|---|---|---|
| **O-007 指纹升级 + 持久化**(本步必做) | FNV 串行 ~1 GB/s(`ClipboardByteProcessor.cpp:78-85`);lhs 每比对重哈希(`08-F-001`) | `maccy::hash::xxh3_64` 单头;`HistoryItemContent.fingerprint` 列 | 哈希 3–5×;lhs 重哈希 → 0;`bytesHashed` 趋 0 | **低**(单头 + 轻量迁移) | `08-F-001/002/003` 已确认;无前置基准 |
| O-004 SIMD 子串搜索 | `String.range(of:.caseInsensitive)` ICU 全量(`Search.swift:115`)| `maccy::text::icontains_ascii`(SSE4.2/AVX2 `pcmpestri`) | ASCII 路径 2–8× | 中 | BS-5 后 `G-search` 若 `simpleSearch` 在 Instruments 占主 |
| O-003 用户正则 RE2 | `NSRegularExpression` + 回溯探测(`Search.swift:40-44,142-160`,1000 字符上限)| `re2::RE2` 线性时间,删除上限与回溯启发式 | 3–10×;删 1000 字符上限 | 中(vendored xcframework) | BS-5 后用户正则路径卡顿 |
| O-002 pHash 近似图去重 | 仅字节精确(`HistoryItemEngine.swift:163`)| `maccy::image::phash64` + `hamming`(popcount) | 启用近似图去重功能 | 中 | 产品目标确认需"近似重复" |
| O-001 图片降采样 C++ | BS-3 已下沉原生 `CGImageSourceCreateThumbnailAtIndex` | 仅在原生不足时:`vImage`/libjpeg-turbo | 2–6×(仅 JPEG)| 中–高 | BS-3 落地后 `G-copy-large-image` 仍未达标 |
| O-005 批量标题缩短 | `String.shortened(to:)` grapheme 计数(`String+Shortened.swift:7`)| `utf8_prefix_to_codepoints` | <2× | 低 | profile 后才考虑(原生已够,见 08-O-005)|
| O-006 排序/索引维护 | Swift `sorted` over `@Model`(`Sorter.swift:26-30`)| C++ 预计算键 + `std::sort` | <2× | 低–中 | **不做**(原生已够,瓶颈在键读取非算法)|

> 不越界:UTF-8 前缀算法(`08-F-012` 已验证正确)不改;图片降采样主路径属 BS-3(原生 ImageIO),本步仅当 `G-copy-large-image` 仍不达标才下沉 C++。O-005/O-006 默认不做。

## 受影响文件

- 新:`Maccy/Processor/third_party/xxhash.h`(或 `wyhash.h`)— 单头公共域/BSD-2,放到 `Processor/third_party/`;`HEADER_SEARCH_PATHS` 加 `$(SRCROOT)/Maccy/Processor`(`08-F-007` 配套)。
- 新:`Maccy/Processor/third_party/LICENSE-xxhash.txt` — 许可证文件随仓库(审 BS-8 验收)。
- 改:`Maccy/Processor/ClipboardByteProcessor.hpp:9-10` — 保留 `fnv1a64`(迁移期并存/兼容回退),新增 `std::uint64_t xxh3_64(const std::uint8_t*, std::size_t, std::uint64_t seed) noexcept`;两函数标 `noexcept`(`08-F-006`/`03-LT-CPP-06`)。
- 改:`Maccy/Processor/ClipboardByteProcessor.cpp:7-8,78-85` — `fnvOffsetBasis`/`fnvPrime` 保留(迁移期);新增 `maccy::processor::xxh3_64`(包 `XXH3_64bits_withSeed`,种子为进程级随机或固定迁移种子),`fnv1a64` 内部加 `seed` 参数与 `noexcept` 但保持算法等价(供旧指纹过渡比对)。
- 改:`Maccy/Processor/MaccyTextProcessor.h:5-11` — 加空/连续性契约文档注释(`08-F-008`);新增 `+ (MaccyFingerprint)fingerprintForData:(NSData *)data` 返回 `(size, hash)`(返回类型用 ObjC `struct`/`NS_INLINE` POD;**避免 `NSObject` 子类**以保 `Sendable`)。
- 改:`Maccy/Processor/MaccyTextProcessor.mm:7-20` — 空 `data` 守卫(`if (data.length == 0) return …`);非连续 `NSData` 走 `withUnsafeBytes`/`enumerateByteRanges` 分片喂入 C++(`08-F-004`/`03-LT-CPP-04`);新方法转调 `xxh3_64`,旧 `fingerprintForData:` 标 `__attribute__((deprecated))` 迁移期保留。
- 改:`Maccy/Maccy-Bridging-Header.h:1` — 桥接器沿用(暂不引 modulemap;若 8.7 选择 modulemap 则新增 `Maccy/Processor/module.modulemap`,`08-F-007`)。
- 改:`Maccy/Core/ClipboardDataProcessor.swift:4,31-68` — 阈值 16 KiB 保持;`dataLikelyEqual` 双默认参数陷阱(`:39-44`)收敛为双向 `MaccyFingerprint` DTO(`08-F-009`),删两参死代码重载(`:31-37`);`fingerprintIfLarge` 返回 `MaccyFingerprint?`(size + hash)而非 `UInt64?`。
- 改:`Maccy/Models/HistoryItemContent.swift:14-24` — 加 `var fingerprint: UInt64? = nil` 列(SwiftData `@Model`,**轻量迁移**——新增可空列无需 schema versioning);`init` 计算并赋值;`@Relationship var item` 不变。
- 改:`Maccy/Engine/HistoryItemEngine.swift:110-165` — `ContentSignature`(`:110-119`)读 `content.fingerprint`(持久化列)落回 `fingerprintIfLarge` 兜底;`ContentIndex`(`:122-142`)由 `[String: [Data]]` 改为 `[String: [(Data, MaccyFingerprint?)]]`(BS-4 内存版替换为持久化列读取);`contains`(`:153-165`)两向传 `MaccyFingerprint` DTO。
- 改:`Maccy.xcodeproj/project.pbxproj:1571,1598,1676,1739` — `gnu++14`/`gnu++0x` 已在 BS-0 统一为 `gnu++17`;本步核对无回退,并把 `xxhash.h`/`wyhash.h` 所在目录加入 `HEADER_SEARCH_PATHS`(若 8.7 选 modulemap 则一并配)。
- 新:`MaccyTests/FingerprintMigrationTests.swift` — 旧库(无 `fingerprint` 列)→ 迁移后旧条目按需回填;冷开/二次写入读列值。
- 新:`MaccyTests/FingerprintSymmetryTests.swift`(BS-4 已有骨架,本步扩 `bytesHashed≈0` 断言)。

## 小步骤

- [ ] **8.1 基准固化(测量驱动门槛)** — `MaccyTests/HistoryItemPerformanceTests.swift`(扩 08-F-011 / 03 Bench-1)。在替换前先固化"前"基线,否则 8.x 无法量化收益。新增用例:
  - 多同型 lhs 场景:`[.string: bigText, .rtf: bigRtf]` + N(≥20)条同型不同内容历史,`measure { signature.isContained(in:) }`——暴露 `08-F-001` 的每元素重哈希。
  - 哈希吞吐单测:`measure { _ = MaccyTextProcessor.fingerprint(for: oneMB) }` 与 `tenMB`,记录 GB/s(用 `XCTMetric` 的时钟;非断言,记录到 8.8 对比)。
  - 冷 lhs 变体:`ContentIndex` 在 `measure` 外构建一次(当前基准偶然如此,显式化)。
  - 不在本步设 `baseline`(算法尚未换);只在 8.8 设置 `measureMetrics` `.baseline` + 相对容差。
- [ ] **8.2 [breaks compile until 8.4] 引入 xxh3,保留 FNV 并存** — `ClipboardByteProcessor.hpp` + `.cpp` + 第三方头。
  - 在 `Maccy/Processor/third_party/` 放 `xxhash.h`(BSD-2,带 `LICENSE-xxhash.txt`);`#include "third_party/xxhash.h"`(相对路径,辅以 `HEADER_SEARCH_PATHS`)。
  - `namespace maccy { namespace processor {` 新增:
    ```cpp
    // 种子:固定迁移种子(migration seed)用于旧库回填阶段的兼容;进程级随机种子用于新写入。
    // 见 8.5:旧 FNV 指纹过渡策略。
    std::uint64_t xxh3_64(const std::uint8_t* bytes, std::size_t count,
                          std::uint64_t seed) noexcept;
    ```
  - 实现:转调 `XXH3_64bits_withSeed(bytes, count, seed)`。空 `count` 返回 `XXH3_64bits_withSeed(nullptr,0,seed)`(xxh3 对空输入定义良好,不同于 FNV 的 offset basis——过渡需注意,见 8.5)。
  - 保留 `fnv1a64`(`ClipboardByteProcessor.cpp:78-85`)不动,标 `noexcept`;供迁移期比对与回退。
  - `.hpp` 内两声明加 `noexcept`(`08-F-006`/`03-LT-CPP-06`)。
  - **本步不接 Swift 调用点**(8.4 才接),只编译 C++ 层;Swift 桥仍指 `fnv1a64`。
- [ ] **8.3 ObjC++ 桥加固 + 新桥方法** — `MaccyTextProcessor.h` + `.mm`。
  - `.h` 加文档契约注释:"Inputs may be empty; `data.bytes` may be `NULL` when `data.length == 0`. Callees must not dereference beyond `data.length`. Non-contiguous `NSData` is materialised via `withUnsafeBytes`."(`08-F-008`/`08-F-004`)。
  - `.mm:7-13,15-20` 两方法首行加 `if (data.length == 0) return 0;`(UTF-8)/ `return 0;`(fingerprint);DEBUG 加 `assert(data.bytes != NULL || data.length == 0)`。
  - 非连续 `NSData`:`[data enumerateByteRangesUsingBlock:]` 把 C++ 哈希改成可续算(对 xxh3 用 `XXH3_64bits_update` 流式 API;对 `validUTF8PrefixLength` 无影响,因为它一次性给 `count`)。`08-F-004`/`03-LT-CPP-04`。
  - 新增方法(返回 POD struct,保 Sendable):
    ```objc
    typedef struct { NSUInteger size; uint64_t hash; } MaccyFingerprintStruct;
    + (MaccyFingerprintStruct)fingerprintForData:(NSData *)data
        NS_SWIFT_NAME(fingerprint(for:));
    ```
    内部调 `maccy::processor::xxh3_64(static_cast<const std::uint8_t*>(buf), data.length, kMaccyHashSeed)`;`size = data.length`。
  - 旧 `+ (uint64_t)fingerprintForData:` 标 `__attribute__((deprecated("use fingerprint(for:) returning MaccyFingerprint")))`,迁移期保留(供 8.4 调用点逐步切换、8.5 旧指纹回填比对)。
  - `validUTF8PrefixLengthInData:`(`.mm:7-13`)的边界守护一并加(`index + width` 改 `width > limit - index` 形式,见 `03-LT-CPP-01`/`08-F-012`——**不改算法语义,仅防御性重写**)。
- [ ] **8.4 [breaks compile until 8.6] `dataLikelyEqual` 收敛为双向 `MaccyFingerprint` DTO** — `ClipboardDataProcessor.swift:31-68`。修 `08-F-009`(默认参数陷阱)+ `08-F-001`(对称):
  - `MaccyFingerprint` 已在 BS-1 `Dtos.swift` 定义(`struct MaccyFingerprint: Sendable, Equatable { let size: Int; let hash: UInt64 }`)。本步把 ObjC `MaccyFingerprintStruct` 经 Swift 自动桥接为同形 `MaccyFingerprint`(或在 `ClipboardDataProcessor` 内做一层 `init(_ c: MaccyFingerprintStruct)` 显式转换,避免类型名冲突——二选一,后者更显式)。
  - 新签名(强制双向,无默认值):
    ```swift
    static func dataLikelyEqual(_ lhs: Data, _ lhsFp: MaccyFingerprint,
                                _ rhs: Data, _ rhsFp: MaccyFingerprint) -> Bool
    ```
  - 内部:`lhs.size == rhs.size` 闸门(`lhsFp.size == rhsFp.size`);`size >= largeContentFingerprintThreshold`(16 KiB,`:4`)闸门;`lhsFp.hash == rhsFp.hash`;命中后 `lhs == rhs` 全字节兜底(`:59` 保留,正确性不变)。
  - **删除**两参死代码重载(`:31-37`)与三参默认值版本(`:39-44`),用新四参版替换(`08-F-009` recommendation 3)。
  - `fingerprintIfLarge(_:)`(`:62-68`)返回 `MaccyFingerprint?`(`nil` 当 `data.count < 16 KiB`);内部调新桥方法,种子用 `kMaccyHashSeed`(与持久化种子一致,见 8.5)。
  - **本步破坏 `HistoryItemEngine.swift:162-164` 调用点**,在 8.6 修复前临时不可编译(`[breaks compile until 8.6]`)。
- [ ] **8.5 [breaks compile until 8.8] `HistoryItemContent.fingerprint` 列 + SwiftData 轻量迁移 + 旧指纹过渡** — `HistoryItemContent.swift:14-24`。修 `08-F-001` 根因(持久化)与 `08-F-002`(种子/算法迁移):
  - 加列:`var fingerprint: UInt64? = nil`(`@Model`,可空;SwiftData 视为**轻量迁移**——新增可空列无需 `VersionedSchema`/`SchemaMigrationPlan`,默认自动迁移;**不破坏既有库**)。
  - `init(type:value:)` 计算并赋值:`self.fingerprint = value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)?.hash`。
  - **种子与迁移兼容(关键)**:xxh3 用 `kMaccyHashSeed`(进程启动时 `SystemRandomNumberGenerator` 生成一次,存 `static let`)?——**否**。若用进程随机种子,重启后同一 blob 哈希不同,持久化列失效。**种子必须固定**(编译期常量或 `UserDefaults` 持久化的安装期一次性随机值)。本步采用**固定迁移种子** `kMaccyHashSeed`(常量),所有 xxh3 调用共享,持久化列才能跨进程复用。
  - **旧 FNV 指纹过渡**:旧库的 `HistoryItemContent` 行**没有** `fingerprint` 列(轻量迁移后为 `nil`)。过渡策略——读路径:`ContentSignature`(`HistoryItemEngine.swift:115-119`)见 `content.fingerprint == nil` 时**落回** `fingerprintIfLarge`(旧路径,临时重算一次 xxh3——**注意**:不能落回 FNV,因为新写入的 rhs 用 xxh3,旧库回填也必须 xxh3 才能与新写入匹配)。写路径:首次 `add`/`load` 命中 `nil` 时,在后台 context 单事务内回填该行的 `fingerprint`(惰性回填,不全表扫)。冷开后台预取阶段可批量回填(借 BS-4 的 `VisibleWindowLoader` tail 队列)。
  - **不并存 FNV 作为持久化值**:持久化列只存 xxh3 哈希。FNV 函数保留(`ClipboardByteProcessor.cpp:78`)仅供迁移期诊断/单测比对,**不**作为回退键。
  - 跨平台字节序:`UInt64` 持久化按主机序写 SQLite(SwiftData 默认);xxh3 算法本身字节序无关(对 byte 序列操作);迁移种子为整型常量,跨架构一致(arm64/x86_64 同值)。无需显式 `OSSwapHostToLittle`。
  - **本步破坏 `ContentSignature` 初始化**,8.6 修复。
- [ ] **8.6 [breaks compile until 8.7] `ContentSignature`/`ContentIndex` 改读持久化列 + 两向 DTO** — `HistoryItemEngine.swift:110-165`。修 `08-F-001` 消费侧:
  - `ContentSignature.init(_ content:)`(`:115-119`):`self.fingerprint = content.fingerprint.map { MaccyFingerprint(size: content.value?.count ?? 0, hash: $0) } ?? content.value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)`——读持久化列优先,`nil` 落回临时计算(触发 8.5 的惰性回填)。
  - `ContentIndex`(`:122-142`)由 BS-4 的 `[String: [(Data, UInt64?)]]` 收敛为 `[String: [(Data, MaccyFingerprint?)]]`;构建时每个 lhs blob 调一次 `content.fingerprint`(持久化列),不再每次 `contains` 重算。
  - `contains(type:value:fingerprint:)`(`:153-165`):
    ```swift
    return values.contains { (lhsData, lhsFp) in
      guard let lhsFp else { return lhsData == value }   // 小内容(<16KiB)无指纹
      guard let rhsFp = fingerprint else { return lhsData == value }
      return ClipboardDataProcessor.dataLikelyEqual(lhsData, lhsFp, value, rhsFp)
    }
    ```
    两向 DTO,无默认参数,无重哈希。
  - **正确性不变**:`dataLikelyEqual` 末尾 `lhs == rhs`(`ClipboardDataProcessor.swift:59`)保留,xxh3 碰撞仍走全字节兜底;`08-F-002` 改善分布但不改正确性契约。
  - 调用点 `HistoryItemEngine.swift:162-164` 已在 8.6 内部更新;编译恢复到 `ContentSignature`/`ContentIndex` 路径,但 `ClipboardDataProcessor` 旧调用点(若 BS-4 留有)需 8.7 核对。
- [ ] **8.7 残留清理 + Sendable 边界 + (可选)modulemap** — 全 C++/Swift 桥层。
  - Sendable:`MaccyFingerprint` 是值类型 POD,Swift 6 `Sendable` 自动推导(BS-1 已 `struct MaccyFingerprint: Sendable, Equatable`)。`MaccyTextProcessor` ObjC 类(`MaccyTextProcessor.h:5`)在新方法返回 POD 后,Swift 侧不再持 ObjC 对象引用(类方法 + POD 返回);若 BS-7 `SWIFT_STRICT_CONCURRENCY=complete` 已开,加 `extension MaccyTextProcessor: @retroactive Sendable {}`(安全:全 `+` 方法,无 ivars,`08-F-010`)。
  - 旧 `+ (uint64_t)fingerprintForData:` deprecation:确认无生产调用点后,本步**保留但不删**(留一个 release 周期);删除时机记入 BS-7 收尾清单。
  - (可选)`Maccy/Processor/module.modulemap`(`08-F-007`):暴露 `MaccyTextProcessor` ObjC facade,`.hpp` 保持内部。设 `HEADER_SEARCH_PATHS = $(SRCROOT)/Maccy/Processor`。**若本步未做,记入 BS-7 待办**;不做不阻塞编译(modulemap 是 Swift 直接 C++ interop 的前置,本步仍走 bridging header)。
  - `xxhash.h` 的 `XXH_INLINE_ALL` 定义核对:单 TU 内联,无链接冲突;`libc++`(`project.pbxproj:1677,1740`)与 macOS 14 部署目标匹配(`08` 已确认)。
  - 线程安全:C++ 侧无共享可变状态(`xxh3_64`/`fnv1a64`/`validUTF8PrefixLength` 均纯函数;匿名 `continuation()`(`ClipboardByteProcessor.cpp:10-12`)内部链接无状态;种子 `kMaccyHashSeed` 是 `constexpr`/`static let` 不可变)。并发调用安全,无需锁。
- [ ] **8.8 测试 + 验证 + 基线设置** — `xcodebuild build` + test 通过。
  - 单测:`FingerprintMigrationTests`(旧库无列 → 轻量迁移后 `nil` → 命中回填 → 二次读有值)、`FingerprintSymmetryTests`(多同型 lhs,`bytesHashed` 不随 lhs 数线性增长——**断言趋 0**)、`DataLikelyEqualContractTests`(双向 DTO 强制;碰撞走 `==` 兜底;`size` 闸门;阈值 16 KiB 边界)、`Xxh3ThroughputTests`(10 MB blob 哈希时间记录,设 `measureMetrics` `.baseline` 相对容差,较 FNV 基线下降 3× 以上)。
  - `08-F-011`/`03 Bench-1` 补:多同型内容基准、CJK/emoji 基准(`heavy_text.txt` 经 BS-1 `FixtureLoader` 接入)、冷 lhs 变体。
  - 性能闸门 `G-copy-text`(复制 `heavy_text.txt`):主线程 < 16ms;**`bytesHashed` 趋 0**(lhs 读持久化列,rhs 哈希一次后 `IngestResult.metrics.bytesHashed` 由 ingestor 记录并断言较 BS-4 进一步下降到接近 0)。
  - 迁移正确性:旧库(模拟 `fingerprint` 列缺失)经轻量迁移后不丢历史、不重建库;回填后去重命中与新建路径一致(同一 blob 两次复制 → `.merged`)。
  - 全量验证:`xcodebuild build` + `xcodebuild test`(含 `MaccyPerformanceTests` 的 `G-copy-text`)通过。

## 关键签名

```cpp
// Maccy/Processor/ClipboardByteProcessor.hpp(BS-8 后)
namespace maccy { namespace processor {
  std::size_t validUTF8PrefixLength(const std::uint8_t* bytes,
                                    std::size_t count,
                                    std::size_t maxBytes) noexcept;            // 不变(08-F-012 正确)
  std::uint64_t fnv1a64(const std::uint8_t* bytes,
                        std::size_t count) noexcept;                           // 保留(迁移期诊断/回退)
  std::uint64_t xxh3_64(const std::uint8_t* bytes,
                        std::size_t count,
                        std::uint64_t seed) noexcept;                          // 新:SIMD 哈希
}}

// Maccy/Processor/ClipboardByteProcessor.cpp
#include "third_party/xxhash.h"
namespace maccy { namespace processor {
  std::uint64_t xxh3_64(const std::uint8_t* bytes, std::size_t count,
                        std::uint64_t seed) noexcept {
    return XXH3_64bits_withSeed(bytes, count, seed);   // 空输入定义良好
  }
}}
```

```objc
// Maccy/Processor/MaccyTextProcessor.h
typedef struct { NSUInteger size; uint64_t hash; } MaccyFingerprintStruct;

@interface MaccyTextProcessor : NSObject
// 文档契约:Inputs may be empty; data.bytes may be NULL when length==0.
// Non-contiguous NSData materialised via enumerateByteRanges.
+ (NSUInteger)validUTF8PrefixLengthInData:(NSData *)data
                                maxBytes:(NSUInteger)maxBytes NS_SWIFT_NAME(validUTF8PrefixLength(in:maxBytes:));
+ (MaccyFingerprintStruct)fingerprintForData:(NSData *)data NS_SWIFT_NAME(fingerprint(for:));
+ (uint64_t)fingerprintForData_deprecated:(NSData *)data
    NS_SWIFT_NAME(fingerprintLegacy(for:)) __attribute__((deprecated));
@end
```

```swift
// Maccy/Core/ClipboardDataProcessor.swift(BS-8 后)
enum ClipboardDataProcessor {
  private static let largeContentFingerprintThreshold = 16 * 1_024   // :4 不变(C §2)

  // 强制双向 DTO,无默认参数(修 08-F-009)
  static func dataLikelyEqual(_ lhs: Data, _ lhsFp: MaccyFingerprint,
                              _ rhs: Data, _ rhsFp: MaccyFingerprint) -> Bool {
    guard lhsFp.size == rhsFp.size else { return false }
    guard lhsFp.size >= largeContentFingerprintThreshold else { return lhs == rhs }
    guard lhsFp.hash == rhsFp.hash else { return false }
    return lhs == rhs                                   // 碰撞兜底(正确性不变)
  }

  static func fingerprintIfLarge(_ data: Data) -> MaccyFingerprint? {
    guard data.count >= largeContentFingerprintThreshold else { return nil }
    let c = MaccyTextProcessor.fingerprint(for: data)   // -> MaccyFingerprintStruct
    return MaccyFingerprint(size: Int(c.size), hash: c.hash)
  }
}

// Maccy/Models/HistoryItemContent.swift(BS-8 后)
@Model class HistoryItemContent {
  var type: String = ""
  var value: Data?
  var fingerprint: UInt64? = nil          // 新列(轻量迁移);xxh3 hash,固定种子
  @Relationship var item: HistoryItem?
  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
    self.fingerprint = value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)?.hash
  }
}

// Maccy/Engine/HistoryItemEngine.swift(BS-8 后,关键片段)
private struct ContentIndex {
  private let contentsByType: [String: [(Data, MaccyFingerprint?)]]   // 读持久化列
  func contains(type: String, value: Data?, fingerprint rhsFp: MaccyFingerprint?) -> Bool {
    guard let value else { return nilValueTypes.contains(type) }
    guard let values = contentsByType[type] else { return false }
    return values.contains { lhsData, lhsFp in
      guard let lhsFp, let rhsFp else { return lhsData == value }
      return ClipboardDataProcessor.dataLikelyEqual(lhsData, lhsFp, value, rhsFp)
    }
  }
}
```

## 复杂度(前→后)

| 操作 | 前(file:line) | 前复杂度/吞吐 | 后复杂度/吞吐 | 落点 |
|---|---|---|---|---|
| 哈希单 blob | `ClipboardByteProcessor.cpp:78-85` | FNV 串行 ~1 GB/s(不可向量化,`08-F-003`) | xxh3 SIMD ~25–35 GB/s(3–5×,`08-O-007`) | 8.2 |
| dedup lhs 重哈希 | `ClipboardDataProcessor.swift:53`(`08-F-001`)+ `HistoryItemEngine.swift:163` | 每比对重算 lhs FNV(O(总存储字节)/比对) | **0**(读 `HistoryItemContent.fingerprint` 持久化列) | 8.5, 8.6 |
| `dataLikelyEqual` 比对 | `ClipboardDataProcessor.swift:39-60` | O(1) 长度 + 可能 O(n) 重哈希 + O(n) `==` | O(1) 长度 + O(1) `UInt64 ==` + 仅命中 O(n) `==` | 8.4 |
| ObjC 桥空/非连续 | `MaccyTextProcessor.mm:7-20` | 隐式契约(`data.bytes` 可能 NULL/非连续) | 显式守护 + `enumerateByteRanges` 流式(`08-F-004`) | 8.3 |
| 旧库迁移 | — | — | 轻量迁移(可空列)+ 惰性回填(O(命中数),非全表) | 8.5 |

> 哈希吞吐:1 GB/s(FNV 串行)→ 25–35 GB/s(xxh3/wyhash)。dedup lhs 重哈希:每次复制 O(总存储字节) → 0(持久化后)。`bytesHashed` 闸门趋 0。

## 管线估计

- 复制文本→列表可见:去重 lhs 零重哈希(读列)+ rhs 哈希一次(xxh3 较 FNV 3–5×)+ 命中候选精确确认(`SignatureIndex` O(命中数),BS-4)。主线程仅追加单行 diff,满足 `G-copy-text` < 16ms;`bytesHashed` 较 BS-4(内存缓存)进一步趋 0。
- 冷开 load:`SignatureIndex(from:)`(BS-4)直接读 `content.fingerprint` 列构建索引,不再对大内容临时哈希;tail 预取阶段惰性回填 `nil` 行(后台,不阻塞首屏)。
- 大图去重(若未来 O-002 pHash):复用 8.3 的 `enumerateByteRanges` 流式桥 + xxh3 基础设施,pHash 作为附加列。

## I/O 限制

- 哈希阈值 `16 KiB`(`ClipboardDataProcessor.swift:4`)不变(`C §2`);仅 ≥16 KiB 内容算/存指纹,小内容走 `lhs == rhs`。
- `HistoryItemContent.fingerprint` 为可空列;旧库轻量迁移不重建、不丢数据(对齐 `A §7` 容器失败不删库精神)。
- 非连续 `NSData`:经 `enumerateByteRanges` + `XXH3_64bits_update` 流式,不强制 `Data` 连续(`08-F-004`);避免对 mapped-file/hole 支持的 `bytes` 直接 deref。
- 第三方头:xxh3 单文件 BSD-2(或 wyhash 公共域),随仓库带 `LICENSE-xxhash.txt`;无新链接库(`libc++` 已在 `project.pbxproj:1677,1740`)。

## 闸门

- **`G-copy-text`**:复制 `heavy_text.txt`(31 KB CJK,`03 Bench-1`),主线程 < 16ms;**`bytesHashed` 趋 0**(BS-4 内存缓存后仍非 0;BS-8 持久化列后 lhs 零哈希,仅 rhs 哈希一次且 xxh3 3–5× 快)。`IngestResult.metrics.bytesHashed` 由 ingestor 记录并断言。
- **`Xxh3ThroughputTests`**(新增):10 MB blob 哈希时间较 FNV 基线(8.1 固化)下降 ≥ 3×,设 `measureMetrics` `.baseline` + 相对容差;CI 性能 PR 须绿。
- 迁移正确性:`FingerprintMigrationTests` 旧库 → 轻量迁移 → 回填 → 去重命中一致(不进 `08-F-001` 重哈希路径)。

## 测试

- 引用:`B §2`(`FixtureLoader` 含 `heavy_text.txt` 与合成大内容、`IngestorSpy` 记 `metrics`)、`§3`(`IngestResult.metrics.bytesHashed`)、`§4`(`G-copy-text`)、`§5`(`08-F-001 → SignatureIndexTests.dedup_lhsFingerprint_notRehashed + bytesHashed≈0`)。
- 新增/扩充:`FingerprintMigrationTests`(轻量迁移 + 惰性回填)、`FingerprintSymmetryTests`(多同型 lhs,`bytesHashed` 不随 lhs 数线性增长)、`DataLikelyEqualContractTests`(双向 DTO 强制;`size` 闸门;`hash` 碰撞走 `==` 兜底;阈值 16 KiB 边界)、`Xxh3ThroughputTests`(吞吐基线)、`HistoryItemPerformanceTests` 扩充(08-F-011:多同型内容、CJK/emoji、冷 lhs)。
- 不变性测试:`validUTF8PrefixLength` 边界回归(确认 8.3/8.7 未误改 UTF-8 状态机——`08-F-012` 全边界用例:`empty`/`maxBytes=0`/`0xC0 0x80` overlong/`0xED 0xA0 0x80` surrogate/`0xF4 0x90 0x80 0x80` >0x10FFFF)。

## 验收标准

- 功能:相同内容 → `.merged` 语义不变;xxh3 碰撞走 `lhs == rhs` 兜底(结果与 FNV 时代逐字节一致);`dataLikelyEqual` 两向 DTO 强制(无默认参数陷阱,`08-F-009` 根除);旧库经轻量迁移后历史不丢、去重命中与新库一致。
- 复杂度:哈希吞吐 ~1 GB/s → ~25–35 GB/s(3–5×);dedup lhs 重哈希每次复制 → 0(持久化列);`bytesHashed` 较 BS-4 进一步趋 0。
- 管线:`G-copy-text` 主线程 < 16ms 且 `bytesHashed ≈ 0`;冷开 `SignatureIndex` 构建读列不临时哈希。
- I/O 限制:16 KiB 阈值不变;`fingerprint` 可空列轻量迁移;非连续 `NSData` 经流式桥不 deref 非法指针;xxh3 许可证随仓库。
- 不变性:`A §7` 的"跨 actor 载荷 Sendable"由 `MaccyFingerprint` POD 值类型保证;"主线程无 >16ms 同步重活"由 `G-copy-text` 守卫;C++ 层无共享可变状态(纯函数 + 不可变种子)。
- 不越界:UTF-8 前缀算法(`ClipboardByteProcessor.cpp:19-76`,`08-F-012`)未改;图片降采样主路径仍属 BS-3(原生 ImageIO),O-001 仅当 `G-copy-large-image` 不达标才后续下沉;O-005/O-006 默认不做。

## Commit
`perf(cpp): xxh3 fingerprint, persisted HistoryItemContent.fingerprint column, symmetric MaccyFingerprint DTO, hardened ObjC++ bridge (gates G-copy-text bytesHashed→0)`

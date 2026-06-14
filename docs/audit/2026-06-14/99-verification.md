# 对抗式验证记录

- **目的**:对 8 份维度文档中最具影响力/最反直觉的断言,由人工独立重读源码核实,剔除误报、修正措辞。
- **方法**:Read 实际代码、走调用路径,不依赖子智能体摘要。
- **范围**:覆盖所有 Critical 中"强断言"类 + 构建设置类。Medium/Low 未逐条复核(信任子智能体的 file:line 证据,实施前再抽样)。

## ✅ 已确认(Confirmed)

### V-1 构建设置基线(对应 06-F49)
**断言**:`SWIFT_VERSION = 5.0`;`SWIFT_STRICT_CONCURRENCY` 未设置(默认 `minimal`);`SWIFT_COMPILATION_MODE = wholemodule`(Release);部署目标 macOS 14.0。
**核实**:`grep` `Maccy.xcodeproj/project.pbxproj`:
```
SWIFT_VERSION = 5.0              # 多个 config
SWIFT_STRICT_CONCURRENCY         # 未出现 → minimal
SWIFT_COMPILATION_MODE = wholemodule   # :1782
MACOSX_DEPLOYMENT_TARGET = 14.0
SWIFT_OBJC_BRIDGING_HEADER = "Maccy/Maccy-Bridging-Header.h"
```
**结论**:确认。Swift 6 迁移起点为 5.0 + minimal。

### V-2 C++ 指纹非对称复用(对应 08-F-001 / 03-LT-CPP-03)
**断言**:`HistoryItemEngine` 只传 `rhsFingerprint`,导致已存储 lhs 大块在每次比对时都被 C++ FNV 重新哈希。
**核实**:
- `Maccy/Engine/HistoryItemEngine.swift:162-164`:
  ```swift
  return values.contains {
    ClipboardDataProcessor.dataLikelyEqual($0, value, rhsFingerprint: fingerprint)
  }
  ```
  其中 `$0` = 已存储值(lhs)、`value` = 新值(rhs)、`fingerprint` = 新值的指纹。
- `Maccy/Core/ClipboardDataProcessor.swift:53-54`:
  ```swift
  let lhsFingerprint = lhsFingerprint ?? MaccyTextProcessor.fingerprint(for: lhs)  // ← nil → 重算
  let rhsFingerprint = rhsFingerprint ?? MaccyTextProcessor.fingerprint(for: rhs)  // 已传入,不重算
  ```
**结论**:确认。每次复制,所有命中类型的已存储大块(≥16KB)都被 FNV 重哈希一遍。措辞修正:并非"完全 no-op"——rhs 侧确实缓存了,小内容走纯 `==`;但对**大内容主导成本**确实被抵消。严重度 High 合理。

### V-3 `item(before:)` 首项 trap 可达(对应 07-F-032)
**断言**:`Collection+Surrounding.item(before:where:)` 在首元素时 `index(currentIndex, offsetBy: -1)` 触发运行时 trap,且经 `highlightPrevious`(↑ 键)可达。
**核实**:
- `Maccy/Extensions/Collection+Surrounding.swift:23`:
  ```swift
  var prevIndex = index(currentIndex, offsetBy: -1)   // 非可选版,首元素(offsetBy -1 越界)→ trap
  while prevIndex >= startIndex { ... }
  ```
  对比 `item(after:)`(`:7`):先算 `index(currentIndex, offsetBy: 1)` 到 `endIndex`(合法),再 `while nextIndex < endIndex` → 安全。**非对称 bug 确认**。
- 可达链:`Maccy/ItemsProtocol.swift:43-44`:
  ```swift
  func visibleItem(before: Item) -> Item? {
    return self.items.item(before: before, where: \.isVisible)   // ← 直接转发
  }
  ```
  `Maccy/Observables/NavigationManager.swift:206-216`:
  ```swift
  func highlightPrevious() {
    guard let lead = leadSelection else { return }
    if let historyItem = history.firstVisibleItem(where: { $0.id == lead }) {
      if let nextItem = history.visibleItem(before: historyItem) { ... }  // ← 无前置"是否首项"守卫
  ```
**结论**:确认。当 `items[0]` 可见且为当前选中时按 ↑ → `firstIndex` 返回 0 → `index(0, offsetBy:-1)` → **app 崩溃**。Critical(可复现崩溃)。

### V-4 `recoverContainer` 删库丢数据(对应 07-F-001)
**断言**:容器加载失败即删除 SQLite 文件,瞬时故障(磁盘满/AV 锁/沙盒变更)也会导致全量历史丢失。
**核实**:`Maccy/Storage.swift:37-72`,`recoverContainer` 先 `removeStoreFiles`(删 `-sqlite/-shm/-wal`)再重试,失败回退内存库,再失败 `preconditionFailure`。
**结论**:确认。Critical(不可逆数据丢失)。

### V-5 `try?` 全局吞错(对应 07-F-002/F-003)
**核实**:`History.swift` 多处(135/142/208/230-241/263-265/284/458)、`Clipboard.swift:208`、`HistoryItem.swift:45/261/266` 均 `try?` 吞掉 save/delete/fetch 错误;`insertIntoStorage` 后 `all`/`items` 已更新,save 静默失败则下次启动丢失。
**结论**:确认。High(静默数据丢失窗口)。

## ⚠️ 措辞/范围修正

| 原文 | 修正 |
|---|---|
| 03-LT-CPP-03:"dedup 优化 essentially a no-op" | 修正为"对大内容主导成本基本失效"(rhs 仍缓存、小内容走 `==`,非完全无效)。结论方向不变。 |
| 05 "最坏 ~12.8 GiB" | 属**重度浏览场景估算**(size=999、20% 图片、retina 27" iMac 且已浏览+预览),非稳态。需在 UI 加内存告警回收前成立。作为"上限警示"有效,非典型值。 |
| 08-F-001 严重度 | 维持 High(性能,非正确性——hash 命中后仍有 `lhs == rhs` 全字节比对兜底,结果正确)。 |

## ℹ️ 补充发现(复核过程中新发现)

- **构建方言不一致**:`project.pbxproj` 中 Maccy 目标 C++ 用 `gnu++14`(`:1571/1598`),但有两个 config 用 `"gnu++0x"`(`:1676/1739`,疑为测试 target)。`gnu++0x` 是 C++11 草案方言,极旧。建议统一为 `gnu++17`/`gnu++20`,并为后续 C++ 机会(xxh3、ImageIO/vImage 封装)预留现代标准。归入 08(C++ 构建卫生,Low/Medium)。

## ❓ 未独立复核(实施前需抽样)

- 02 图片 "~10× 慢" 等量化对比(方向正确,具体倍数依赖图源;实施时基准测试验证)。
- 各 Low 级发现(命名/冗余/小边界),信任子智能体的 file:line 证据,实施时按需抽查。

## 复核结论

四类最关键断言(构建基线、C++ 指纹非对称、首项 trap 可达、删库丢数据)**全部属实**,可作为实施依据。其余发现按文档 file:line 证据采信,实施时抽样验证。

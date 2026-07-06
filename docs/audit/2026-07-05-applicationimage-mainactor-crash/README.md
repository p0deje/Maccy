# ApplicationImage `@MainActor` 崩溃分析 + 同类隔离风险排查(2026-07-05)

> **触发**:`Maccy 2.6.1 (build 60)` 本地构建(未签名,`codeSigningTeamID: ""`)在 2026-07-04 23:24 崩溃,
> `EXC_BREAKPOINT (SIGTRAP)`,`Thread 5`,`com.apple.root.default-qos`。
> **崩溃点**:`closure #1 in ApplicationImage.nsImage.getter` → `_dispatch_assert_queue_fail`。
> **结论**:**这是 BS-7(`c6193c7`,2026-06-28)把 `ApplicationImage` 标 `@MainActor` 后引入的运行时隔离崩溃**;
> 06-28 gap-audit 把 7.4 误判为"经 main hop 隔离安全",本崩溃证伪该判断。
> **修复(2026-07-06 已落地)**:`ApplicationImage.swift` `queue: DispatchQueue.global()` → `queue: DispatchQueue.main`,并删除现已冗余的内层 `DispatchQueue.main.async` hop(handler 已在 main 上,直接访问 `self`;原"序言后 hop"结构是导致 06-28 误判的脚枪,一并清除)。
> **同类排查**:§7 单人预扫描仅 `ApplicationImage` 一处确认 trap;`deinit + assumeIsolated` + NSCache 后台驱逐(§8)为同族潜在风险,待验证。

---

## 0. TL;DR

| 项 | 内容 |
|---|---|
| **崩溃类型** | `EXC_BREAKPOINT (SIGTRAP)` = Swift 6 运行时隔离断言 `dispatch_assert_queue_fail` |
| **崩溃位置** | `Maccy/ApplicationImage.swift` 的 `nsImage` getter 里 `setEventHandler` 闭包(外层) |
| **机制** | `ApplicationImage` 是 `@MainActor` 类;`DispatchSourceHandler` 是 `() -> Void`(非 `@Sendable`);外层事件处理闭包**继承** `@MainActor`(SE-0420)。Dispatch source 的 `queue: .global()` 在后台队列回调该闭包 → `@MainActor` 序言 `dispatch_assert_queue(main)` 失败 → `SIGTRAP` |
| **为什么 `DispatchQueue.main.async` 没救** | 那个 hop 在闭包**体内**;序言在**进入体之前**就 trap 了,hop 永远到不了 |
| **为何潜伏 ~14 小时** | dispatch source 只在**被监视的 app bundle 被删除/重命名**时才 fire。09:00 启动 → 23:24 崩溃,与用户期间装/更新了某个 app 一致 |
| **根因提交** | `c6193c7 fix(bs7): ApplicationImage @MainActor + …`(2026-06-28)——加 `@MainActor` 时没动 `setEventHandler` |
| **审计误判** | 06-28 gap-audit `03-bs7-swift6-gaps.md` 7.4 写"经 main hop 隔离安全(故 complete 编译过)"——**错**。complete 模式只保证编译,不保证运行时不 trap |
| **修复** | `queue: .global()` → `queue: .main`(与 06-28 审计 7.4 的"应改 `queue:.main`"建议一致;但当时被标"部分完成/低优先",本崩溃证明它是 **P0** 而非 P3) |
| **同类风险** | 见 §6 清单;**已预扫描**——仅 `ApplicationImage` 一处确认会 trap;`deinit + assumeIsolated` 有 NSCache 后台驱逐的潜在风险 |

---

## 1. 崩溃证据(来自 crash report)

关键栈帧(`Thread 5 Crashed:: com.apple.root.default-qos`):

```
0  libdispatch.dylib        _dispatch_assert_queue_fail + 120
1  libdispatch.dylib        dispatch_assert_queue$V2.cold.1
2  libdispatch.dylib        dispatch_assert_queue + 108
3  libswift_Concurrency.dylib _swift_task_checkIsolatedSwift + 48
4  libswift_Concurrency.dylib swift_task_isCurrentExecutorWithFlagsImpl(...) + 356
5  Maccy                    closure #1 in ApplicationImage.nsImage.getter + 292
6  Maccy                    <deduplicated_symbol> + 28
7  libdispatch.dylib        _dispatch_client_callout + 16
8  libdispatch.dylib        _dispatch_continuation_pop + 596
9  libdispatch.dylib        _dispatch_source_latch_and_call + 392   ← dispatch SOURCE 回调
10 libdispatch.dylib        _dispatch_source_invoke
11 libdispatch.dylib        _dispatch_root_queue_drain_deferred_item
12 libdispatch.dylib        _dispatch_kevent_worker_thread         ← kevent 后台 worker
13 libsystem_pthread.dylib  _pthread_wqthread
```

读法:

- `_dispatch_source_latch_and_call` = **dispatch source 触发事件处理器**(`setEventHandler` 装的闭包),不是普通 `DispatchQueue.main.async` 的 continuation。
- 调用源是 `_dispatch_kevent_worker_thread` → `com.apple.root.default-qos`,即 `DispatchQueue.global()` 的后台线程。
- `swift_task_isCurrentExecutorWithFlagsImpl` → `dispatch_assert_queue` → `_dispatch_assert_queue_fail`:**Swift 6 的 `@MainActor` 序言**断言"当前在主队列",失败 → `brk 1`(esr `0xf2000001`)→ `SIGTRAP`。
- `closure #1 in ApplicationImage.nsImage.getter + 292`:闭包入口序言里调 executor 检查的那条指令。

崩溃签名不是 `EXC_BAD_ACCESS`、不是 OOM、不是被系统 kill——是**进程自己 `brk` 自杀**,典型 Swift Concurrency 隔离断言失败。

辅助证据(VM summary):`Memory Tag 22 = 64.0M`、`mapped file = 654.2M`(图标资源)、`MALLOC = 185.3M` —— 都是 Maccy 正常驻留,与崩溃无因果。`System Integrity Protection: disabled` 是用户机器状态,与本栈无关。

---

## 2. 崩溃机制(逐步)

### 2.1 `ApplicationImage` 现在是 `@MainActor` 类

`Maccy/ApplicationImage.swift`:

```swift
@MainActor                       // ← BS-7 (c6193c7, 2026-06-28) 加入
class ApplicationImage {
  ...
  private var eventSource: (any DispatchSourceFileSystemObject)?

  var nsImage: NSImage {
    ...
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.delete, .rename],
      queue: DispatchQueue.global()        // ← 第 80 行:后台队列
    )
    source.setEventHandler { [weak self] in        // ← "closure #1"
      DispatchQueue.main.async { [weak self] in     //   体内 hop,在序言之后
        guard let self, let eventSource = self.eventSource else { return }
        ...
        self.image = NSWorkspace.shared.icon(forFile: appURL.path)
      }
    }
    ...
  }
}
```

### 2.2 `DispatchSourceHandler` 是非 `@Sendable` 类型别名

Apple 文档(`DispatchSourceProtocol.setEventHandler(qos:flags:handler:)` 的 `handler: Self.DispatchSourceHandler?`):

```swift
typealias DispatchSourceHandler = () -> Void   // 非 @Sendable
```

`setEventHandler(handler:)` 接受的闭包类型是 `() -> Void`,**不是** `@Sendable () -> Void`。

### 2.3 SE-0420 隔离继承 ⇒ 外层闭包继承 `@MainActor`

Swift 6 规则:**非 `@Sendable` 的闭包字面量从其词法上下文继承隔离**。这里词法上下文是 `@MainActor` 类 `ApplicationImage` 的 `nsImage` getter(`@MainActor` 隔离)。

所以传给 `setEventHandler` 的外层闭包被推断为 **`@MainActor () -> Void`**:
- 编译器为它生成入口序言,调 `swift_task_isCurrentExecutorWithFlagsImpl` → `dispatch_assert_queue(com.apple.main-thread)`。
- 这一步是**运行时断言**,不是编译期检查——`SWIFT_STRICT_CONCURRENCY = complete` 只保证编译过,不保证运行时序言通过。

### 2.4 dispatch source 在后台队列回调该闭包 ⇒ 序言失败

`queue: DispatchQueue.global()` 意味着 dispatch source 把事件处理闭包提交到 `com.apple.root.default-qos`。当被监视的 app bundle 被删除/重命名(kevent 触发),source 在后台 worker 线程上调用该 `@MainActor` 闭包:

1. 进入闭包 → 序言 `dispatch_assert_queue(main)`:
   - 当前队列 = `com.apple.root.default-qos`(后台)≠ `com.apple.main-thread`。
   - 断言失败 → `_dispatch_assert_queue_fail` → `brk 1` → `SIGTRAP`。

### 2.5 为什么 `DispatchQueue.main.async` hop 救不了

外层闭包的**结构**是:

```
[序言: assert on MainActor]  ← trap 在这里
{
  DispatchQueue.main.async {   ← 永远到不了
    ... self.image = ... ...
  }
}
```

序言在函数体执行**之前**就 trap 了。`DispatchQueue.main.async` 是函数体里的一条语句,永远到不了。**"先 hop 到 main 再做事"的 hop 必须放在闭包外面、序言之前才有效**——而 `setEventHandler` 的闭包类型已经把整个闭包钉死成 `@MainActor`,你没法在"外面"再 hop。

这是 06-28 审计 7.4 "经 main hop 隔离安全"判断的根本错误:**hop 在错误的一侧**。

### 2.6 与 14 小时潜伏期一致

dispatch source 用 `O_EVTONLY` 打开 app bundle 路径,监听 `[.delete, .rename]`。**只有用户删除/重命名/重装了某个已复制过(缓存了图标)的 app bundle**,source 才 fire。09:00:23 启动 → 23:24:21 崩溃 = ~14h20m,期间用户装/更新了一个 app,触发了 source——与机制完全自洽。

(这也解释了为什么 CI 没抓到:CI 跑的是单元/UI 测试,测试里不会真的去删一个 app bundle 来触发 `ApplicationImage` 的 dispatch source。`ApplicationImageCacheTests` 只测缓存命中/`purge()`,不测 source fire。)

---

## 3. 根因时间线

| 日期 | 提交 | 改动 | 当时是否安全 |
|------|------|------|------|
| 历史 | (2.6.1 tag 前) | `ApplicationImage` 无 `@MainActor`;`setEventHandler { DispatchQueue.main.async { self.image = nil } }` | ✅ 安全(类非 `@MainActor`,闭包非隔离,无序言) |
| 2026-06-25 | `dd1d565` fix(memory) M4 | 加 `[weak self]`、`DispatchQueue.main.async` 内层 hop、fd guard、`[.delete,.rename]`、logger。**类仍非 `@MainActor`** | ✅ 安全(同上) |
| 2026-06-28 | `c6193c7` fix(bs7) | **加 `@MainActor` 到 `class ApplicationImage`**;`deinit` 改 `MainActor.assumeIsolated { eventSource?.cancel() }`。**未动 `setEventHandler` 闭包** | ❌ **引入崩溃**。commit message 写 "DispatchSource handler already hops to main"——**错误前提**(见 §2.5) |
| 2026-06-28 | 06-28 gap-audit `03-bs7-swift6-gaps.md` | 7.4 识别出 `queue: .global()` + main.async hop,但判 "经 main hop 隔离安全(故 complete 编译过)",标 ⚠️ 部分完成,P3 优先级 | ❌ 误判(见 §4) |
| 2026-07-04 23:24 | 用户本地 2.6.1 构建崩溃 | dispatch source fire → 序言 trap | — |

**核心错配**:M4 的 `DispatchQueue.main.async` hop 是在类还是**非** `@MainActor` 时写的,那时它**不需要**起隔离作用(没有序言要绕)。BS-7 加 `@MainActor` 后,这个 hop 被寄希望于"已经处理了隔离",但它**在闭包体内**,挡不住**体外**的序言。

---

## 4. 为什么 06-28 审计判错(以及它为什么有迷惑性)

06-28 gap-audit `03-bs7-swift6-gaps.md:30-31` 原文:

> ### 7.4 Singleton @MainActor + ApplicationImage DispatchSource→.main — ⚠️ 部分
> ApplicationImage 已 @MainActor,但 `ApplicationImage.swift:76` 仍 `queue: DispatchQueue.global()` + `:79` 内层 `DispatchQueue.main.async` — 正是 7.4 要替换为 `queue:.main` 的模式。**经 main hop 隔离安全(故 complete 编译过)**,但规范的改法未做。

两个迷惑点:

1. **"complete 编译过"被当成"隔离安全"的证据**。错。`SWIFT_STRICT_CONCURRENCY = complete` 是**编译期**门,只校验静态隔离关系;`@MainActor` 闭包被传给非 `@Sendable` 的 `() -> Void` 参数是合法的(协变,更隔离可赋给更不隔离),编译通过。**运行时序言**是另一道门,complete 模式不替你跑它。
2. **"main hop 在"被当成"序言过得了"的证据**。错。hop 在闭包体内,序言在体外入口;体外的 trap 先于体内的 hop。

> **方法学教训**:`@MainActor` 上下文里,任何传给 dispatch/Timer/notification 的**非 `@Sendable`** 闭包都会继承 `@MainActor`,从而带运行时序言。判断"是否安全"的唯一标准是:**该回调实际在哪个队列/线程上被调用**——若不是 main,就 trap。"代码里有 `DispatchQueue.main.async`"不是判据,"回调的 `queue:` 参数是什么"才是。

---

## 5. 修复方案

### 5.1 推荐(一行,最小,与 06-28 审计 7.4 一致):`queue: .main`

```swift
let source = DispatchSource.makeFileSystemObjectSource(
  fileDescriptor: descriptor,
  eventMask: [.delete, .rename],
  queue: DispatchQueue.main        // ← was: DispatchQueue.global()
)
```

为什么有效:

- dispatch source 在主队列回调事件处理闭包 → `@MainActor` 序言 `dispatch_assert_queue(main)` 通过 ✅
- `setCancelHandler { close(descriptor) }` 也在主队列跑;`close()` 是线程安全 syscall,主线程上开销可忽略 ✅
- `deinit` 里 `eventSource?.cancel()` 调度 cancel handler 到 source 的目标队列(现在 `.main`)——与 `deinit` 实际在 main 跑一致 ✅

代价:

- rename 分支会同步在主线程做 `NSWorkspace.shared.icon(forFile:)`(一次 LaunchServices/FS 查询)。**这是极罕见事件**(app 重装/重命名),且当前代码在 hop 之后也是这么做的,行为不变 ✅

可选简化(非必需):改 `queue: .main` 后,内层 `DispatchQueue.main.async { ... }` 已冗余(已在 main),可顺势去掉,直接在 `setEventHandler` 闭包里写 `self.image = ...`。但这会改闭包结构、需重新过一遍 SwiftLint;**最小修复只改 `queue:` 一行**,简化留作可选。

### 5.2 备选(更"教科书"的 Swift 6 模式):非隔离闭包 + 显式 hop

把事件处理拆成 `nonisolated` 闭包,只捕获 `Sendable` 值,再 `Task { @MainActor in … }` 或 `MainActor.run` hop:

```swift
// 概念示意(不要直接照抄,需配合 Sendable 捕获)
let bundleID = self.bundleIdentifier  // Sendable
let appPath = appURL.path             // Sendable
source.setEventHandler { [weak self] in
  guard let self else { return }
  Task { @MainActor in
    // 在这里访问 self.eventSource / self.image
  }
}
```

问题:`DispatchSourceHandler = () -> Void` 非 `@Sendable`,外层闭包仍会继承 `@MainActor`(因为 `self` 是 `@MainActor`)——除非把 `self` 完全踢出捕获、改用 token/handle。改动面大、收益等于 5.1,**不推荐**。5.1 已是 06-28 审计自己挑的方案。

### 5.3 验证门

- **CI**(必跑):`gh workflow run "macOS 26 ARM CI" --ref <branch>`,绿是必要条件(编译 + SwiftLint --strict + 既有测试)。
- **回归测试**(应补,见 §7):新增一个触发 dispatch source fire 的测试——监听一个临时文件,`rename`/`delete` 它,断言不 trap。当前 `ApplicationImageCacheTests` 不覆盖 source fire 路径,这是 CI 没抓到本 bug 的直接原因。

---

## 6. 同类隔离风险排查方法学(给"排查所有类似问题"用)

本崩溃属于一个可推广的**危险模式族**:

> **`@MainActor` 上下文里把非 `@Sendable` 闭包传给会在非主队列/线程回调的 API → 闭包继承 `@MainActor` → 回调时序言 trap。**

以及它的对偶:

> **`MainActor.assumeIsolated { … }` 出现在可能**不在**主线程的上下文 → 同样的 `dispatch_assert_queue` trap。**

### 6.1 排查清单(5 类调用点)

对 `Maccy/` 下每个命中点,只问一个问题:**"回调实际在哪个队列/线程发生?"**——不是 main 就标红。

| # | 模式 | grep 锚点 | 判据 |
|---|------|-----------|------|
| **C1** | `DispatchSource.make*Source(... queue: X)` | `makeFileSystemObjectSource\|makeMemoryPressureSource\|makeProcessSource\|makeTimerSource\|makeSignalSource\|makeReadSource\|makeWriteSource` | `queue:` 必须是 `.main`,否则事件处理闭包(继承 `@MainActor`)会在 X 上 trap |
| **C2** | `NotificationCenter/DistributedNotificationCenter.addObserver(... queue: X)` + `MainActor.assumeIsolated` | `addObserver.*queue:` | `queue:` 必须是 `.main`;`queue: nil` 时回调在**发帖线程**——若闭包体或 assumeIsolated 触达 main 隔离即危险 |
| **C3** | `Timer.scheduledTimer(... target:selector:)` / `Timer.init(... block:)` | `Timer\.scheduledTimer\|Timer\.init\|Timer\.publish` | Timer 在**调度它的 run loop** 上 fire;若 `@MainActor` 类的 Timer 不在 main run loop 调度,回调 trap。`target-action` 走 `@objc` 方法,需确认该方法隔离 |
| **C4** | `MainActor.assumeIsolated { … }` 全部站点 | `MainActor\.assumeIsolated\|assumeIsolated` | 每一处都要回答:"调用方**保证**在 main 吗?"——尤其是 **`deinit`** 和**`nonisolated` 方法** |
| **C5** | `@Sendable` / `DispatchQueue.global().async` / `Task.detached` 里捕获 `@MainActor` 类型并触达 main 隔离状态 | `DispatchQueue\.global\|Task\.detached\|@Sendable` | 必须 hop(`Task { @MainActor … }` / `MainActor.run` / `DispatchQueue.main.async`),且 hop 要在**访问 main 隔离之前** |

### 6.2 排查流程(推荐按此顺序)

1. **枚举**:用 §6.1 的 grep 锚点拉出全量调用点(见 §7 已预扫描结果)。
2. **定 queue / 线程**:对每个调用点,确认回调实际发生在哪个队列。看 API 文档(`queue:` 参数语义、`NotificationCenter` `queue: nil` = 发帖线程、`Timer` = 调度 run loop)。
3. **定闭包隔离**:确认闭包是否 `@Sendable`。`@Sendable` 闭包**不**继承上下文隔离(非隔离,无序言);非 `@Sendable` 闭包**继承**上下文隔离(带序言)。`DispatchSourceHandler`、`Timer` 的 `block:` 等**是非 `@Sendable`**。
4. **定 deinit 上下文**:`@MainActor` 类的 `deinit` 是 `nonisolated`;若 `deinit` 里用了 `MainActor.assumeIsolated`,必须确认该实例**只可能**在 main 上被释放(否则 trap)。NSCache / NSMapTable 等容器可能在后台线程驱逐 → `deinit` 后台跑。
5. **写触发测试**:对每个"罕见事件触发的回调"(dispatch source fire、memory warning、notification),写一个能**真正触发**它的测试。CI 没抓到本 bug 是因为没人触发 dispatch source fire。
6. **CI 绿是必要不充分**:complete 模式 + SwiftLint --strict + 全测试绿**不**等于运行时隔离安全。隔离序言只在回调真的发生时才跑。

### 6.3 高危信号(优先看)

- `queue: DispatchQueue.global()` / `queue: nil` / `queue: .global(qos: …)` 在 `@MainActor` 上下文里出现。
- `MainActor.assumeIsolated` 出现在 `deinit` 或 `nonisolated func` 里。
- 注释里写 "in practice runs on main"、"synchronous no-op assertion"——这是**假设**,不是**保证**;要追"假设靠什么成立"。
- commit message 写 "already hops to main" / "isolation-safe via hop"——按 §2.5 复核 hop 在序言之前还是之后。

---

## 7. 已预扫描候选清单(本仓库 HEAD)

> 用 §6.1 的 grep 锚点拉出,逐一定 queue/隔离。结论:**仅 `ApplicationImage` 一处确认 trap**;`deinit+assumeIsolated` 一处潜在风险(取决于 NSCache 后台驱逐);其余安全。

| 文件:行 | 模式 | queue / 回调线程 | 闭包隔离 | 结论 |
|---------|------|------------------|----------|------|
| `Maccy/ApplicationImage.swift:80` | C1 DispatchSource FS object | **`.global()`** ❌ | `@MainActor`(继承) | **🔴 本崩溃。改 `.main`** |
| `Maccy/ApplicationImage.swift:25-35` | C4 `deinit` + `assumeIsolated` | 取决于 NSCache 驱逐线程 | `nonisolated` deinit | **🟡 潜在**:NSCache 后台驱逐 → `deinit` 后台 → `assumeIsolated` trap。需确认 `ApplicationImage` 只在 main 释放(见 §8) |
| `Maccy/Observables/MemoryGovernance.swift:84-91` | C1 DispatchSource memory pressure | `.main` ✅ | `@MainActor`(继承) | ✅ 安全(handler 在 main 跑,序言过) |
| `Maccy/Observables/Popup.swift:88-113` | C2 `NSEvent.addLocalMonitorForEvents` | main run loop ✅ | 非 `@Sendable`,`assumeIsolated` 是 no-op | ✅ 安全(本地 monitor 在 main run loop fire) |
| `Maccy/Observables/Popup.swift:117-131` | C4 `deinit` + `assumeIsolated`(经 `deinitEventsMonitor`) | `Popup` 是进程生命期 singleton,`deinit` 实际不 fire | `nonisolated` | 🟢 理论安全(且 `removeMonitor` 线程安全,即便不 assumeIsolated 也行) |
| `Maccy/AppDelegate.swift:267-275` | C2 `NotificationCenter.addObserver` `queue: nil` | 发帖线程(KeyboardShortcuts 库内部) | 闭包体只调 `KeyboardShortcuts.disable` 静态方法,无 main 隔离触达 | 🟢 安全(无 `@MainActor` 触达,无序言) |
| `Maccy/AppDelegate.swift:285-373`(DEBUG) | C2 `DistributedNotificationCenter` `queue: .main` | `.main` ✅ | `assumeIsolated` no-op | ✅ 安全 |
| `Maccy/Observables/AppState.swift:204-216` | C2 `NotificationCenter` `queue: .main` | `.main` ✅ | `assumeIsolated` no-op | ✅ 安全 |
| `Maccy/Clipboard.swift:73-79` | C3 `Timer.scheduledTimer(target:selector:)` | `Clipboard` 是 `@MainActor`,`start()` 在 main → main run loop ✅ | `@objc @MainActor func checkForChangesInPasteboard` | ✅ 安全(Timer 在 main run loop fire) |
| `Maccy/Views/HeightReaderModifier.swift:17-19` | C4 `assumeIsolated` | SwiftUI geometry 回调在 main ✅ | — | ✅ 安全 |
| `Maccy/SoftwareUpdater.swift:41` | C4 `assumeIsolated` | Sparkle 回调;需确认在 main | — | 🟡 待确认(看 Sparkle delegate 的线程契约) |
| `Maccy/Observables/ModifierFlags.swift:20-24` | `deinit` 调 `NSEvent.removeMonitor` | — | 线程安全 API,无 `assumeIsolated` | ✅ 安全 |
| `Maccy/Settings/StorageSettingsPane.swift:60-62` | `deinit` 调 `observer?.invalidate()` | — | 线程安全 API,无 `assumeIsolated` | ✅ 安全 |
| `Maccy/Sorter.swift` | (audit 06-28 称"裸 class") | — | 实际已是 `@MainActor final class Sorter` | ✅ 已修(audit 描述过期) |
| `Maccy/Throttler.swift` | — | — | 文件为空(已删/未建) | ✅ 无风险 |

### 7.1 唯一确认 trap 点的复现

```sh
# 不可能在 CI 上稳定复现(需要真删一个 app bundle)。
# 验证路径:见 §5.3 的"补一个 rename/delete 触发测试"。
```

---

## 8. 次要风险:`ApplicationImage.deinit` + `MainActor.assumeIsolated` + NSCache 后台驱逐

`Maccy/ApplicationImage.swift:25-35`:

```swift
deinit {
  // ... "Instances live in the main-only ApplicationImageCache, so deinit
  //      runs on main in practice."
  MainActor.assumeIsolated {
    eventSource?.cancel()
  }
}
```

`ApplicationImageCache`(`Maccy/ApplicationImageCache.swift`)用 `NSCache<NSString, ApplicationImage>(countLimit: 128)`。NSCache 的语义:

- `setObject` 触发的 count 超限驱逐:在**调用线程**上同步发生——`getImage` 在 main(`@MainActor` cache)→ 驱逐在 main → `deinit` 在 main ✅
- `purge()`(由 `MemoryGovernor.handleMemoryWarning` 在 main 上调):main ✅
- **系统内存压力自动驱逐**:NSCache 响应系统内存压力自动 evict。该回调的线程**不是我们控制的**——可能后台。

若 NSCache 在后台线程自动驱逐 `ApplicationImage` → `deinit` 后台跑 → `MainActor.assumeIsolated` → `dispatch_assert_queue(main)` 失败 → **同样的 `SIGTRAP`**。

**这是与本崩溃同族的潜在 bug**:同样的 `dispatch_assert_queue_fail`,同样的 `brk 1`,只是触发路径不同(NSCache 内存压力驱逐 vs dispatch source fire)。

> **待确认 / 建议在排查中处理**:
> 1. 查 Apple 文档/实现:macOS 上 NSCache 自动驱逐是否可能后台线程?(iOS 上有 `NSCacheDelegate.cache:willEvictObject:` 回调,可在任意线程。)
> 2. 若可能:把 `deinit` 里的 `MainActor.assumeIsolated { eventSource?.cancel() }` 改成不依赖隔离的写法——`DispatchSource.cancel()` 本身**线程安全**(任意线程可调),只是 `eventSource` 属性访问受隔离。可考虑 `nonisolated(unsafe)` + 注释,或把 `eventSource` 持有改到一个 `nonisolated` 的 `os_unfair_lock`/`OSAllocatedUnfairLock` 包装里。
> 3. 写一个压测测试:制造 NSCache 后台驱逐场景,断言不 trap。

---

## 9. 下一步(用户"排查所有类似问题"的执行建议)

1. **先修主 bug**(§5.1):`ApplicationImage.swift:80` `queue: .global()` → `.main`。一行 + commit + 推 CI。
2. **补触发测试**(§5.3 + §7.1):让 dispatch source fire 被测试覆盖。这是防回归的唯一硬保证。
3. **按 §6 流程跑全量排查**:本 README §7 已预扫描,但建议用一个 workflow 多 agent 并行复核(每个 agent 认领一类 C1–C5,独立给出 queue/隔离判定 + 证据),再汇总——避免单人漏判。可选:用户授权后用 `Workflow` 跑。
4. **深挖 §8 的 NSCache deinit 风险**:可能需要专门查 Apple 文档 / 写压测。
5. **更新 06-28 gap-audit**:`03-bs7-swift6-gaps.md` 7.4 从 ⚠️ 部分完成 → 🔴 已确认运行时崩溃(本崩溃证伪"经 main hop 隔离安全");并修正 §0 的 7.4 描述。同时回填 step-7-swift6.md 的 7.4 checkbox 状态。
6. **更新 INDEX.md**:在权威导航里挂上本目录(已在本 README 同目录)。

### 9.1 排查时可用工具

- **`mcp__sosumi__searchAppleDocumentation` / `fetchAppleDocumentation`**:确认 API 的 closure 类型是否 `@Sendable`、`queue:` 参数语义(本文已用它确认 `DispatchSourceHandler = () -> Void`)。
- **Context7**:第三方库(KeyboardShortcuts、Sparkle)的回调线程契约。
- **`grep -rEn`**:本 README §6.1 的锚点。
- **CI**:每改一处推一个 run,`gh run view` 查 `Lint + diagnostics` + 各 shard。

---

## 10. 方法论沉淀(给后续 BS-7/BS-8 工作的一句话)

> **"complete 模式编译过" ≠ "运行时隔离安全"。**
> `@MainActor` 序言是**运行时**断言;任何被 dispatch/Timer/notification 在**非主队列**回调的**非 `@Sendable`** 闭包,只要它从 `@MainActor` 上下文继承了隔离,就会在该回调时 `brk`。
> 判据不是"代码里有没有 hop",而是"回调的 `queue:` / 实际线程是不是 main"。
> `deinit + MainActor.assumeIsolated` 是同族陷阱:容器(NSCache 等)后台驱逐 → `deinit` 后台跑 → 同样 trap。

---

## 附录 A:崩溃报告关键字段速查

```
Process:        Maccy [10921]
Version:        2.6.1 (60)              ← 本地未签名构建(codeSigningTeamID: "")
Exception Type: EXC_BREAKPOINT (SIGTRAP)
Exception Codes: 0x0000000000000001, 0x000000018a5504fc
Triggered by Thread: 5, Dispatch queue: com.apple.root.default-qos
Termination Reason: Namespace SIGNAL, Code 5, Trace/BPT trap: 5

关键帧:
  _dispatch_assert_queue_fail
  _swift_task_checkIsolatedSwift
  swift_task_isCurrentExecutorWithFlagsImpl
  closure #1 in ApplicationImage.nsImage.getter + 292
  _dispatch_source_latch_and_call        ← dispatch source 回调
  _dispatch_kevent_worker_thread         ← 后台 kevent worker

procLaunch: 2026-07-04 09:00:23.7386 +0800
崩溃时间:    2026-07-04 23:24:21.6721 +0800   ← 启动后 ~14h20m(潜伏,等 source fire)
```

## 附录 B:关键源码片段(崩溃点)

`Maccy/ApplicationImage.swift:38-112`(`nsImage` getter 的 dispatch source 段):

```swift
@MainActor
class ApplicationImage {
  // ...
  var nsImage: NSImage {
    // ...
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.delete, .rename],
      queue: DispatchQueue.global()      // ← FIX: DispatchQueue.main
    )
    source.setEventHandler { [weak self] in   // 继承 @MainActor(DispatchSourceHandler 非 @Sendable)
      DispatchQueue.main.async { [weak self] in  // ← 在序言之后,救不了
        guard let self, let eventSource = self.eventSource else { return }
        let event = eventSource.data
        if event.contains(.delete) {
          self.eventSource?.cancel(); self.eventSource = nil; self.image = nil
        } else if event.contains(.rename) {
          self.image = NSWorkspace.shared.icon(forFile: appURL.path)
        }
      }
    }
    source.setCancelHandler { close(descriptor) }
    eventSource = source
    source.resume()
    // ...
  }
}
```

---

**文档状态**:2026-07-05 初版。主 bug 未修(待用户确认后改 `queue: .main` + 推 CI)。`§8` deinit 风险待查证。`§7` 预扫描覆盖 C1–C5 主要调用点。

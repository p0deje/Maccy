# Gauge Maccy Plugin

A [Gauge](https://github.com/ebowwa/gauge) menu-bar plugin that turns your
clipboard into a lightweight history card in the Gauge tray popover — the
**even-more-lightweight Maccy**: no app bundle, no settings window, no
SwiftData, no updater. The heavy lifting lives in the slim companion agent
([`../maccy-agent`](../maccy-agent/README.md)), a LaunchAgent that captures
clipboard history even while Gauge is closed; this plugin renders the recent
items and restores them on tap.

This repo (the Maccy checkout) is the plugin's **source of truth** — it ships
with the product whose history it renders. The gauge repo holds only the
catalog entry + release config (`plugin-catalog/plugins.json`,
`plugins/publish.json`) once the Developer ID lane is unblocked. Consumed SDK:
[GaugePluginKit](https://github.com/ebowwa/gaugepluginkit) via SPM.

## What it shows

A fixed four-region card (constant height, deterministic first layout — see
[TRAY-GUIDELINES.md](https://github.com/ebowwa/gauge/blob/master/plugins/TRAY-GUIDELINES.md)):

1. **Status row** — dot (green = agent alive, orange pulsing = ⌘V paste
   armed, gray = agent off) · "Maccy" · trailing `N items · 2m ago` (plus
   `copy only` when Gauge lacks the Accessibility grant).
2. **Items area** — exactly 6 fixed-height rows, newest first: `📎` file
   copies, `🖼` images, `•` text. Titles are single-line truncated,
   `2m ago`-style trailing time. Row count never changes — pages swap
   CONTENT only.
3. **Paging footer** — `← prev · 1/2 · more →`; hidden (empty fixed slot)
   when one page fits.
4. **Agent affordance** — when the agent is not alive, the footer becomes
   `agent not running · Start` (kickstarts the LaunchAgent).

**Tap = restore:** copies the item back to the system clipboard (marker type
set so the agent never re-captures it) and — when Gauge is
Accessibility-trusted — **arms a one-shot ⌘V that fires when the popover
closes**, so the paste lands in the real frontmost app. Without the grant,
items copy only. That delayed ⌘V is deliberate: posting while the popover is
open would paste into the popover itself.

## Data source

`maccy-agent` publishes the capped history at:

```
~/Library/Application Support/maccy-agent/history.json
```

- **Override for dev/tests:** set `MACCY_HISTORY_PATH` to any JSON file with
  the same shape — the store reads it instead of the primary path.
- If the primary path is missing, the store globs
  `~/Library/Application Support/maccy-agent*/history.json` and uses the most
  recently modified one (variant install dirs).
- Decoding is fully tolerant: unknown keys ignored, any field may be missing,
  null, or wrongly typed (degrades to `nil`), dates accept ISO 8601
  with/without fractional seconds and epoch seconds/millis, images are base64.
  Malformed data renders placeholders / the not-running state — never a crash.
- **Liveness = mtime freshness:** the agent heartbeats the file's mtime every
  120 s, so a live agent stays fresh and a crashed one goes stale within 300 s
  (the squeakd "process check is the authority" lesson, expressed through the
  heartbeat instead of an app process).
- Updates arrive via a debounced `DispatchSource` file watcher on the primary
  path, plus a 3s poll while the popover is open (started/stopped by the host's
  `menuWillOpen`/`menuDidClose`). Reads run on a utility queue; the main
  thread is never blocked.

## Install with Gauge

Two ways to get the Maccy tray card:

1. **From the secondsee.com distribution (end users)** — the plugin ships
   through **Gauge's plugin catalog** (`secondsee.com/downloads/gauge/plugins/…`).
   Install **Gauge** itself from secondsee.com first (Gauge is **not open
   source** — you cannot clone and build it locally; the host app, the
   `GaugePluginKit` SDK contract, and the tray are only distributed there),
   then add this plugin the same way you add the AI Sessions / Squeakd cards.
   The companion `maccy-agent` is downloadable from the same product page and
   installed with its `install.sh` (LaunchAgent — captures even while Gauge
   is closed).
2. **As a developer (this checkout)** — build and install locally:
   `./build.sh --install`, relaunch Gauge, and run
   `cd ../maccy-agent && ./install.sh` for the companion. Detail below.

## Build, install, package

```bash
./build.sh              # build + sign → build/Build/Products/Release/GaugeMaccyPlugin.gaugeplugin
./build.sh --install    # … and copy into ~/Library/Application Support/Gauge/Plugins/
./build.sh --package    # … and zip into build/GaugeMaccyPlugin.gaugeplugin.zip (ditto)
```

Requires `xcodegen` and `xcodebuild` (the script checks and offers
`brew install xcodegen`). `--install` and `--package` can combine.
**Gauge must be relaunched after installing** — plugins load at launch, not
hot. The companion agent is installed separately:
`cd ../maccy-agent && ./install.sh`.

### Signing

`build.sh` prefers a **Developer ID Application** identity from
`security find-identity -v -p codesigning` and signs with hardened runtime.
With none available it falls back to **ad-hoc** (`codesign --force --deep -s -`,
no runtime flag). Gauge ships `disable-library-validation`, so both load.
`CFBundleVersion` is stamped with `git rev-list --count HEAD` (mirrors the
squeakd/reflex scripts) so a stale install is detectable via
`profilingSnapshot`/Info.plist.

## Host contract

Conforms to **GaugePluginKit**'s `GaugePlugin` protocol — the official plugin
SDK ([ebowwa/gaugepluginkit], SPM `from: "0.1.0"`). The host probes an
informal `@objc` selector boundary (the kit is a static library; each plugin
links its own copy, version skew tolerated), so the principal class keeps the
`@objc` members and adds the kit's view entry:

- `var pluginID: String { get }` — `com.ebowwa.gauge.plugin.maccy`
- `var displayName: String { get }` — `"Maccy"`
- `func makeMenuBlockView() -> AnyView` — `MaccyMenuBlock`, sharing ONE static
  history store; `@objc makeMenuView() -> NSView` wraps it in an `NSHostingView`
  for the host's selector probe
- `func menuWillOpen()` / `func menuDidClose()` — refresh + poll lifecycle;
  `menuDidClose` also fires the armed ⌘V
- `@objc func profilingSnapshot() -> NSDictionary` — `found`, `fileAge`,
  `fileFresh`, `agentAlive`, `itemCount`, `lastCapturedAt`, `axTrusted`,
  `pendingAutoPaste`, `version`

Building requires GitHub auth for the private SDK fetch (`gh auth setup-git`).

## Headless load test

`tests/load-test.swift` does exactly what the host does (bundle load,
principal class, selector asserts, `makeMenuView()` on the main thread,
offscreen-window layout), and with the sample template it stages a temp copy
with fresh timestamps and points the store at it via the `MACCY_HISTORY_PATH`
env override:

```bash
swiftc -O tests/load-test.swift -o build/load-test
build/load-test build/Build/Products/Release/GaugeMaccyPlugin.gaugeplugin tests/sample-history.json
# → PASS: bundle loads, contract holds, menu view materializes, sample history decodes
```

## Catalog publishing (deferred)

Deferred until the Developer ID Application cert (team **42R8ZPM5N8**) is
provisioned on this machine. Steps when unblocked:

1. Import the Developer ID Application identity into the login keychain and
   confirm `security find-identity -v -p codesigning` lists it.
2. `SIGN_IDENTITY=<hash> ./build.sh build --package` — the script will then
   pick the Developer ID identity automatically (hardened runtime).
3. Add the catalog entry + build wiring in the **gauge repo** (this fork only
   owns the source; the catalog/release lane live there):
   - `plugin-catalog/plugins.json` — new `com.ebowwa.gauge.plugin.maccy`
     entry: name `Maccy`, kind `gaugeplugin` artifact pointing at
     `https://secondsee.com/downloads/gauge/plugins/GaugeMaccyPlugin.gaugeplugin.zip`,
     plus the `maccy-agent` companion as the second artifact (kind `app`),
     both with the sha256 printed by `--package`.
   - `plugins/publish.json` — build wiring
     `{ "repo": "ebowwa/Maccy", "dir": "plugins/gauge-plugin", "cmd": "./build.sh --package" }`
     (the lane does a `--depth=1` clone of `ebowwa/Maccy`; changes must be
     merged to `master` before dispatch).
4. Dispatch `plugins-release` on the gauge repo for `maccy`; the lane bumps
   `MARKETING_VERSION`, builds, uploads to R2, live-verifies, and patches the
   catalog with the fresh sha256/`?v=`. Gauge updates the plugin on next
   launch.

The full distribution story (end-user install via secondsee.com, developer
local install, and the Gauge-is-not-open-source note) is in
[docs/gauge-integration.md](../../docs/gauge-integration.md).

## Files

```
plugins/gauge-plugin/
├── project.yml                  # xcodegen (target GaugeMaccyPlugin, macOS 13.0; GaugePluginKit SPM dep)
├── Info.plist                   # NSPrincipalClass $(PRODUCT_MODULE_NAME).MaccyPlugin
├── build.sh                     # build / sign / --install / --package (mirrors squeakd lane)
├── Sources/
│   ├── MaccyPlugin.swift        # principal class (GaugePluginKit GaugePlugin + @objc host selectors)
│   ├── MaccyHistory.swift       # tolerant Codable schema + MaccyHistoryStore + pasteboard restore/⌘V
│   └── MaccyMenuBlock.swift     # SwiftUI tray card (TRAY-GUIDELINES compliant, paged)
├── tests/
│   ├── load-test.swift          # headless host-contract test
│   └── sample-history.json      # 8-item sample with FRESH-timestamp placeholders
└── README.md
```

[ebowwa/gaugepluginkit]: https://github.com/ebowwa/gaugepluginkit
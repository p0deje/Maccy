# Gauge Maccy Integration — the lightweight Maccy, end to end

**tl;dr**: this fork turns Maccy into a *background clipboard companion* whose
only user surface is a live history card in the **Gauge** menu-bar tray. No
app bundle to babysit, no Dock icon, no Cmd-Tab presence, no Settings window —
a headless `maccy-agent` captures your clipboard history 24/7 and the Gauge
tray card shows the recent items; tapping one restores it (and pastes it, when
the Accessibility grant is in place).

This is the "even-more-lightweight Maccy": the heavy parts that made the app
a standalone citizen (SwiftData storage, AppIntents, the Settings window, the
updater, the app-store machinery) are gone. Maccy.app itself was already a
menu-bar-only app (`LSUIElement`); the product is now even further off the
dock — the agent has **no UI at all**, and **Gauge is the unified surface**.

## Architecture

```
any app copy → pasteboard → maccy-agent (LaunchAgent, always on, headless)
                                ↓  capped JSON history, atomic writes, mtime heartbeat
    ~/Library/Application Support/maccy-agent/history.json
                                ↓  DispatchSource watcher + poll-while-open
                       GaugeMaccyPlugin tray card (paged recent items)
                                ↓  tap → item restored to pasteboard (+⌘V if AX)
```

| Piece | What it is | Where it lives |
|---|---|---|
| `maccy-agent` | The clipboard companion: single Swift CLI, LaunchAgent (`RunAtLoad` + `KeepAlive`), captures even when Gauge is closed | `plugins/maccy-agent/` |
| `GaugeMaccyPlugin` | The tray card: GaugePluginKit bundle, rendered inside Gauge's process | `plugins/gauge-plugin/` |
| `Gauge` | The host app (menu-bar tray). **Not open source** — see below | installed from secondsee.com |

The two halves talk through exactly one file: the agent **writes**
`history.json`, the plugin **reads** it (lenient decode — any field may be
missing/wrong-typed and the card still renders). A marker pasteboard type
(`com.ebowwa.maccy.agent.copied`) stops the agent from re-capturing its own
restores.

## Using it

- Open Gauge's tray → **Maccy** card shows the newest items: `•` text, `📎`
  file copies, `🖼` images, each with a relative age.
- The status row shows `N items · 2m ago` (and `copy only` when Gauge lacks
  the Accessibility grant — see below).
- **Tap an item** → it goes back on your clipboard. When Gauge is
  Accessibility-trusted, the card arms a one-shot **⌘V** that fires as soon
  as you close the tray — so the item lands in the app you're typing into,
  exactly like Maccy's auto-paste. Without the grant, items copy only (you
  paste manually).
- Paging: more than 6 items → `← prev · 1/2 · more →` in the footer.
- If the agent isn't running, the footer shows `agent not running · Start`
  (kickstarts the LaunchAgent).

## Installing

### End users — install with Gauge, from secondsee.com

> **Gauge is not open source.** You cannot clone it and build the host app
> locally — the host, the `GaugePluginKit` SDK contract, and the tray are
> only distributed through our **secondsee.com** distribution platform. To
> use the Maccy card you install Gauge from there first.

1. **Install Gauge** from secondsee.com (the menu-bar host).
2. **Install the Maccy plugin** from the secondsee.com product page — the
   catalog entry carries a signed `GaugeMaccyPlugin.gaugeplugin.zip`
   (`secondsee.com/downloads/gauge/plugins/…`); Gauge picks it up on its next
   launch (plugins load at launch, not hot).
3. **Install the companion agent** from the same product page:
   `maccy-agent-<version>.zip` → unzip → `./install.sh`. That registers the
   LaunchAgent; from then on the history captures in the background whether
   or not Gauge is running.

No compiler, no Xcode, no checkout involved. (Distribution note: catalog
publishing is **deferred until the Developer ID Application certificate** is
provisioned — see `plugins/gauge-plugin/README.md` → Catalog publishing.
Until then the plugin loads ad-hoc on machines that trust it locally.)

### Developers — install from this checkout

Prerequisites: Xcode command-line tools (`xcodebuild`, `swiftc`),
[xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`),
and `gh auth setup-git` (the plugin's SDK, `GaugePluginKit`, is a private
SPM package).

```bash
# 1. the companion agent → LaunchAgent (captures immediately)
cd plugins/maccy-agent
./install.sh                 # build + register + start

# 2. the tray plugin
cd ../gauge-plugin
./build.sh --install         # build + sign + copy into ~/Library/Application Support/Gauge/Plugins
# 3. RELAUNCH Gauge (plugins load at launch)
```

Verify with the headless host-contract test:

```bash
cd plugins/gauge-plugin
swiftc -O tests/load-test.swift -o build/load-test
build/load-test build/Build/Products/Release/GaugeMaccyPlugin.gaugeplugin tests/sample-history.json
# → PASS: bundle loads, contract holds, menu view materializes, sample history decodes
```

And the agent's end-to-end gate (real pasteboard):

```bash
cd plugins/maccy-agent
./tests/verify.sh            # 12 cases: capture/caps/dedupe/marker/heartbeat/restart
```

Uninstall: `cd plugins/maccy-agent && ./install.sh uninstall` and remove the
plugin from `~/Library/Application Support/Gauge/Plugins/`.

## Operational notes

- **Gauge must be relaunched after any plugin install** — plugins load at
  launch only.
- **⌘V auto-paste needs the Accessibility grant for Gauge's process** (System
  Settings → Privacy & Security → Accessibility). Until granted, the card is
  honest: the status row shows `copy only` and taps copy without pasting.
- **Liveness = file freshness.** The agent heartbeats `history.json`'s mtime
  every 120 s; a crashed agent renders `agent not running` within ~5 minutes.
  The card's `Start` button kickstarts the LaunchAgent.
- History caps: 200 items, images ≤ 2 MB each (larger images aren't
  recorded). Adjacent duplicates collapse. Restores never re-capture (marker
  type).

## Distribution plumbing

The fork owns the source; the release lane lives in the **gauge repo**
(`plugin-catalog/plugins.json`, `plugins/publish.json`,
`.github/workflows/plugins-release.yml`). The ready-to-apply wiring for this
product:

- **Catalog entry** (`plugin-catalog/plugins.json`): id
  `com.ebowwa.gauge.plugin.maccy`, name `Maccy`; artifacts (kind `gaugeplugin`)
  `GaugeMaccyPlugin.gaugeplugin.zip` and (kind `app`)
  `maccy-agent-<version>.zip`, both at
  `https://secondsee.com/downloads/gauge/plugins/`, sha256 from each
  `--package`.
- **Build wiring** (`plugins/publish.json`):
  `{ "repo": "ebowwa/Maccy", "dir": "plugins/gauge-plugin", "cmd": "./build.sh --package" }`
  (external repo — the lane deep-clones `ebowwa/Maccy`, so changes must be
  merged to `master` before dispatch).
- Packaging locally, without the lane:
  `cd plugins/gauge-plugin && ./build.sh build --package` and
  `cd ../maccy-agent && ./build.sh build --package` → two zips + sha256s in
  each `build/`.

End users get all of this through the product page / Gauge's catalog; see
[Install with Gauge](../plugins/gauge-plugin/README.md#install-with-gauge).
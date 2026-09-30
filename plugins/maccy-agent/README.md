# maccy-agent — the lightweight Maccy clipboard companion

The **even-more-lightweight Maccy**: a single Swift CLI (no app bundle, no
menu bar item, no Settings window, no SwiftData, no AppIntents, no updater)
that watches the pasteboard, keeps a **capped** clipboard history, and
publishes it as one JSON file for the [Gauge Maccy plugin](../gauge-plugin/)
to render in the tray. Derived from Maccy's `Clipboard.swift` engine, stripped
to: capture → cap → persist → heartbeat.

## Why a companion instead of a pure plugin

The user picks *squeakd-style*: the agent runs as a LaunchAgent, so **clipboard
history is captured even while Gauge is closed**. The plugin (GaugeMaccyPlugin)
only renders the history and restores items — no pasteboard access of its own
beyond writing the restored item back.

## Data flow

```
any app copy → pasteboard → maccy-agent (LaunchAgent, always on)
                                ↓  atomic JSON write, capped, mtime-heartbeat
    ~/Library/Application Support/maccy-agent/history.json
                                ↓  DispatchSource watcher + poll-while-open
                       GaugeMaccyPlugin tray card (recent items, paged)
                                ↓  click → write item back to pasteboard (+⌘V if AX)
```

## History file

```json
{
  "schemaVersion": 1,
  "version": "0.1.0",
  "publishedAt": "…",
  "itemCount": 12,
  "lastCapturedAt": "…",
  "items": [
    { "id": "…", "capturedAt": "…", "app": "com.apple.Safari",
      "title": "first line of the copy", "string": "…",
      "fileURLs": ["/Users/me/a.txt"], "image": "base64…", "imageType": "png" }
  ]
}
```

- **Caps (defaults, overridable):** 200 items; images ≤ 2 MB each (larger
  images are not recorded).
- **Dedupe:** an item whose `title` equals the current head is skipped — the
  common "copy / paste / copy again" case and plugin restores stay silent
  (restores also carry the marker type below).
- **Atomic writes:** `Data.write(.atomic)` — a crash mid-write can never leave
  a truncated file for the plugin.
- **Heartbeat:** the agent refreshes the file's mtime every 120 s even with no
  copies; the plugin treats mtime freshness as the agent-liveness authority
  (a live agent stays fresh, a crashed one goes stale in ≤ 2 checks).

## Marker type

`com.ebowwa.maccy.agent.copied` — set by the plugin on the pasteboard whenever
it restores an item. The agent skips captures carrying it, so restoring never
re-captures (Maccy's `org.p0deje.Maccy` pattern, namespaced).

## Install / build

```bash
./build.sh            # swift build -c release → .build/release/maccy-agent
./install.sh          # build + copy to ~/Library/Application Support/maccy-agent/
                      #   + LaunchAgent ~/Library/LaunchAgents/com.ebowwa.maccy.agent.plist + start
./install.sh uninstall
```

The LaunchAgent runs with `RunAtLoad` + `KeepAlive` — capture survives
reboots, Gauge being closed, and agent crashes (auto-restart). Logs go to
`~/Library/Application Support/maccy-agent/maccy-agent.log`.

## Dev / test

```bash
swift build
.build/debug/maccy-agent --history-path /tmp/h.json --once          # one check
.build/debug/maccy-agent --history-path /tmp/h.json                 # daemon
cp some-text; .build/debug/maccy-agent --history-path /tmp/h.json --once
python3 -c 'import json;print(json.dumps(json.load(open("/tmp/h.json")),indent=1))'
```

## Options

| Flag | Default | Meaning |
|---|---|---|
| `--history-path` | `~/Library/Application Support/maccy-agent/history.json` | where the history file lives |
| `--max-items` | 200 | history cap (newest N kept) |
| `--max-image-bytes` | 2097152 | images larger than this are not recorded |
| `--check-interval` | 1.0 s | pasteboard changeCount poll |
| `--heartbeat-interval` | 120.0 s | mtime refresh while quiet |
| `--once` | off | single check then exit (tests) |

## Scope notes

- **No signing** — a local LaunchAgent CLI doesn't need a signature (the
  catalog-shippable plugin is the signed artifact; see the plugin README).
- **No Accessibility requirement** — the agent only *reads* the pasteboard.
  ⌘V auto-paste (Gauge Maccy plugin) needs the Accessibility grant for
  **Gauge's** process, not this agent.
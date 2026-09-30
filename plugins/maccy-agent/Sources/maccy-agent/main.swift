//
//  main.swift
//  maccy-agent
//
//  CLI entry: parse options, fire up the watcher + heartbeat timers, stay
//  alive on the main run loop. Also `--once` for tests (one check, exit).
//
//  Usage:
//    maccy-agent                                              # daemon (defaults)
//    maccy-agent --history-path /tmp/h.json --max-items 50    # overrides
//    maccy-agent --once                                       # single check, exit
//

import Foundation

var historyURL = defaultHistoryURL()
var maxItems = 200
var maxImageBytes = 2 * 1024 * 1024
var checkInterval: TimeInterval = 1.0
var heartbeatInterval: TimeInterval = 120.0
var once = false
var verbose = false

let args = CommandLine.arguments
var i = 1
while i < args.count {
    switch args[i] {
    case "--history-path":
        i += 1
        if i < args.count { historyURL = URL(fileURLWithPath: (args[i] as NSString).expandingTildeInPath) }
    case "--max-items":
        i += 1
        if i < args.count, let n = Int(args[i]) { maxItems = n }
    case "--max-image-bytes":
        i += 1
        if i < args.count, let n = Int(args[i]) { maxImageBytes = n }
    case "--check-interval":
        i += 1
        if i < args.count, let n = Double(args[i]) { checkInterval = n }
    case "--heartbeat-interval":
        i += 1
        if i < args.count, let n = Double(args[i]) { heartbeatInterval = n }
    case "--once":
        once = true
    case "--verbose":
        verbose = true
    default:
        fputs("maccy-agent: unknown argument \(args[i])\n", stderr)
        exit(2)
    }
    i += 1
}

let store = HistoryStore(url: historyURL, maxItems: maxItems, maxImageBytes: maxImageBytes)
let watcher = ClipboardWatcher(store: store)
watcher.verbose = verbose

// Ensure the file exists on first run so the plugin sees a valid (empty)
// snapshot immediately instead of "no file yet".
store.persist()

if once {
    _ = watcher.checkForChanges()
    exit(0)
}
print("maccy-agent \(maccyAgentVersion) — history: \(historyURL.path) (max \(maxItems) items, images ≤ \(maxImageBytes) bytes)")

// DispatchSourceTimers on the main queue: RunLoop.main timers are NOT
// serviced by dispatchMain() in a bare CLI (no NSApplication), so Timer-based
// ticks silently never fire. GCD timers on the main queue keep the AppKit
// pasteboard/workspace calls on the main thread while firing reliably.
let captureTimer = DispatchSource.makeTimerSource(queue: .main)
captureTimer.schedule(deadline: .now() + 1.0, repeating: checkInterval)
captureTimer.setEventHandler { _ = watcher.checkForChanges() }
captureTimer.resume()

let heartbeatTimer = DispatchSource.makeTimerSource(queue: .main)
heartbeatTimer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
heartbeatTimer.setEventHandler { store.heartbeat() }
heartbeatTimer.resume()

// Clean shutdown on SIGTERM (launchctl stop / bootout).
signal(SIGTERM, SIG_IGN)
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigSource.setEventHandler { exit(0) }
sigSource.resume()

dispatchMain()
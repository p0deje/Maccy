//
//  load-test.swift — headless host-contract test for GaugeMaccyPlugin.
//
//  Does EXACTLY what Gauge's PluginManager does: Bundle(url:).load(), read
//  NSPrincipalClass from Info.plist, instantiate the principal class, assert
//  the informal @objc contract (pluginID / displayName / makeMenuView, plus
//  the optional menuWillOpen / menuDidClose / profilingSnapshot hooks), then
//  call makeMenuView() on the main thread and force SwiftUI→AppKit layout so
//  the menu block materializes for real.
//
//  When given a sample-history.json template, it rewrites the placeholder
//  timestamps to fresh values, copies it to a TEMP path, and points the
//  plugin's history store at it via the MACCY_HISTORY_PATH environment
//  override. After pumping the run loop (async refresh + timers),
//  profilingSnapshot() must report the decoded sample.
//
//  Usage: load-test <path/to/GaugeMaccyPlugin.gaugeplugin> [sample-template.json]
//  Prints PASS/FAIL; exit 0 only on PASS.
//
//  NOTE: loading a second copy of the plugin in this test process is safe
//  (plain bundle load, no IPC with the host) even while Gauge is running.
//

import AppKit

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("usage: load-test <plugin.gaugeplugin> [sample-template.json]")
}
let pluginPath = args[1]
let sampleTemplatePath = args.count > 2 ? args[2] : nil

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

// --- Stage the sample history at a temp path with fresh timestamps ---------
if let sampleTemplatePath {
    let fm = FileManager.default
    guard let template = try? String(contentsOfFile: sampleTemplatePath, encoding: .utf8) else {
        fail("cannot read sample template at \(sampleTemplatePath)")
    }
    func iso(_ offset: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(offset))
    }
    var fresh = template
        .replacingOccurrences(of: "PUBLISHED_AT_FRESH", with: iso(0))
    for index in 0...7 {
        fresh = fresh.replacingOccurrences(
            of: "CAPTURED_AT_\(index)",
            with: iso(-Double(60 * (index + 1)))
        )
    }
    let tempURL = fm.temporaryDirectory
        .appendingPathComponent("maccy-history-sample-\(UUID().uuidString).json")
    do {
        try fresh.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
        fail("cannot write temp sample: \(error)")
    }
    // Must happen BEFORE the store is created (plugin instantiation).
    setenv("MACCY_HISTORY_PATH", tempURL.path, 1)
    print("sample history staged at: \(tempURL.path)")
}

// --- Load the bundle the way the host does -----------------------------------
guard FileManager.default.fileExists(atPath: pluginPath) else {
    fail("plugin not found at \(pluginPath)")
}
guard let bundle = Bundle(url: URL(fileURLWithPath: pluginPath)) else {
    fail("Bundle(url:) returned nil for \(pluginPath)")
}
guard bundle.load() else {
    fail("Bundle.load() returned false")
}
let principalName = bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String ?? "?"
guard let principalClass = bundle.principalClass else {
    fail("principalClass lookup failed for NSPrincipalClass=\(principalName)")
}
guard let instance = (principalClass as? NSObject.Type)?.init() else {
    fail("principal class \(principalName) failed to instantiate")
}

// --- Assert the informal @objc contract --------------------------------------
let requiredSelectors = ["pluginID", "displayName", "makeMenuView"]
for name in requiredSelectors {
    guard instance.responds(to: Selector(name)) else {
        fail("principal class does not respond to required selector \(name)")
    }
}
let optionalSelectors = ["menuWillOpen", "menuDidClose", "profilingSnapshot"]
for name in optionalSelectors {
    guard instance.responds(to: Selector(name)) else {
        fail("principal class does not implement optional hook \(name)")
    }
}
guard let pluginID = instance.value(forKey: "pluginID") as? String else {
    fail("pluginID is not a String")
}
guard pluginID == "com.ebowwa.gauge.plugin.maccy" else {
    fail("pluginID mismatch: \(pluginID)")
}
guard let displayName = instance.value(forKey: "displayName") as? String, displayName == "Maccy" else {
    fail("displayName mismatch: \(String(describing: instance.value(forKey: "displayName")))")
}
print("contract: pluginID=\(pluginID) displayName=\(displayName)")

// --- Materialize the menu view (SwiftUI → AppKit layout) ---------------------
guard let view = instance.value(forKey: "makeMenuView") as? NSView else {
    fail("makeMenuView did not return an NSView")
}
view.frame = NSRect(x: 0, y: 0, width: 390, height: 190)
view.layoutSubtreeIfNeeded()
guard view.bounds.width > 0, view.bounds.height > 0 else {
    fail("menu view did not lay out (bounds \(view.bounds))")
}
// Attach to an offscreen borderless window (never ordered on) so the full
// SwiftUI render pass runs — text layout, buttons, all rows.
let window = NSWindow(
    contentRect: NSRect(x: -20000, y: -20000, width: 390, height: 190),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.contentView = view
window.layoutIfNeeded()
view.layoutSubtreeIfNeeded()
print("menu view materialized: \(type(of: view)) bounds=\(view.bounds.size) subviews=\(view.subviews.count) (window-attached, offscreen)")

func pumpRunLoop(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
}

// --- Let the async history refresh land, then check profilingSnapshot -------
pumpRunLoop(1.5)
guard let profile = instance.value(forKey: "profilingSnapshot") as? NSDictionary else {
    fail("profilingSnapshot did not return an NSDictionary")
}
print("profilingSnapshot: \(profile)")
guard let found = profile["found"] as? Bool, found == true else {
    fail("history file not found (found=false)")
}
if sampleTemplatePath != nil {
    guard let fileAge = profile["fileAge"] as? Double, fileAge >= 0, fileAge < 60 else {
        fail("fileAge missing or implausible: \(String(describing: profile["fileAge"]))")
    }
    guard let agentAlive = profile["agentAlive"] as? Bool, agentAlive == true else {
        fail("staged sample should be fresh → agentAlive=true, got \(String(describing: profile["agentAlive"]))")
    }
    guard let itemCount = profile["itemCount"] as? Int, itemCount == 8 else {
        fail("itemCount not decoded from sample: \(String(describing: profile["itemCount"]))")
    }
    guard let version = profile["version"] as? String, version == "0.1.0" else {
        fail("version not decoded from sample: \(String(describing: profile["version"]))")
    }
}

// --- Exercise the lifecycle hooks --------------------------------------------
instance.perform(Selector("menuWillOpen")) // starts the 3s poll timer
pumpRunLoop(2.5)                           // ≥2 ticks of the 1s text timer
instance.perform(Selector("menuDidClose")) // stops the poll timer, fires armed paste
guard let profile2 = instance.value(forKey: "profilingSnapshot") as? NSDictionary else {
    fail("profilingSnapshot (2nd read) did not return an NSDictionary")
}
print("profilingSnapshot after menu cycle: \(profile2)")

// --- Restore path: drive the real restore code via the diagnostics hook ------
// A tray tap runs `MaccyPasteboard.restore(item)` + `armAutoPaste()`; the
// hook exercises exactly that (without the SwiftUI button press, which is
// windowed). The pasteboard must then carry the item's string AND the
// agent-skip marker (so maccy-agent never re-captures the restore).
// NOTE: no menuDidClose after this — an armed ⌘V would otherwise fire into
// whatever app is frontmost.
if sampleTemplatePath != nil {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString("PRESET-SEED-VALUE", forType: .string)

    let json = #"{"id":"restore-test","capturedAt":null,"app":"com.apple.TextEdit","title":"Gauge Maccy plugin sample — newest text item, deliberately long enough to show tail truncation doing its job in the tray","string":"Gauge Maccy plugin sample — newest text item, deliberately long enough to show tail truncation doing its job in the tray"}"#
    guard let returned = instance.perform(Selector(("restoreItemFromJSON:")), with: json)?.takeUnretainedValue() as? String else {
        fail("restoreItemFromJSON did not return the restored string")
    }

    let restored = pb.string(forType: .string)
    guard restored == "Gauge Maccy plugin sample — newest text item, deliberately long enough to show tail truncation doing its job in the tray" else {
        fail("restore did not write the item's string to the pasteboard (got: \(String(describing: restored)))")
    }
    guard returned == restored else {
        fail("restoreItemFromJSON return (\(returned)) does not match pasteboard content (\(restored))")
    }
    let hasMarker = pb.availableType(from: [NSPasteboard.PasteboardType("com.ebowwa.maccy.agent.copied")]) != nil
    guard hasMarker else {
        fail("restore did not write the agent-skip marker type")
    }
    print("restore: item string on pasteboard, agent-skip marker present (no re-capture)")

    if let profile3 = instance.value(forKey: "profilingSnapshot") as? NSDictionary {
        print("profilingSnapshot after restore: \(profile3)")
    }
}

print("PASS: bundle loads, contract holds, menu view materializes" +
      (sampleTemplatePath != nil ? ", sample history decodes, restore/re-capture guard verified" : ""))
exit(0)
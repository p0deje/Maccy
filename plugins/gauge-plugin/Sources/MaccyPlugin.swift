//
//  MaccyPlugin.swift
//  GaugeMaccyPlugin
//
//  Principal class, conforming to GaugePluginKit's GaugePlugin protocol (the
//  official plugin contract). The host probes the informal @objc selectors
//  (see Gauge's targets/Gauge/3o/Managers/PluginManager.swift), so pluginID /
//  displayName / makeMenuView() and the optional menuWillOpen / menuDidClose /
//  profilingSnapshot hooks stay @objc; the kit conformance adds
//  makeMenuBlockView() so the plugin is a first-class SDK consumer.
//

import AppKit
import GaugePluginKit
import SwiftUI

@objc
final class MaccyPlugin: NSObject, GaugePlugin {

    static let pluginIdentifier = "com.ebowwa.gauge.plugin.maccy"

    /// ONE history store shared by every menu view the host materializes.
    /// Static so even a host re-instantiation of the principal class can never
    /// fork the state (or double the timers/watchers).
    private static let sharedStore = MaccyHistoryStore()

    // MARK: Required contract

    @objc var pluginID: String { Self.pluginIdentifier }

    @objc var displayName: String { "Maccy" }

    /// GaugePlugin (kit): the SwiftUI block. Single source of truth — the
    /// @objc host entry below wraps this view in an NSHostingView.
    @MainActor
    func makeMenuBlockView() -> AnyView {
        AnyView(MaccyMenuBlock(store: Self.sharedStore))
    }

    /// Host entry (PluginManager selector probe): NSView-wrapped block.
    @objc func makeMenuView() -> NSView {
        MainActor.assumeIsolated {
            NSHostingView(rootView: makeMenuBlockView())
        }
    }

    // MARK: Optional lifecycle hooks

    @objc func menuWillOpen() {
        // Immediate refresh + a 3s poll timer while the popover is open.
        Self.sharedStore.setMenuVisible(true)
    }

    @objc func menuDidClose() {
        // Stop the poll timer; the file watcher keeps state warm cheaply.
        // Also fires an armed ⌘V (the popover is closed by now, so the paste
        // lands in the real frontmost app).
        Self.sharedStore.setMenuVisible(false)
    }

    // MARK: Optional profiling hook

    @objc func profilingSnapshot() -> NSDictionary {
        let store = Self.sharedStore
        return [
            "found": store.fileFound,
            "fileAge": store.fileAge ?? -1,
            "fileFresh": store.isFileFresh,
            "agentAlive": store.isAlive,
            "itemCount": store.itemCount,
            "lastCapturedAt": store.lastCapturedAt.map { String(describing: $0) } ?? "",
            "axTrusted": store.axTrusted,
            "pendingAutoPaste": store.pendingAutoPaste,
            "version": store.snapshot?.version ?? "",
        ] as NSDictionary
    }
}
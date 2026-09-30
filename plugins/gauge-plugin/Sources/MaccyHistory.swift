//
//  MaccyHistory.swift
//  GaugeMaccyPlugin
//
//  Tolerant decode of the clipboard history JSON that maccy-agent publishes
//  (~/Library/Application Support/maccy-agent/history.json), plus the
//  observable store the tray block renders from.
//
//  Tolerance rules (same contract as the squeakd plugin): unknown JSON keys
//  are ignored, any field may be missing, null, or the wrong scalar type (it
//  degrades to nil instead of failing the whole decode), dates accept ISO
//  8601 with/without fractional seconds and epoch seconds/millis, and a nil
//  snapshot always renders as placeholders — never a crash.
//
//  Read path: MACCY_HISTORY_PATH env override, else the agent's default path,
//  falling back to a glob over ~/Library/Application Support/maccy-agent*/
//  (variant install dirs). Liveness: the agent heartbeats the file's mtime
//  every 120 s, so mtime freshness IS the agent-liveness authority (a live
//  agent stays fresh, a crashed one goes stale — same lesson as squeakd's
//  process check, expressed through the heartbeat).
//

import AppKit
import Combine
import Foundation

// Marker pasteboard type maccy-agent skips (restores never re-capture).
// Kept in sync with plugins/maccy-agent/Sources/maccy-agent/History.swift.
let maccyMarkerType = "com.ebowwa.maccy.agent.copied"

// MARK: - Schema

struct MaccyHistorySnapshot: Codable {
    let schemaVersion: Int?
    let version: String?
    let publishedAt: Date?
    let itemCount: Int?
    let lastCapturedAt: Date?
    let items: [MaccyHistoryItem]?

    struct MaccyHistoryItem: Codable {
        let id: String?
        let capturedAt: Date?
        let app: String?
        let title: String?
        let string: String?
        let fileURLs: [String]?
        let image: Data?
        let imageType: String?
    }
}

extension MaccyHistorySnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.lenientInt(.schemaVersion)
        version = c.lenientString(.version)
        publishedAt = c.lenientDate(.publishedAt)
        itemCount = c.lenientInt(.itemCount)
        lastCapturedAt = c.lenientDate(.lastCapturedAt)
        items = c.lenientArray(.items)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, version, publishedAt, itemCount, lastCapturedAt, items
    }
}

extension MaccyHistorySnapshot.MaccyHistoryItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        capturedAt = c.lenientDate(.capturedAt)
        app = c.lenientString(.app)
        title = c.lenientString(.title)
        string = c.lenientString(.string)
        fileURLs = c.lenientStringArray(.fileURLs)
        image = c.lenientData(.image)
        imageType = c.lenientString(.imageType)
    }

    private enum CodingKeys: String, CodingKey {
        case id, capturedAt, app, title, string, fileURLs, image, imageType
    }
}

/// Field-level tolerance helpers: a wrong-typed value degrades to nil instead
/// of poisoning the whole decode.
private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(number))
                : String(number)
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return number != 0 }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            guard number.isFinite, let exact = Int(exactly: number.rounded()) else { return nil }
            return exact
        }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        return nil
    }

    func lenientDate(_ key: Key) -> Date? {
        guard let raw = lenientString(key) else { return nil }
        return MaccyHistorySnapshot.parseDate(raw)
    }

    func lenientStringArray(_ key: Key) -> [String]? {
        if let values = try? decodeIfPresent([String].self, forKey: key) { return values }
        return nil
    }

    func lenientArray<T: Decodable>(_ key: Key) -> [T]? {
        try? decodeIfPresent([T].self, forKey: key)
    }

    func lenientData(_ key: Key) -> Data? {
        guard let raw = lenientString(key) else { return nil }
        return Data(base64Encoded: raw)
    }
}

// MARK: - Date parsing

extension MaccyHistorySnapshot {
    /// ISO 8601 (with or without fractional seconds) → epoch seconds/millis
    /// fallback → nil. Never throws on odd formats.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        for formatter in dateFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        if let epoch = Double(raw) {
            return abs(epoch) > 99_999_999_999
                ? Date(timeIntervalSince1970: epoch / 1000)
                : Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    private static let dateFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [fractional, plain]
    }()
}

// MARK: - Store

/// Observable store shared by the plugin's menu view(s). All filesystem reads
/// run on a utility queue and never block the calling (main) thread;
/// @Published state is mutated on the main thread only. Watcher state is
/// confined to the reader queue.
final class MaccyHistoryStore: ObservableObject {

    /// Files older than this render as the agent-not-running/stale state.
    /// The agent heartbeats the mtime every 120 s, so 300 s is ~2.5 missed
    /// beats before we call it dead.
    static let staleInterval: TimeInterval = 300

    // MARK: Published state (main thread only)

    @Published private(set) var snapshot: MaccyHistorySnapshot?
    @Published private(set) var fileFound = false
    /// Seconds since the history file's mtime, captured at last read.
    @Published private(set) var fileAge: TimeInterval?
    @Published private(set) var lastReadAt: Date?
    @Published private(set) var isMenuVisible = false
    /// Whether Gauge's process is trusted for Accessibility (⌘V auto-paste).
    @Published private(set) var axTrusted = AXIsProcessTrusted()

    // MARK: Derived state

    var items: [MaccyHistorySnapshot.MaccyHistoryItem] { snapshot?.items ?? [] }
    var itemCount: Int { snapshot?.itemCount ?? items.count }
    /// Time of the newest capture (for the status row).
    var lastCapturedAt: Date? { snapshot?.lastCapturedAt ?? items.first?.capturedAt }
    var isFileFresh: Bool { (fileAge ?? .infinity) < Self.staleInterval }
    /// Alive = file exists, decodes, and its mtime is fresh. The agent's 120 s
    /// heartbeat keeps a quiet but live agent fresh; a crashed agent goes
    /// stale and renders the not-running state.
    var isAlive: Bool { fileFound && isFileFresh && snapshot != nil }

    // MARK: Paths

    /// Env override MACCY_HISTORY_PATH, else the agent's default path.
    static func makePrimaryURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["MACCY_HISTORY_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/maccy-agent/history.json",
                isDirectory: false
            )
    }

    let primaryURL: URL

    // MARK: Reader queue / watcher state (confined to readerQueue)

    private let readerQueue = DispatchQueue(label: "com.ebowwa.gauge.plugin.maccy.reader", qos: .utility)
    private var watcherSource: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    /// Poll timer while the menu is open (main thread only). 3s ≤ the 5s cap.
    private var pollTimer: Timer?

    // MARK: Auto-paste arming (main thread only)

    /// Set when the user taps an item; ⌘V is posted from menuDidClose (the
    /// popover has closed by then, so the paste lands in the real frontmost
    /// app — never into the popover itself).
    @Published private(set) var pendingAutoPaste = false
    private var pendingPasteExpiry: Date?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        primaryURL = Self.makePrimaryURL(environment: environment)
        refresh()
    }

    // MARK: Reading

    struct ReadResult {
        let snapshot: MaccyHistorySnapshot?
        let found: Bool
        let fileAge: TimeInterval?
    }

    /// Async, non-blocking read of the history file.
    func refresh() {
        let primary = primaryURL
        readerQueue.async { [weak self] in
            guard let self else { return }
            let result = Self.read(primaryURL: primary)
            DispatchQueue.main.async { self.apply(result) }
            self.ensureWatcherLocked()
        }
    }

    /// Pure read+decode, safe from any thread (used by tests too).
    static func read(primaryURL: URL, now: Date = Date()) -> ReadResult {
        var url = primaryURL
        var attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if attrs == nil, let fallback = fallbackSnapshotURL() {
            url = fallback
            attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        }
        guard let attrs = attrs, let data = try? Data(contentsOf: url) else {
            return ReadResult(snapshot: nil, found: false, fileAge: nil)
        }
        let age = (attrs[.modificationDate] as? Date).map { now.timeIntervalSince($0) }
        // Undecodable data keeps found=true but snapshot=nil → the view's
        // isAlive gate renders the not-running state. Never a crash.
        let snapshot = try? JSONDecoder().decode(MaccyHistorySnapshot.self, from: data)
        return ReadResult(snapshot: snapshot, found: true, fileAge: age)
    }

    /// Variant-install fallback: newest history.json under any
    /// ~/Library/Application Support/maccy-agent*/.
    static func fallbackSnapshotURL() -> URL? {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: support,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var best: (url: URL, modified: Date)?
        for entry in entries where entry.lastPathComponent.hasPrefix("maccy-agent") {
            let candidate = entry.appendingPathComponent("history.json", isDirectory: false)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: candidate.path),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            if best == nil || modified > best!.modified { best = (candidate, modified) }
        }
        return best?.url
    }

    /// Publish on the main thread. Runs on main (dispatched from readerQueue).
    private func apply(_ result: ReadResult) {
        snapshot = result.snapshot
        fileFound = result.found
        fileAge = result.fileAge
        lastReadAt = Date()
        // Re-check the Accessibility grant on every read (cheap; the grant can
        // land while Gauge runs, e.g. after the user approves the prompt).
        axTrusted = AXIsProcessTrusted()
    }

    // MARK: Menu visibility (host hooks, called on the main thread)

    func setMenuVisible(_ visible: Bool) {
        isMenuVisible = visible
        if visible {
            refresh()
            startPolling()
        } else {
            stopPolling()
            firePendingPasteIfNeeded()
        }
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Auto-paste (⌘V)

    /// Arm a one-shot ⌘V to fire from menuDidClose — the popover has closed by
    /// then, so the paste lands in the real frontmost app.
    func armAutoPaste(now: Date = Date()) {
        guard axTrusted else {
            pendingAutoPaste = false
            return
        }
        pendingAutoPaste = true
        pendingPasteExpiry = now.addingTimeInterval(15)
    }

    private func firePendingPasteIfNeeded(now: Date = Date()) {
        guard pendingAutoPaste else { return }
        guard let expiry = pendingPasteExpiry, now < expiry else {
            pendingAutoPaste = false
            pendingPasteExpiry = nil
            return
        }
        pendingAutoPaste = false
        pendingPasteExpiry = nil
        MaccyPasteboard.postPasteKey()
    }

    // MARK: File watcher (reader-queue-confined)

    private func ensureWatcherLocked() {
        guard watcherSource == nil else { return }
        let fd = open(primaryURL.path, O_EVTONLY)
        guard fd >= 0 else { return } // not there yet; retried on next refresh
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: readerQueue
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            let event = source?.data ?? []
            if !event.intersection([.delete, .rename, .revoke]).isEmpty {
                self.teardownWatcherLocked()
            }
            self.scheduleDebouncedRefreshLocked()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcherSource = source
    }

    private func teardownWatcherLocked() {
        watcherSource?.cancel()
        watcherSource = nil
    }

    private func scheduleDebouncedRefreshLocked() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.debounceWork = nil
            self.refresh()
        }
        debounceWork = work
        readerQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

// MARK: - Pasteboard restore + ⌘V posting

enum MaccyPasteboard {

    /// Restore an item to the system clipboard, marking it so maccy-agent
    /// never re-captures it. fileURLs are written via writeObjects (multi-file
    /// Finder semantics); images as their captured type.
    static func restore(_ item: MaccyHistorySnapshot.MaccyHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let string = item.string, !string.isEmpty {
            pasteboard.setString(string, forType: .string)
        }

        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            let objects: [NSPasteboardItem] = fileURLs.compactMap { path in
                let pasteItem = NSPasteboardItem()
                pasteItem.setString(path, forType: .fileURL)
                return pasteItem
            }
            pasteboard.writeObjects(objects)
        }

        if let image = item.image, let imageType = item.imageType {
            let type = imageType == "tiff"
                ? NSPasteboard.PasteboardType.tiff
                : NSPasteboard.PasteboardType.png
            pasteboard.setData(image, forType: type)
        }

        // Marker: the agent skips captures carrying this type.
        pasteboard.setString("", forType: NSPasteboard.PasteboardType(maccyMarkerType))
    }

    /// Post ⌘V to the session event tap. Only effective when the posting
    /// process (Gauge) is trusted for Accessibility; the paste lands in the
    /// frontmost app — call only after the popover is closed.
    static func postPasteKey() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9 /* kVK_ANSI_V */, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
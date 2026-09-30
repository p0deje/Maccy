//
//  HistoryStore.swift
//  maccy-agent
//
//  Load / append / cap / persist the history file. All writes are atomic
//  (Data.write(.atomic) — temp file + rename), so a crash mid-write can never
//  leave a truncated history for the plugin to trip on. The heartbeat refreshes
//  the file's mtime without rewriting content: the plugin treats mtime
//  freshness as the agent-liveness authority (a live agent heartbeats, a
//  crashed one goes stale).
//

import Foundation

final class HistoryStore {

    let url: URL
    let maxItems: Int
    let maxImageBytes: Int

    /// Newest first. Confined to the main thread (watcher timer + writes).
    private(set) var items: [HistoryItem] = []

    init(url: URL, maxItems: Int = 200, maxImageBytes: Int = 2 * 1024 * 1024) {
        self.url = url
        self.maxItems = maxItems
        self.maxImageBytes = maxImageBytes
        load()
    }

    // MARK: Loading

    func load() {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(HistorySnapshot.self, from: data) else {
            items = []
            return
        }
        items = snapshot.items
    }

    // MARK: Capturing

    /// Insert a candidate at the head (newest first), cap, persist.
    /// Returns false when the candidate dedupes against the current head.
    /// Adjacent duplicates are collapsed on purpose: re-copying the same text
    /// (or restoring an item from the plugin) adds no information — true for
    /// the marker path and for the common "copy / paste / copy again" case.
    @discardableResult
    func append(_ candidate: HistoryItem, now: Date = Date()) -> Bool {
        if let last = items.first, last.title == candidate.title {
            return false
        }
        items.insert(candidate, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        persist(now: now)
        return true
    }

    /// Rewrite the whole file (small: ≤ maxItems records, images size-capped).
    func persist(now: Date = Date()) {
        let snapshot = HistorySnapshot(
            schemaVersion: 1,
            version: maccyAgentVersion,
            publishedAt: now,
            itemCount: items.count,
            lastCapturedAt: items.first?.capturedAt,
            items: items
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(
                Data("maccy-agent: cannot persist history: \(error)\n".utf8)
            )
        }
    }

    /// Refresh mtime without touching content — keeps the plugin's freshness
    /// check honest during quiet stretches. No-op if the file is absent.
    func heartbeat(now: Date = Date()) {
        try? FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: url.path
        )
    }
}
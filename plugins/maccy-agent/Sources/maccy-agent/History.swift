//
//  History.swift
//  maccy-agent
//
//  The capped clipboard history schema, persisted as history.json for the
//  Gauge Maccy plugin. Field semantics mirror Maccy's HistoryItem but without
//  SwiftData — one JSON file, atomic writes, tolerated by a lenient decoder
//  on the plugin side (any field may be missing/null/wrong-typed there).
//

import Foundation

/// Version of the lightweight Maccy companion (stamped into the snapshot).
let maccyAgentVersion = "0.1.0"

/// Default location of the history file. Overridable with --history-path
/// (agent) and MACCY_HISTORY_PATH (plugin), mirroring the squeakd
/// GAUGE_SQUEAKD_SNAPSHOT_PATH override pattern.
func defaultHistoryURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/maccy-agent/history.json",
            isDirectory: false
        )
}

/// Marker pasteboard type the Gauge plugin sets when it restores an item to
/// the clipboard. The agent skips captures that carry it, so copying an item
/// back out of history never re-captures it (Maccy's org.p0deje.Maccy marker,
/// namespaced to this project). Kept in sync with the plugin by convention —
/// see plugins/gauge-plugin/Sources/MaccyHistory.swift.
let maccyMarkerType = "com.ebowwa.maccy.agent.copied"

/// One clipboard capture. `string` (plain text, always present for text
/// copies), `fileURLs` (one or more copied files/folders), or `image`
/// (base64 PNG/TIFF, size-capped by the agent) — or combinations.
struct HistoryItem: Codable {
    var id: String
    var capturedAt: Date
    /// Bundle id of the frontmost app at copy time (best effort; nil from a
    /// non-GUI context).
    var app: String?
    /// Sanitized, first-line, length-capped preview. Also the dedupe identity.
    var title: String
    var string: String?
    var fileURLs: [String]?
    var image: Data?
    var imageType: String?
}

/// The whole history file: metadata the plugin renders (itemCount,
/// lastCapturedAt, publishedAt) plus the capped item array (newest first).
struct HistorySnapshot: Codable {
    var schemaVersion: Int
    var version: String
    var publishedAt: Date
    var itemCount: Int
    var lastCapturedAt: Date?
    var items: [HistoryItem]
}

/// Strip scalars that hang CoreText line truncation (mirrors Maccy
/// String+UnsafeForTitleLayout — U+FFFC from rich text with inline
/// attachments). The plugin renders titles with .lineLimit(1), so both
/// sides must sanitize: the agent at capture, the plugin at render.
extension String {
    private static let scalarsUnsafeForTitleLayout: Set<Unicode.Scalar> = [
        "\u{FFFC}"
    ]

    var containsScalarsUnsafeForTitleLayout: Bool {
        unicodeScalars.contains { Self.scalarsUnsafeForTitleLayout.contains($0) }
    }

    func removingScalarsUnsafeForTitleLayout() -> String {
        guard containsScalarsUnsafeForTitleLayout else { return self }
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars where !Self.scalarsUnsafeForTitleLayout.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }
}
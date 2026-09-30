//
//  ClipboardWatcher.swift
//  maccy-agent
//
//  The pasteboard watcher — Maccy's Clipboard engine stripped to the
//  essentials. Polls NSPasteboard.general.changeCount on a timer (same
//  approach as Maccy's checkForChangesInPasteboard), merges multi-item copies
//  into one record, captures .string / .fileURL / .png / .tiff, skips empty
//  and dynamic (dyn.*) types, skips the plugin's own restores (marker type),
//  and falls back to the plain-text flavor of RTF/HTML-only copies.
//

import AppKit

final class ClipboardWatcher {

    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private let store: HistoryStore
    var verbose = false

    private func trace(_ message: String) {
        guard verbose else { return }
        FileHandle.standardError.write(Data("[maccy-agent] \(message)\n".utf8))
    }

    init(store: HistoryStore) {
        self.store = store
        self.changeCount = pasteboard.changeCount
    }

    /// One changeCount check. Returns the captured item when a new copy
    /// landed and was NOT deduped; nil otherwise. Call from the main thread.
    @discardableResult
    func checkForChanges() -> HistoryItem? {
        let cc = pasteboard.changeCount
        guard cc != changeCount else { return nil }
        changeCount = cc

        trace("changeCount \(cc): reading pasteboard")
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            trace("no pasteboard items — skipped")
            return nil
        }
        trace("items=\(items.count) types=\(items.first?.types.map(\.rawValue) ?? [])")

        // Skip the plugin's own restores (and anything else that carries the
        // marker): restoring an item is not a new copy.
        if items.contains(where: { $0.types.contains(NSPasteboard.PasteboardType(maccyMarkerType)) }) {
            trace("marker type present — skipped (plugin restore)")
            return nil
        }

        var stringValue: String?
        var fileURLs: [String] = []
        var imageData: Data?
        var imageType: String?

        for item in items {
            let types = item.types.filter { !$0.rawValue.hasPrefix("dyn.") }

            if let value = item.string(forType: .string),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stringValue = value
            }

            if types.contains(.fileURL), let path = item.string(forType: .fileURL) {
                fileURLs.append(path)
            }

            if imageData == nil {
                if types.contains(.png), let data = item.data(forType: .png), data.count <= store.maxImageBytes {
                    imageData = data
                    imageType = "png"
                } else if types.contains(.tiff), let data = item.data(forType: .tiff), data.count <= store.maxImageBytes {
                    imageData = data
                    imageType = "tiff"
                }
            }
        }

        // Rich text without a .string flavor: fall back to the plain text of
        // the RTF/HTML representation so rich copies still land as text.
        if stringValue == nil {
            if let rtf = pasteboard.data(forType: .rtf),
               let attr = NSAttributedString(rtf: rtf, documentAttributes: nil),
               !attr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stringValue = attr.string
            } else if let html = pasteboard.data(forType: .html),
                      let attr = NSAttributedString(html: html, documentAttributes: nil),
                      !attr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stringValue = attr.string
            }
        }

        guard stringValue != nil || !fileURLs.isEmpty || imageData != nil else {
            trace("no capturable content (string=\(stringValue != nil) files=\(fileURLs.count) image=\(imageData != nil)) — skipped")
            return nil
        }

        let title: String
        if let stringValue {
            title = firstLine(stringValue)
        } else if !fileURLs.isEmpty {
            title = fileURLs.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        } else {
            // Images get a size-stamped title: unique enough for dedupe,
            // stable for identical re-copies, and renderable as text.
            let size = ByteCountFormatter.string(fromByteCount: Int64(imageData?.count ?? 0), countStyle: .file)
            title = "🖼 Image · \(size)"
        }

        let cleaned = title.removingScalarsUnsafeForTitleLayout()
        let truncated = String(cleaned.prefix(300))

        let item = HistoryItem(
            id: UUID().uuidString,
            capturedAt: Date(),
            app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            title: truncated,
            string: stringValue,
            fileURLs: fileURLs.isEmpty ? nil : fileURLs,
            image: imageData,
            imageType: imageType
        )

        guard store.append(item) else { return nil }
        return item
    }

    private func firstLine(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n").first ?? text
    }
}
import AppKit
import Defaults
import Sauce
import SwiftData
import Vision

@Model
class HistoryItem {
    static var supportedPins: Set<String> {
        // "a" reserved for select all
        // "q" reserved for quit
        // "v" reserved for paste
        // "w" reserved for close window
        // "z" reserved for undo/redo
        var keys = Set([
            "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
            "m", "n", "o", "p", "r", "s", "t", "u", "x", "y"
        ])

        if let deleteKey = KeyChord.deleteKey,
           let character = Sauce.shared.character(for: Int(deleteKey.QWERTYKeyCode), cocoaModifiers: []) {
            keys.remove(character)
        }

        if let pinKey = KeyChord.pinKey,
           let character = Sauce.shared.character(for: Int(pinKey.QWERTYKeyCode), cocoaModifiers: []) {
            keys.remove(character)
        }

        return keys
    }

    @MainActor
    static var availablePins: [String] {
        let descriptor = FetchDescriptor<HistoryItem>(
            predicate: #Predicate { $0.pin != nil }
        )
        let pins = try? Storage.shared.context.fetch(descriptor).compactMap({ $0.pin })
        let assignedPins = Set(pins ?? [])
        return Array(supportedPins.subtracting(assignedPins))
    }

    @MainActor
    static var randomAvailablePin: String { availablePins.randomElement() ?? "" }

    private static let transientTypes: [String] = [
        NSPasteboard.PasteboardType.modified.rawValue,
        NSPasteboard.PasteboardType.fromMaccy.rawValue,
        NSPasteboard.PasteboardType.linkPresentationMetadata.rawValue,
        NSPasteboard.PasteboardType.customPasteboardData.rawValue,
        NSPasteboard.PasteboardType.source.rawValue
    ]

    var application: String?
    var firstCopiedAt: Date = Date.now
    var lastCopiedAt: Date = Date.now
    var numberOfCopies: Int = 1
    var pin: String?
    var title = ""

    @Relationship(deleteRule: .cascade)
    var contents: [HistoryItemContent] = []

    init(contents: [HistoryItemContent] = []) {
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.contents = contents
    }

    func supersedes(_ item: HistoryItem) -> Bool {
        return item.contents
            .filter { content in
                !Self.transientTypes.contains(content.type)
            }
            .allSatisfy { content in
                contents.contains(where: { $0.type == content.type && $0.value == content.value })
            }
    }

    func generateTitle() -> String {
        guard image == nil else {
            // For images, provide a descriptive title
            if !fileURLs.isEmpty {
                // If we have file URLs for the image, show the filename
                return fileURLs.compactMap { $0.lastPathComponent }.joined(separator: ", ")
            } else {
                // For clipboard images without file URLs, show a generic title
                Task {
                    self.performTextRecognition()
                }
                return "📷 Image"
            }
        }

        // Check if we have file URLs (including non-image files)
        if !fileURLs.isEmpty {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
            let hasImageFiles = fileURLs.contains { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }

            if hasImageFiles {
                // For image files, show filename instead of full path
                return fileURLs
                    .filter { url in imageExtensions.contains(url.pathExtension.lowercased()) }
                    .compactMap { $0.lastPathComponent }
                    .joined(separator: ", ")
            } else {
                // For non-image files, show filename with appropriate icon
                return fileURLs.compactMap { $0.lastPathComponent }.joined(separator: ", ")
            }
        }

        // 1k characters is trade-off for performance
        var title = previewableText.shortened(to: 1_000)

        if Defaults[.showSpecialSymbols] {
            if let range = title.range(of: "^ +", options: .regularExpression) {
                title = title.replacingOccurrences(of: " ", with: "·", range: range)
            }
            if let range = title.range(of: " +$", options: .regularExpression) {
                title = title.replacingOccurrences(of: " ", with: "·", range: range)
            }
            title = title
                .replacingOccurrences(of: "\n", with: "⏎")
                .replacingOccurrences(of: "\t", with: "⇥")
        } else {
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return title
    }

    var previewableText: String {
        // Prioritize image content when image data is available
        if image != nil {
            return ""
        } else if !fileURLs.isEmpty {
            // Check if file URLs are image files
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
            let hasImageFiles = fileURLs.contains { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }

            // If we have image files, return empty string to show the image instead of file path
            if hasImageFiles {
                return ""
            } else {
                // For non-image files, return the filename to show alongside the file icon
                return fileURLs.compactMap { $0.lastPathComponent }.joined(separator: ", ")
            }
        } else if let text = text, !text.isEmpty {
            return text
        } else if let rtf = rtf, !rtf.string.isEmpty {
            return rtf.string
        } else if let html = html, !html.string.isEmpty {
            return html.string
        } else {
            return title
        }
    }

    var fileURLs: [URL] {
        guard !universalClipboardText else {
            return []
        }

        return allContentData([.fileURL])
            .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
    }

    var htmlData: Data? { contentData([.html]) }
    var html: NSAttributedString? {
        guard let data = htmlData else {
            return nil
        }

        return NSAttributedString(html: data, documentAttributes: nil)
    }

    var imageData: Data? {
        var data: Data?
        data = contentData([.tiff, .png, .jpeg, .heic])

        // If no direct image data, check if we have image file URLs
        if data == nil {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
            if let imageURL = fileURLs.first(where: { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }) {
                data = try? Data(contentsOf: imageURL)
            } else if universalClipboardImage, let url = fileURLs.first {
                data = try? Data(contentsOf: url)
            }
        }

        return data
    }

    var image: NSImage? {
        guard let data = imageData else {
            return nil
        }

        return NSImage(data: data)
    }

    var fileIcon: NSImage? {
        // Only show file icons for non-image files
        guard !fileURLs.isEmpty else {
            return nil
        }

        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
        let nonImageFiles = fileURLs.filter { url in
            !imageExtensions.contains(url.pathExtension.lowercased())
        }

        // Return icon for the first non-image file
        guard let firstFile = nonImageFiles.first else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: firstFile.path)
        return icon
    }

    var rtfData: Data? { contentData([.rtf]) }
    var rtf: NSAttributedString? {
        guard let data = rtfData else {
            return nil
        }

        return NSAttributedString(rtf: data, documentAttributes: nil)
    }

    var text: String? {
        guard let data = contentData([.string]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    var modified: Int? {
        guard let data = contentData([.modified]),
              let modified = String(data: data, encoding: .utf8) else {
            return nil
        }

        return Int(modified)
    }

    var fromMaccy: Bool { contentData([.fromMaccy]) != nil }
    var universalClipboard: Bool { contentData([.universalClipboard]) != nil }

    private var universalClipboardImage: Bool { universalClipboard && fileURLs.first?.pathExtension == "jpeg" }
    private var universalClipboardText: Bool {
        universalClipboard && contentData([.html, .tiff, .png, .jpeg, .rtf, .string, .heic]) != nil
    }

    private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
        let content = contents.first(where: { content in
            return types.contains(NSPasteboard.PasteboardType(content.type))
        })

        return content?.value
    }

    private func allContentData(_ types: [NSPasteboard.PasteboardType]) -> [Data] {
        return contents
            .filter { types.contains(NSPasteboard.PasteboardType($0.type)) }
            .compactMap { $0.value }
    }

    private func performTextRecognition() {
        guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        request.recognitionLevel = .fast

        do {
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the request: \(error).")
        }
    }

    private func recognizeTextHandler(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return
        }

        let recognizedStrings = observations.compactMap { observation in
            return observation.topCandidates(1).first?.string
        }

        self.title = recognizedStrings.joined(separator: "\n")
    }
}

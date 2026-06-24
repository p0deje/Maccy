import AppKit
import Defaults
import Logging
import Sauce
import SwiftData

@Model
class HistoryItem {
  static let titlePreviewLimit = 1_000
  /// Capped at 3,000 chars (was 10,000, 2026-06-22). The preview pane renders
  /// this with CoreText, and 10k-char previews were a measurable layout cost
  /// when opening a long-text item's preview. 3k covers real-world clips while
  /// bounding the measurement work. (User-directed.)
  static let textPreviewLimit = 3_000

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
    if let previewKey = KeyChord.previewKey,
       let character = Sauce.shared.character(for: Int(previewKey.QWERTYKeyCode), cocoaModifiers: []) {
      keys.remove(character)
    }

    return keys
  }

  @MainActor
  static var availablePins: [String] {
    let descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin != nil }
    )
    let pins: [String]
    do {
      pins = try Storage.shared.context.fetch(descriptor).compactMap({ $0.pin })
    } catch {
      Logger(label: "org.p0deje.Maccy").error("Failed to fetch assigned pins: \(String(describing: error))")
      pins = []
    }
    let assignedPins = Set(pins)
    return Array(supportedPins.subtracting(assignedPins))
  }

  @MainActor
  static var randomAvailablePin: String? { availablePins.randomElement() }

  private static let transientTypes: Set<String> = [
    NSPasteboard.PasteboardType.modified.rawValue,
    NSPasteboard.PasteboardType.fromMaccy.rawValue,
    NSPasteboard.PasteboardType.linkPresentationMetadata.rawValue,
    NSPasteboard.PasteboardType.customWebKitPasteboardData.rawValue,
    NSPasteboard.PasteboardType.source.rawValue,
    NSPasteboard.PasteboardType.customChromiumWebData.rawValue,
    NSPasteboard.PasteboardType.chromiumSourceUrl.rawValue,
    NSPasteboard.PasteboardType.chromiumSourceToken.rawValue,
    NSPasteboard.PasteboardType.notesRichText.rawValue
  ]
  private static let richTextParsingLimit = 512 * 1_024

  var application: String?
  var firstCopiedAt: Date = Date.now
  var lastCopiedAt: Date = Date.now
  var numberOfCopies: Int = 1
  var pin: String?
  var title = ""

  @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
  var contents: [HistoryItemContent] = []

  init(contents: [HistoryItemContent] = []) {
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.contents = contents
  }

  func supersedes(_ item: HistoryItem) -> Bool {
    supersedes(item.duplicateSignature)
  }

  var duplicateSignature: HistoryItemEngine.Signature {
    HistoryItemEngine.signature(
      contents: contents,
      ignoringTypes: Self.transientTypes
    )
  }

  func supersedes(_ signature: HistoryItemEngine.Signature) -> Bool {
    HistoryItemEngine.contains(contents: contents, signature: signature)
  }

  func generateTitle() -> String {
    // Image items have no text title — they are presented as thumbnails. (The
    // Vision OCR title feature was removed; image titles stay empty.)
    if imageData != nil {
      return ""
    }

    return HistoryItemEngine.generateTitle(
      contents: contents,
      fallbackTitle: title,
      maxLength: Self.titlePreviewLimit,
      richTextParsingLimit: Self.richTextParsingLimit,
      showSpecialSymbols: Defaults[.showSpecialSymbols]
    )
  }

  func previewableTextPrefix(maxLength: Int) -> String {
    HistoryItemEngine.previewableTextPrefix(
      contents: contents,
      fallbackTitle: title,
      maxLength: maxLength,
      richTextParsingLimit: Self.richTextParsingLimit
    )
  }

  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return allContentData([.fileURL])
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }

  var htmlData: Data? { contentData([.html]) }
  var imageData: Data? {
    var data: Data?
    data = contentData([.tiff, .png, .jpeg, .heic])
    if data == nil, universalClipboardImage, let url = fileURLs.first {
      data = dataFromFileIfAllowed(url)
    }

    return data
  }

  var hasImageData: Bool { imageData != nil }

  var image: NSImage? {
    guard let data = imageData else {
      return nil
    }

    return NSImage(data: data)
  }

  var rtfData: Data? { contentData([.rtf]) }
  var text: String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  func textPrefix(maxLength: Int) -> String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return data.stringPrefix(maxBytes: maxLength)
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
    for type in types {
      if let content = contents.first(where: { NSPasteboard.PasteboardType($0.type) == type }) {
        return content.value
      }
    }

    return nil
  }

  private func allContentData(_ types: [NSPasteboard.PasteboardType]) -> [Data] {
    return contents
      .filter { types.contains(NSPasteboard.PasteboardType($0.type)) }
      .compactMap { $0.value }
  }

  private func dataFromFileIfAllowed(_ url: URL) -> Data? {
    Self.dataFromFileIfAllowed(url)
  }
}

extension HistoryItem {
  static func dataFromFileIfAllowed(
    _ url: URL,
    resourceValues: (URL) throws -> URLResourceValues = {
      try $0.resourceValues(forKeys: [.fileSizeKey])
    },
    dataContents: (URL) throws -> Data = { try Data(contentsOf: $0) },
    logErrors: Bool = true
  ) -> Data? {
    let fileSize: Int
    do {
      guard let value = try resourceValues(url).fileSize else {
        return nil
      }
      fileSize = value
    } catch {
      Logger(label: "org.p0deje.Maccy")
        .logErrorIfNeeded(logErrors, "Failed to read file size for \(url.path): \(String(describing: error))")
      return nil
    }

    guard fileSize <= HistoryItemContent.maxValueSize else {
      return nil
    }

    do {
      return try dataContents(url)
    } catch {
      Logger(label: "org.p0deje.Maccy")
        .logErrorIfNeeded(logErrors, "Failed to read file data for \(url.path): \(String(describing: error))")
      return nil
    }
  }
}

private extension Logger {
  func logErrorIfNeeded(_ enabled: Bool, _ message: Logger.Message) {
    if enabled {
      error(message)
    }
  }
}

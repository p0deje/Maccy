import AppKit
import Defaults
import Logging
import Sauce
import SwiftData

/// A single clipboard history entry. Owns its content entries (one per
/// pasteboard type), metadata (source app, copy timestamps, pin), and the
/// derived preview title.
@Model
class HistoryItem {
  /// Max chars used when generating an item's title.
  static let titlePreviewLimit = TextLimits.titlePreview

  /// Max chars of a text item shown in the preview (Defaults[.textPreviewLimit]).
  /// Configurable in Appearance settings; 0 = full text (no truncation, mapped
  /// to a large sentinel). Large values can make a long-text preview measurably
  /// slower to lay out (CoreText), so the default (3000) bounds the work for
  /// real-world clips.
  static var textPreviewLimit: Int {
    let limit = Defaults[.textPreviewLimit]
    return limit > 0 ? limit : 10_000_000
  }

  /// Pin keys not reserved for other shortcuts and not currently assigned.
  static var supportedPins: Set<String> {
    // Keys reserved for built-in shortcuts: "a" (select all), "q" (quit),
    // "v" (paste), "w" (close window), "z" (undo/redo).
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

  /// Pin keys that are supported and not yet assigned to any item.
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

  /// A random unassigned pin key, or nil if every supported key is taken.
  @MainActor
  static var randomAvailablePin: String? { availablePins.randomElement() }

  /// Pasteboard types that are transient (set by the source app for its own
  /// bookkeeping) and must be ignored when comparing items for dedup.
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

  // MARK: - Dedup

  /// Returns true if this item's non-transient contents fully cover `item`'s.
  func supersedes(_ item: HistoryItem) -> Bool {
    supersedes(item.duplicateSignature)
  }

  /// A Sendable containment signature for this item, ignoring transient types.
  var duplicateSignature: HistoryItemEngine.Signature {
    HistoryItemEngine.signature(
      contents: contents,
      ignoringTypes: Self.transientTypes
    )
  }

  /// Returns true if this item's contents contain every entry in `signature`.
  func supersedes(_ signature: HistoryItemEngine.Signature) -> Bool {
    HistoryItemEngine.contains(contents: contents, signature: signature)
  }

  // MARK: - Title & preview

  /// Generates the single-line preview title for this item.
  ///
  /// Image items have no text title (they are presented as thumbnails), so an
  /// item with image data returns an empty string.
  func generateTitle() -> String {
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

  /// Returns the previewable text prefix of this item, capped at `maxLength`.
  func previewableTextPrefix(maxLength: Int) -> String {
    HistoryItemEngine.previewableTextPrefix(
      contents: contents,
      fallbackTitle: title,
      maxLength: maxLength,
      richTextParsingLimit: Self.richTextParsingLimit
    )
  }

  // MARK: - Content accessors

  /// File URLs carried by this item, unless it is a Handoff (universal
  /// clipboard) payload that also carries other types.
  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return allContentData([.fileURL])
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }

  /// The HTML payload, if any.
  var htmlData: Data? { contentData([.html]) }

  /// The image payload, resolving Handoff image URLs to their file bytes when
  /// the inline image types are absent.
  var imageData: Data? {
    var data: Data?
    data = contentData([.tiff, .png, .jpeg, .heic])
    if data == nil, universalClipboardImage, let url = fileURLs.first {
      data = dataFromFileIfAllowed(url)
    }

    return data
  }

  /// True if this item carries an image payload.
  var hasImageData: Bool { imageData != nil }

  /// Decodes the image payload into an `NSImage`, or nil if there is none.
  var image: NSImage? {
    guard let data = imageData else {
      return nil
    }

    return NSImage(data: data)
  }

  /// The RTF payload, if any.
  var rtfData: Data? { contentData([.rtf]) }

  /// The plain-text payload decoded as UTF-8, if any.
  var text: String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  /// Returns the UTF-8-safe prefix of the string payload, up to `maxLength`
  /// bytes, or nil if there is no string payload.
  func textPrefix(maxLength: Int) -> String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return data.stringPrefix(maxBytes: maxLength)
  }

  /// The numeric modification flag carried by the item, if any.
  var modified: Int? {
    guard let data = contentData([.modified]),
          let modified = String(data: data, encoding: .utf8) else {
      return nil
    }

    return Int(modified)
  }

  /// True if this item was placed on the pasteboard by Maccy itself.
  var fromMaccy: Bool { contentData([.fromMaccy]) != nil }

  /// True if this item arrived via Handoff (universal clipboard).
  var universalClipboard: Bool { contentData([.universalClipboard]) != nil }

  /// True when a Handoff image payload is present (a `.universalClipboard`
  /// entry whose file URL points at a JPEG).
  private var universalClipboardImage: Bool { universalClipboard && fileURLs.first?.pathExtension == "jpeg" }

  /// True when a Handoff text payload is present, detected by a
  /// `.universalClipboard` entry alongside any of the concrete text/image types.
  private var universalClipboardText: Bool {
    universalClipboard && contentData([.html, .tiff, .png, .jpeg, .rtf, .string, .heic]) != nil
  }

  /// Returns the first non-nil payload among `types`, in order.
  private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
    for type in types {
      if let content = contents.first(where: { NSPasteboard.PasteboardType($0.type) == type }) {
        return content.value
      }
    }

    return nil
  }

  /// Returns every payload carried for any of `types`.
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
  /// Reads the bytes of a file URL into `Data`, subject to the content size
  /// limit, so a Handoff image URL can be resolved without overflowing memory.
  ///
  /// The `resourceValues` / `dataContents` closures are injection points for
  /// tests; `logErrors` silences logging in contexts where a missing file is
  /// expected.
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

/// Logs `message` at `.error` only when `enabled` is true.
private extension Logger {
  func logErrorIfNeeded(_ enabled: Bool, _ message: Logger.Message) {
    if enabled {
      error(message)
    }
  }
}

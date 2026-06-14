import AppKit
import Defaults
import Sauce
import SwiftData
import Vision

@Model
class HistoryItem {
  static let titlePreviewLimit = 1_000
  static let textPreviewLimit = 10_000

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
    let pins = try? Storage.shared.context.fetch(descriptor).compactMap({ $0.pin })
    let assignedPins = Set(pins ?? [])
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
    HistoryItemEngine.supersedes(
      contents: contents,
      otherContents: item.contents,
      ignoringTypes: Self.transientTypes
    )
  }

  func generateTitle() -> String {
    if let imageData {
      if CommandLine.arguments.contains("enable-testing") {
        return ""
      }

      Task { @MainActor [weak self, imageData] in
        guard let image = NSImage(data: imageData) else {
          return
        }
        guard let recognizedText = Self.recognizedText(in: image) else {
          return
        }

        self?.title = recognizedText
      }
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

  var previewableText: String {
    if !fileURLs.isEmpty {
      fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let text = text, !text.isEmpty {
      text
    } else if let rtf = rtf, !rtf.string.isEmpty {
      rtf.string
    } else if let html = html, !html.string.isEmpty {
      html.string
    } else {
      title
    }
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
  var html: NSAttributedString? {
    guard let data = htmlData else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }
  private var htmlIfSmall: NSAttributedString? {
    guard let data = htmlData, data.count <= Self.richTextParsingLimit else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

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
  var rtf: NSAttributedString? {
    guard let data = rtfData else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }
  private var rtfIfSmall: NSAttributedString? {
    guard let data = rtfData, data.count <= Self.richTextParsingLimit else {
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
    let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard (fileSize ?? 0) <= HistoryItemContent.maxValueSize else {
      return nil
    }

    return try? Data(contentsOf: url)
  }

  private static func recognizedText(in image: NSImage) -> String? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    let requestHandler = VNImageRequestHandler(cgImage: cgImage)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast

    do {
      try requestHandler.perform([request])
    } catch {
      return nil
    }

    guard let observations = request.results else {
      return nil
    }

    let recognizedStrings = observations.compactMap {
      $0.topCandidates(1).first?.string
    }
    return recognizedStrings.joined(separator: "\n")
  }
}

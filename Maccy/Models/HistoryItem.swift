import AppKit
import CryptoKit
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
  static var randomAvailablePin: String { availablePins.randomElement() ?? "" }

  private static let transientTypes: [String] = [
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

  var application: String?
  var firstCopiedAt: Date = Date.now
  var lastCopiedAt: Date = Date.now
  var numberOfCopies: Int = 1
  var pin: String?
  var title = ""
  var contentFingerprint: String?

  // Pre-rendered thumbnail bytes for image items. Small JPEG (~5-10 KB) used by
  // the list UI so browsing never has to fault in the full `contents`
  // relationship. Nil for text/file items and for image items that pre-date
  // this migration (backfilled lazily — see `History.backfillThumbnails`).
  var thumbnailData: Data?

  @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
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

  func ensureContentFingerprint() {
    guard contentFingerprint == nil else { return }
    contentFingerprint = Self.makeContentFingerprint(from: contents)
  }

  static func makeContentFingerprint(from contents: [HistoryItemContent]) -> String? {
    let stableContents = contents
      .filter { !transientTypes.contains($0.type) }
      .sorted { lhs, rhs in
        if lhs.type == rhs.type {
          return (lhs.value ?? Data()).lexicographicallyPrecedes(rhs.value ?? Data())
        }
        return lhs.type < rhs.type
      }

    guard !stableContents.isEmpty else { return nil }

    var bytes = Data()
    for content in stableContents {
      bytes.append(Data(content.type.utf8))
      bytes.append(0)
      if let value = content.value {
        bytes.append(Data(String(value.count).utf8))
        bytes.append(0)
        bytes.append(value)
      } else {
        bytes.append(Data("-1".utf8))
        bytes.append(0)
      }
      bytes.append(0xff)
    }

    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  // 2x retina capacity for a 340x40 row tile, JPEG-encoded. Keeps each
  // thumbnail under ~10 KB so the entire history's worth fits in a few MB.
  static let thumbnailMaxPixelSize = NSSize(width: 680, height: 80)
  static let thumbnailJPEGQuality: CGFloat = 0.7

  // Synchronous; use only off the main thread or for fresh captures where the
  // image is already decoded. Returns nil if `data` doesn't decode or is
  // smaller than the target (no point in re-encoding).
  static func makeThumbnailData(from data: Data) -> Data? {
    guard let source = NSImage(data: data) else { return nil }
    let sourceSize = source.size
    guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

    let target = HistoryItem.thumbnailMaxPixelSize
    let ratio = min(target.width / sourceSize.width, target.height / sourceSize.height)
    let pixelSize: NSSize
    if ratio >= 1 {
      pixelSize = sourceSize
    } else {
      pixelSize = NSSize(
        width: max(1, (sourceSize.width * ratio).rounded()),
        height: max(1, (sourceSize.height * ratio).rounded())
      )
    }

    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(pixelSize.width),
      pixelsHigh: Int(pixelSize.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bitmapFormat: [],
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }
    rep.size = pixelSize

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    source.draw(in: NSRect(origin: .zero, size: pixelSize),
                from: .zero, operation: .copy, fraction: 1)

    return rep.representation(
      using: .jpeg,
      properties: [.compressionFactor: HistoryItem.thumbnailJPEGQuality]
    )
  }

  func ensureThumbnailData() {
    guard thumbnailData == nil else { return }
    guard let data = imageData else { return }
    thumbnailData = HistoryItem.makeThumbnailData(from: data)
  }

  func generateTitle() -> String {
    guard image == nil else {
      Task {
        self.performTextRecognition()
      }
      return ""
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

  func previewableText(upTo maxLength: Int) -> String {
    if !fileURLs.isEmpty {
      return fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
        .shortened(to: maxLength)
    } else if let text = text(upTo: maxLength), !text.isEmpty {
      return text
    } else if let rtf = rtf, !rtf.string.isEmpty {
      return rtf.string.shortened(to: maxLength)
    } else if let html = html, !html.string.isEmpty {
      return html.string.shortened(to: maxLength)
    } else {
      return title.shortened(to: maxLength)
    }
  }

  func hasPreviewableText(after maxLength: Int) -> Bool {
    if let textData = contentData([.string]) {
      return textData.count > maxLength
    }
    return previewableText.count > maxLength
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
    if data == nil, universalClipboardImage, let url = fileURLs.first {
      data = try? Data(contentsOf: url)
    }

    return data
  }

  var hasImageDataType: Bool {
    containsContentType([.tiff, .png, .jpeg, .heic])
  }

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

  var text: String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  var textByteSize: Int {
    return contentData([.string])?.count ?? 0
  }

  func text(upTo maxLength: Int) -> String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    let byteLimit = min(data.count, maxLength * 4)
    return String(data: data.prefix(byteLimit), encoding: .utf8)?
      .shortened(to: maxLength)
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

  private func containsContentType(_ types: [NSPasteboard.PasteboardType]) -> Bool {
    return contents.contains { content in
      types.contains(NSPasteboard.PasteboardType(content.type))
    }
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

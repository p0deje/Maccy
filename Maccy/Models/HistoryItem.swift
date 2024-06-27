import AppKit
import Defaults
import SwiftData

@Model
class HistoryItem {
  static var availablePins: Set<String> {
    var keys = Set([
      "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
      "n", "o", "p", "r", "s", "t", "u", "v", "w", "x", "y", "z" // "q" reserved for quit
    ])

    if let deleteKey = KeyChord.deleteKey {
      keys.remove(String(deleteKey.character))
    }
    if let pinKey = KeyChord.pinKey {
      keys.remove(String(pinKey.character))
    }

    return keys
  }

  @MainActor
  static var randomAvailablePin: String {
    let descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin != nil }
    )
    let pins = try! SwiftDataManager.shared.container.mainContext.fetch(descriptor).compactMap({ $0.pin })
    let assignedPins = Set(pins)
    return availablePins.subtracting(assignedPins).randomElement() ?? ""
  }

  var application: String?
  var firstCopiedAt: Date
  var lastCopiedAt: Date
  var numberOfCopies: Int = 1
  @Attribute(.unique) 
  var pin: String?
  var title = ""
  
  @Relationship(deleteRule: .cascade)
  var contents: [HistoryItemContent] = []

  init(firstCopiedAt: Date = Date.now, lastCopiedAt: Date = Date.now, contents: [HistoryItemContent] = []) {
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.contents = contents
  }

  func supersedes(_ item: HistoryItem) -> Bool {
    return item.contents
      .filter { content in
        ![
          NSPasteboard.PasteboardType.modified.rawValue,
          NSPasteboard.PasteboardType.fromMaccy.rawValue
        ].contains(content.type)
      }
      .allSatisfy { content in
        contents.contains(where: { $0.type == content.type && $0.value == content.value })
      }
  }

  func generateTitle() -> String {
    var title = ""

    guard image == nil else {
      return title
    }

    if !fileURLs.isEmpty {
      title = fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let text = text {
      title = text
    } else if title.isEmpty, let rtf = rtf {
      title = rtf.string
    } else if title.isEmpty, let html = html {
      title = html.string
    }

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
  
  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return allContentData(filePasteboardTypes)
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }

  var htmlData: Data? { contentData(htmlPasteboardTypes) }
  var html: NSAttributedString? {
    guard let data = htmlData else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  var image: NSImage? {
    var data: Data?
    data = contentData(imagePasteboardTypes)
    if data == nil, universalClipboardImage, let url = fileURLs.first {
      data = try? Data(contentsOf: url)
    }

    guard let data = data else {
      return nil
    }

    return NSImage(data: data)
  }

  var rtfData: Data? { contentData(rtfPasteboardTypes) }
  var rtf: NSAttributedString? {
    guard let data = rtfData else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }

  var text: String? {
    guard let data = contentData(textPasteboardTypes) else {
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

  @Transient private let filePasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL]
  @Transient private let htmlPasteboardTypes: [NSPasteboard.PasteboardType] = [.html]
  @Transient private let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, .jpeg]
  @Transient private let rtfPasteboardTypes: [NSPasteboard.PasteboardType] = [.rtf]
  @Transient private let textPasteboardTypes: [NSPasteboard.PasteboardType] = [.string]

  private var universalClipboardImage: Bool { universalClipboard && fileURLs.first?.pathExtension == "jpeg" }
  private var universalClipboardText: Bool {
     universalClipboard &&
      contentData(htmlPasteboardTypes + imagePasteboardTypes + rtfPasteboardTypes + textPasteboardTypes) != nil
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
}

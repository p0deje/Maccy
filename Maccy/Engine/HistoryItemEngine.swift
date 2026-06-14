import AppKit

enum HistoryItemEngine {
  static func supersedes(
    contents: [HistoryItemContent],
    otherContents: [HistoryItemContent],
    ignoringTypes transientTypes: Set<String>
  ) -> Bool {
    let index = ContentIndex(contents)

    return otherContents
      .filter { content in
        !transientTypes.contains(content.type)
      }
      .allSatisfy { content in
        index.contains(type: content.type, value: content.value)
      }
  }

  static func generateTitle(
    contents: [HistoryItemContent],
    fallbackTitle: String,
    maxLength: Int,
    richTextParsingLimit: Int,
    showSpecialSymbols: Bool
  ) -> String {
    var title = previewableTextPrefix(
      contents: contents,
      fallbackTitle: fallbackTitle,
      maxLength: maxLength,
      richTextParsingLimit: richTextParsingLimit
    )

    if showSpecialSymbols {
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

  static func previewableTextPrefix(
    contents: [HistoryItemContent],
    fallbackTitle: String,
    maxLength: Int,
    richTextParsingLimit: Int
  ) -> String {
    let index = ContentIndex(contents)

    let fileURLs = index.fileURLs
    if !fileURLs.isEmpty {
      return fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
        .shortened(to: maxLength)
    } else if let text = index.textPrefix(maxLength: maxLength), !text.isEmpty {
      return text
    } else if let rtf = index.rtfIfSmall(maxBytes: richTextParsingLimit), !rtf.string.isEmpty {
      return rtf.string.shortened(to: maxLength)
    } else if let html = index.htmlIfSmall(maxBytes: richTextParsingLimit), !html.string.isEmpty {
      return html.string.shortened(to: maxLength)
    } else {
      return fallbackTitle.shortened(to: maxLength)
    }
  }
}

private struct ContentIndex {
  private let contentsByType: [String: [Data]]
  private let nilValueTypes: Set<String>

  init(_ contents: [HistoryItemContent]) {
    var contentsByType: [String: [Data]] = [:]
    var nilValueTypes: Set<String> = []
    contentsByType.reserveCapacity(contents.count)

    for content in contents {
      guard let value = content.value else {
        nilValueTypes.insert(content.type)
        continue
      }

      contentsByType[content.type, default: []].append(value)
    }

    self.contentsByType = contentsByType
    self.nilValueTypes = nilValueTypes
  }

  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return allData(for: [.fileURL])
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }

  func contains(type: String, value: Data?) -> Bool {
    guard let value else {
      return nilValueTypes.contains(type)
    }

    guard let values = contentsByType[type] else {
      return false
    }

    return values.contains {
      ClipboardDataProcessor.dataLikelyEqual($0, value)
    }
  }

  func textPrefix(maxLength: Int) -> String? {
    data(for: [.string])?.stringPrefix(maxBytes: maxLength)
  }

  func rtfIfSmall(maxBytes: Int) -> NSAttributedString? {
    guard let data = data(for: [.rtf]), data.count <= maxBytes else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }

  func htmlIfSmall(maxBytes: Int) -> NSAttributedString? {
    guard let data = data(for: [.html]), data.count <= maxBytes else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  private var universalClipboardText: Bool {
    data(for: [.universalClipboard]) != nil &&
      data(for: [.html, .tiff, .png, .jpeg, .rtf, .string, .heic]) != nil
  }

  private func data(for types: [NSPasteboard.PasteboardType]) -> Data? {
    for type in types {
      if let data = contentsByType[type.rawValue]?.first {
        return data
      }
    }

    return nil
  }

  private func allData(for types: [NSPasteboard.PasteboardType]) -> [Data] {
    types.flatMap { contentsByType[$0.rawValue] ?? [] }
  }
}

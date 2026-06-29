import AppKit

/// Pure helpers that operate on a history item's content entries without
/// touching SwiftData: building a dedup containment signature, testing
/// containment, and deriving a preview title.
enum HistoryItemEngine {
  /// A Sendable containment signature built from a set of content entries,
  /// used to test whether one item's contents are a subset of another's.
  struct Signature: Sendable {
    private let contents: [ContentSignature]

    init(
      contents: [HistoryItemContent],
      ignoringTypes transientTypes: Set<String>
    ) {
      self.contents = contents.compactMap { content in
        guard !transientTypes.contains(content.type) else {
          return nil
        }

        return ContentSignature(content)
      }
    }

    /// Returns true if every entry in this signature is present in `contents`.
    func isContained(in contents: [HistoryItemContent]) -> Bool {
      let index = ContentIndex(contents)
      return self.contents.allSatisfy {
        index.contains(type: $0.type, value: $0.value, fingerprint: $0.fingerprint)
      }
    }
  }

  /// Builds a containment signature from `contents`, dropping any entry whose
  /// type is in `transientTypes`.
  static func signature(
    contents: [HistoryItemContent],
    ignoringTypes transientTypes: Set<String>
  ) -> Signature {
    Signature(contents: contents, ignoringTypes: transientTypes)
  }

  /// Returns true if `contents` contains every entry described by `signature`.
  static func contains(
    contents: [HistoryItemContent],
    signature: Signature
  ) -> Bool {
    signature.isContained(in: contents)
  }

  /// Derives a single-line preview title from `contents`.
  ///
  /// When `showSpecialSymbols` is true, leading/trailing whitespace is rendered
  /// as `·` and embedded newlines/tabs as `⏎`/`⇥`; otherwise the result is
  /// trimmed. The text source is chosen by `previewableTextPrefix`.
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

  /// Returns the most useful text prefix from `contents`, in priority order:
  /// file URLs, plain string, small RTF, small HTML, then `fallbackTitle`.
  /// Each candidate is shortened to `maxLength`.
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

/// A single content entry projected for dedup: its type, value, and fingerprint.
private struct ContentSignature: Sendable {
  let type: String
  let value: Data?
  let fingerprint: UInt64?

  init(_ content: HistoryItemContent) {
    self.type = content.type
    self.value = content.value
    // Prefer the persisted fingerprint column; fall back to re-hashing when the
    // column is nil. Pre-migration rows have a nil column for their lifetime
    // (the write-back backfill was never implemented), so they are re-hashed on
    // every containment build rather than once.
    self.fingerprint = content.fingerprint
      ?? content.value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)
  }
}

/// Lookup index over a set of content entries, grouped by pasteboard type, that
/// answers containment queries and extracts preview text without re-hashing.
private struct ContentIndex: Sendable {
  // Carries each lhs item's fingerprint so `contains` can pass it to
  // `dataLikelyEqual`. For rows with a populated column (post-migration inserts)
  // this avoids re-hashing; for pre-migration rows (nil column, no backfill) the
  // carried value is freshly re-hashed on each build.
  private let contentsByType: [String: [(Data, UInt64?)]]
  private let nilValueTypes: Set<String>

  init(_ contents: [HistoryItemContent]) {
    var contentsByType: [String: [(Data, UInt64?)]] = [:]
    var nilValueTypes: Set<String> = []
    contentsByType.reserveCapacity(contents.count)

    for content in contents {
      guard let value = content.value else {
        nilValueTypes.insert(content.type)
        continue
      }

      contentsByType[content.type, default: []].append((value, content.fingerprint))
    }

    self.contentsByType = contentsByType
    self.nilValueTypes = nilValueTypes
  }

  /// File URLs carried by the content, unless this is a Handoff (universal
  /// clipboard) payload that also carries other types.
  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return allData(for: [.fileURL])
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }

  /// Returns true if an entry of `type` with `value` (and matching fingerprint)
  /// is present. A nil `value` matches any same-typed entry whose value is nil.
  func contains(type: String, value: Data?, fingerprint: UInt64?) -> Bool {
    guard let value else {
      return nilValueTypes.contains(type)
    }

    guard let values = contentsByType[type] else {
      return false
    }

    return values.contains { lhsData, lhsFingerprint in
      ClipboardDataProcessor.dataLikelyEqual(lhsData, lhsFingerprint, value, fingerprint)
    }
  }

  /// Returns the UTF-8-safe prefix of the first `.string` entry, up to
  /// `maxLength` bytes, or nil if there is no string entry.
  func textPrefix(maxLength: Int) -> String? {
    data(for: [.string])?.stringPrefix(maxBytes: maxLength)
  }

  /// Returns the attributed string parsed from the RTF entry, but only when it
  /// is no larger than `maxBytes` (parsing large RTF on the main thread is
  /// costly). Returns nil otherwise.
  func rtfIfSmall(maxBytes: Int) -> NSAttributedString? {
    guard let data = data(for: [.rtf]), data.count <= maxBytes else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }

  /// Returns the attributed string parsed from the HTML entry, but only when it
  /// is no larger than `maxBytes` (parsing large HTML on the main thread is
  /// costly). Returns nil otherwise.
  func htmlIfSmall(maxBytes: Int) -> NSAttributedString? {
    guard let data = data(for: [.html]), data.count <= maxBytes else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  /// True when a Handoff (universal clipboard) text payload is present, detected
  /// by a `.universalClipboard` entry alongside any of the concrete text/image
  /// types.
  private var universalClipboardText: Bool {
    data(for: [.universalClipboard]) != nil &&
      data(for: [.html, .tiff, .png, .jpeg, .rtf, .string, .heic]) != nil
  }

  /// Returns the first non-nil payload among `types`, in order.
  private func data(for types: [NSPasteboard.PasteboardType]) -> Data? {
    for type in types {
      if let entry = contentsByType[type.rawValue]?.first {
        return entry.0
      }
    }

    return nil
  }

  /// Returns every payload carried for any of `types`.
  private func allData(for types: [NSPasteboard.PasteboardType]) -> [Data] {
    types.flatMap { contentsByType[$0.rawValue] ?? [] }.map { $0.0 }
  }
}

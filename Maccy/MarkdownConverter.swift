import AppKit
import HTMLToMarkdown

// Converts clipboard content (HTML, RTF, plain text) into Markdown.
// Used by the "paste as Markdown" action (⌘⌥ by default).
enum MarkdownConverter {
  static func convert(_ contents: [HistoryItemContent]) -> String? {
    if let htmlData = contents.first(where: { NSPasteboard.PasteboardType($0.type) == .html })?.value,
       let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .unicode) {
      return convertHTML(html)
    }

    if let rtfData = contents.first(where: { NSPasteboard.PasteboardType($0.type) == .rtf })?.value,
       let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil),
       let htmlData = try? attributedString.data(
        from: NSRange(location: 0, length: attributedString.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
       ),
       let html = String(data: htmlData, encoding: .utf8) {
      return convertHTML(html)
    }

    if let stringData = contents.first(where: { NSPasteboard.PasteboardType($0.type) == .string })?.value,
       let string = String(data: stringData, encoding: .utf8) {
      return string
    }

    return nil
  }

  private static func convertHTML(_ html: String) -> String? {
    var tableOptions = TableOptions()
    tableOptions.cellPaddingBehavior = .minimal
    tableOptions.headerPromotion = true

    return try? HTMLToMarkdown.convert(
      normalizeWhitespace(html),
      // TablePlugin must be registered before GFMPlugin (which bundles its own
      // default-configured TablePlugin) so our options take precedence.
      plugins: [BasePlugin(), CommonmarkPlugin(), TablePlugin(options: tableOptions), GFMPlugin()]
    )
  }

  // Word/Excel clipboard HTML is hard-wrapped with raw \r\n inside inline text
  // (e.g. right before a <b>), which the converter otherwise renders as a
  // visible line break. Collapse insignificant whitespace the way a browser
  // would, while leaving <pre> content untouched.
  private static func normalizeWhitespace(_ html: String) -> String {
    let preRanges = html.ranges(of: try! Regex("(?is)<pre[^>]*>.*?</pre>"))
    guard !preRanges.isEmpty else {
      return html.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
    }

    var placeholders: [String: String] = [:]
    var working = html
    for (index, range) in preRanges.enumerated() {
      let token = "\u{0}PRE\(index)\u{0}"
      placeholders[token] = String(html[range])
      working = working.replacingOccurrences(of: String(html[range]), with: token)
    }

    working = working.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)

    for (token, original) in placeholders {
      working = working.replacingOccurrences(of: token, with: original)
    }

    return working
  }
}


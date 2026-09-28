import AppKit
import Defaults

// A rule that turns clipboard text matching `pattern` into a URL built from `urlTemplate`.
//
// Placeholders in the template:
//   {0}  or {match} — the whole match
//   {1}, {2}, ...   — regular expression capture groups
// Inserted values are percent-encoded.
struct LinkRule: Codable, Identifiable, Hashable, Defaults.Serializable {
  var id = UUID()
  var enabled = true
  var name: String
  var pattern: String
  var urlTemplate: String

  static let jira = LinkRule(
    name: "Jira",
    pattern: "^[A-Z][A-Z0-9]+-[0-9]+$",
    urlTemplate: "https://strategyagile.atlassian.net/browse/{0}"
  )

  var regex: NSRegularExpression? {
    try? NSRegularExpression(pattern: pattern)
  }

  var isValid: Bool {
    regex != nil && !urlTemplate.isEmpty
  }

  func url(for text: String) -> URL? {
    guard enabled, let regex else { return nil }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }

    var result = urlTemplate
    for index in (0..<match.numberOfRanges).reversed() {
      let group = match.range(at: index)
      let value = Range(group, in: text).map { String(text[$0]) } ?? ""
      let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
      result = result.replacingOccurrences(of: "{\(index)}", with: encoded)
      if index == 0 {
        result = result.replacingOccurrences(of: "{match}", with: encoded)
      }
    }

    guard let url = URL(string: result), url.scheme != nil else { return nil }
    return url
  }
}

enum LinkOpener {
  static func url(for text: String, rules: [LinkRule] = Defaults[.linkRules]) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return rules.lazy.compactMap { $0.url(for: trimmed) }.first
  }

  // Opens the current clipboard text in the default browser if any rule matches.
  static func openClipboard() {
    guard let text = NSPasteboard.general.string(forType: .string),
          let url = url(for: text) else {
      NSSound.beep()
      return
    }

    NSWorkspace.shared.open(url)
  }
}

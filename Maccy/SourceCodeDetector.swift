import AppKit

struct SourceCodeDetector {
  // Pasteboard types that indicate source code content from code editors.
  // When present, whitespace normalization is skipped to preserve indentation.
  private static let indicatorTypes: Set<String> = [
    NSPasteboard.PasteboardType.vscodeEditorData.rawValue
  ]

  static func containsSourceCode(_ contents: [HistoryItemContent]) -> Bool {
    // Check for known code editor pasteboard types (definitive signal).
    if contents.contains(where: { indicatorTypes.contains($0.type) }) {
      return true
    }

    // Check if the text content looks like code based on structure (heuristic).
    for content in contents where content.type == NSPasteboard.PasteboardType.string.rawValue {
      if let data = content.value,
         let string = String(data: data, encoding: .utf8),
         looksLikeCode(string) {
        return true
      }
    }

    return false
  }

  static func looksLikeCode(_ string: String) -> Bool {
    let lines = string.components(separatedBy: .newlines)
    guard lines.count > 1 else { return false }

    // Markdown/doc code block markers.
    if lines.contains(where: { $0.hasPrefix("```") || $0.hasPrefix("~~~") }) {
      return true
    }

    // Pipe tables (Markdown, ASCII): ≥2 lines with ≥2 pipe characters.
    let pipeLineCount = lines.filter({ line in
      line.filter({ $0 == "|" }).count >= 2
    }).count
    if pipeLineCount >= 2 {
      return true
    }

    // Tab-separated data: lines with internal tabs (not just leading).
    let tsvLineCount = lines.filter({ $0.range(of: "\\S\t", options: .regularExpression) != nil }).count
    if tsvLineCount >= 2 {
      return true
    }

    // Significant indentation (code, YAML, Python, etc.):
    // ≥3 indented lines, or ≥20% of non-empty lines are indented.
    let nonEmptyLines = lines.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    let indentedLineCount = nonEmptyLines.filter({ $0.hasPrefix("  ") || $0.hasPrefix("\t") }).count
    if indentedLineCount >= 3 {
      return true
    }
    if nonEmptyLines.count >= 5, Double(indentedLineCount) / Double(nonEmptyLines.count) >= 0.2 {
      return true
    }

    return false
  }
}

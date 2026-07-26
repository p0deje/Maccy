import AppKit
import Defaults
import Foundation
import Logging

// Runs user-configured automations against freshly copied text.
//
// Registered as an `onNewCopy` hook *after* `History.add`, so by the time it runs the original
// item is already in history. When one or more automations match, their scripts are chained
// (each transforms the previous output) and a single new item is produced: it becomes the
// current clipboard contents and the most-recent history entry, while the original copy is
// preserved.
@MainActor
final class AutomationProcessor {
  static let shared = AutomationProcessor()

  // Injectable so tests can stub script execution.
  var scriptRunner: ScriptRunning = ScriptRunner.shared

  private let logger = Logger(label: "org.p0deje.Maccy")

  // Synchronous entry point for the clipboard hook.
  func process(_ item: HistoryItem) {
    guard shouldProcess(item), let text = item.text else { return }

    let source = item.application
    Task { @MainActor in
      if let result = await buildResult(forText: text, source: source) {
        History.shared.add(result)
        Clipboard.shared.copy(result)
      }
    }
  }

  // Skip Maccy's own writes (prevents re-trigger loops) and non-text items.
  func shouldProcess(_ item: HistoryItem) -> Bool {
    !item.fromMaccy && (item.text?.isEmpty == false)
  }

  // Testable core: matches, chains scripts, and builds the resulting item without publishing
  // it. Returns nil when nothing matched, a script failed, or the output was empty/unchanged.
  func buildResult(forText text: String, source: String?) async -> HistoryItem? {
    let matching = Defaults[.automations].filter { $0.isEnabled && $0.matches(text) }
    guard !matching.isEmpty else { return nil }

    var current = text
    var isHTML = false

    for automation in matching {
      guard case let .runScript(config) = automation.action, !config.scriptName.isEmpty else {
        continue
      }

      do {
        let output = try await scriptRunner.run(scriptName: config.scriptName, input: current)
        let cleaned = trimTrailingNewlines(output)
        guard !cleaned.isEmpty else { continue }
        current = cleaned
        isHTML = config.parseResultAsHTML
      } catch {
        logger.error("Automation '\(automation.name)' script failed: \(error.localizedDescription)")
        return nil
      }
    }

    guard current != text else { return nil }
    return makeItem(output: current, isHTML: isHTML, source: source)
  }

  private func makeItem(output: String, isHTML: Bool, source: String?) -> HistoryItem {
    var contents = [HistoryItemContent]()

    if isHTML {
      let htmlData = Data(output.utf8)
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue, value: htmlData))
      // Plain-text fallback so paste-without-formatting and title generation still work.
      let plain = NSAttributedString(html: htmlData, documentAttributes: nil)?.string ?? output
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(plain.utf8)))
    } else {
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(output.utf8)))
    }

    let item = HistoryItem(contents: contents)
    item.application = source
    item.title = item.generateTitle()
    return item
  }

  private func trimTrailingNewlines(_ string: String) -> String {
    var result = Substring(string)
    while let last = result.last, last == "\n" || last == "\r" {
      result = result.dropLast()
    }
    return String(result)
  }
}

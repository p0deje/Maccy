import Foundation
import AppIntents

/// App Intent that returns a clipboard history item with its text, rich text,
/// HTML, image, or file contents.
struct Get: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "GetIntent"

  static let title: LocalizedStringResource = "Get Item from Clipboard History"
  static let description = IntentDescription("""
  Gets an item from Maccy clipboard history.
  The returned item can be used to access its plain/rich/HTML text, image contents or file location.
  """)

  /// When true, return the currently selected item instead of the one at `number`.
  @Parameter(title: "Selected", default: true)
  var selected: Bool

  /// 1-based position of the item to return when `selected` is false.
  @Parameter(title: "Number", default: 1)
  var number: Int

  /// Converts the 1-based `number` parameter to a 0-based collection index.
  private let positionOffset = 1

  static var parameterSummary: some ParameterSummary {
    When(\.$selected, .equalTo, false) {
      Summary {
        \.$number
        \.$selected
      }
    } otherwise: {
      Summary {
        \.$selected
      }
    }
  }

  /// Builds and returns a `HistoryItemAppEntity` for the selected or indexed item.
  ///
  /// Image contents are written to a temporary PNG file (data protection `.atomic`
  /// + `.completeFileProtection`) so the entity can expose them as a URL.
  @MainActor func perform() async throws -> some IntentResult & ReturnsValue<HistoryItemAppEntity> {
    var item: HistoryItem?
    if selected {
      item = AppState.shared.navigator.selection.first?.item
    } else {
      let index = number - positionOffset
      if index >= 0, AppState.shared.history.items.count > index {
        item = AppState.shared.history.items[index].item
      }
    }

    guard let item else {
      throw AppIntentError.notFound
    }

    let intentItem = HistoryItemAppEntity()
    intentItem.text = item.text

    if let html = item.htmlData {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = item.fileURLs.first {
      intentItem.file = fileURL
    }

    if let imageData = item.imageData {
      let file = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString).png")
      try imageData.write(to: file, options: [.atomic, .completeFileProtection])
      intentItem.image = file
    }

    if let rtf = item.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    return .result(value: intentItem)
  }
}

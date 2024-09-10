import Foundation
import AppIntents

struct Get: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "GetIntent"

  static var title: LocalizedStringResource = "Get Item from Clipboard History"
  static var description = IntentDescription("""
  Gets an item from Maccy clipboard history.
  The returned item can be used to access its plain/rich/HTML text, image contents or file location.
  """)

  @Parameter(title: "Selected", default: true)
  var selected: Bool

  @Parameter(title: "Number", default: 1)
  var number: Int

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

  func perform() async throws -> some IntentResult & ReturnsValue<HistoryItemAppEntity> {
    var item: HistoryItem?
    if selected {
      item = AppState.shared.history.selectedItem?.item
    } else {
      let index = number - positionOffset
      if AppState.shared.history.items.count >= index {
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
      let file = URL.documentsDirectory.appending(path: "image.png")
      try imageData.write(to: file, options: [.atomic, .completeFileProtection])
      intentItem.image = file
    }

    if let rtf = item.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    return .result(value: intentItem)
  }
}

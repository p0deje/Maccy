import Foundation
import AppIntents

struct Get: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "GetIntent"

  static var title: LocalizedStringResource = "Get Item from Clipboard History"
  static var description = IntentDescription("Gets an item from Maccy clipboard history. The returned item can be used to access its plain/rich/HTML text, image contents or file location.")

  @Parameter(title: "Selected", default: true)
  var selected: Bool

  @Parameter(title: "Number", default: 1)
  var number: Int

  private let positionOffset = 1

  @Dependency(key: "maccy")
  private var maccy: Maccy

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
    var item: HistoryItemL?
    if selected {
      item = maccy.selectedItem
    } else {
      let index = number - positionOffset
      item = maccy.item(at: index)
    }

    guard let item = item else {
      throw AppIntentError.notFound
    }

    let intentItem = HistoryItemAppEntity()
    intentItem.text = item.text

    if let html = item.htmlData {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = item.fileURLs.first {
      intentItem.file = IntentFile(
        fileURL: fileURL,
        filename: "",
        type: nil
      )
    }

    if let image = item.image?.tiffRepresentation {
      intentItem.image = IntentFile(
        data: image,
        filename: "",
        type: nil
      )
    }

    if let rtf = item.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    return .result(value: intentItem)
  }
}

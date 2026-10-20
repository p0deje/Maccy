import Foundation
import AppIntents

private nonisolated struct ItemContents: Sendable {
  let text: String?
  let html: Data?
  let file: URL?
  let image: Data?
  let rtf: Data?
}

struct Get: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "GetIntent"

  static let title: LocalizedStringResource = "Get Item from Clipboard History"
  static let description = IntentDescription("""
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
    let contents = try await MainActor.run { () -> ItemContents in
      var item: HistoryItem?
      if selected {
        item = AppState.shared.navigator.selection.first?.item
      } else {
        let index = number - positionOffset
        if AppState.shared.history.items.count >= index {
          item = AppState.shared.history.items[index].item
        }
      }

      guard let item else {
        throw AppIntentError.notFound
      }

      return ItemContents(
        text: item.text,
        html: item.htmlData,
        file: item.fileURLs.first,
        image: item.imageData,
        rtf: item.rtfData
      )
    }

    let intentItem = HistoryItemAppEntity()
    intentItem.text = contents.text

    if let html = contents.html {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = contents.file {
      intentItem.file = fileURL
    }

    if let imageData = contents.image {
      let file = URL.documentsDirectory.appending(path: "image.png")
      try imageData.write(to: file, options: [.atomic, .completeFileProtection])
      intentItem.image = file
    }

    if let rtf = contents.rtf {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    return .result(value: intentItem)
  }
}

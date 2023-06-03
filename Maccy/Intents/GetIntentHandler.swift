import AppKit
import Intents

@available(macOS 11.0, *)
class GetIntentHandler: NSObject, GetIntentHandling {
  private let positionOffset = 1
  private var maccy: Maccy!

  init(_ maccy: Maccy) {
    self.maccy = maccy
  }

  func handle(intent: GetIntent, completion: @escaping (GetIntentResponse) -> Void) {
    guard let selected = intent.selected as? Bool else {
      return completion(GetIntentResponse(code: .failure, userActivity: nil))
    }

    var item: HistoryItem?
    if selected {
      item = maccy.selectedItem
    } else {
      guard let number = intent.number as? Int else {
        return completion(GetIntentResponse(code: .failure, userActivity: nil))
      }

      let index = number - positionOffset
      item = maccy.item(at: index)
    }

    guard let item = item, let title = item.title else {
      return completion(GetIntentResponse(code: .failure, userActivity: nil))
    }

    let intentItem = IntentHistoryItem(identifier: item.title, display: title)
    intentItem.text = item.text

    if let html = item.htmlData {
      intentItem.html = String(data: html, encoding: .utf8)
    }

    if let fileURL = item.fileURL {
      intentItem.file = INFile(
        fileURL: fileURL,
        filename: "",
        typeIdentifier: nil
      )
    }

    if let image = item.image?.tiffRepresentation {
      intentItem.image = INFile(data: image, filename: "", typeIdentifier: nil)
    }

    if let rtf = item.rtfData {
      intentItem.richText = String(data: rtf, encoding: .utf8)
    }

    let response = GetIntentResponse(code: .success, userActivity: nil)
    response.item = intentItem
    return completion(response)
  }

  func resolveSelected(for intent: GetIntent, with completion: @escaping (INBooleanResolutionResult) -> Void) {
    guard let selected = intent.selected as? Bool else {
      return completion(.needsValue())
    }

    return completion(.success(with: selected))
  }

  func resolveNumber(for intent: GetIntent, with completion: @escaping (GetNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(.needsValue())
    }

    return completion(.success(with: number))
  }
}

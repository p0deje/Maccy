import Intents

@available(macOS 11.0, *)
class SelectIntentHandler: NSObject, SelectIntentHandling {
  private let positionOffset = 1
  private var maccy: Maccy!

  init(_ maccy: Maccy) {
    self.maccy = maccy
  }

  func handle(intent: SelectIntent, completion: @escaping (SelectIntentResponse) -> Void) {
    guard let number = intent.number as? Int,
          let value = maccy.select(position: number - positionOffset) else {
      return completion(SelectIntentResponse(code: .failure, userActivity: nil))
    }

    let response = SelectIntentResponse(code: .success, userActivity: nil)
    response.value = value
    return completion(response)
  }

  func resolveNumber(for intent: SelectIntent, with completion: @escaping (SelectNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(.needsValue())
    }

    return completion(.success(with: number))
  }
}

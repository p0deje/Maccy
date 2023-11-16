import Intents

@available(macOS 11.0, *)
class DeleteIntentHandler: NSObject, DeleteIntentHandling {
  private let positionOffset = 1
  private var maccy: Maccy!

  init(_ maccy: Maccy) {
    self.maccy = maccy
  }

  func handle(intent: DeleteIntent, completion: @escaping (DeleteIntentResponse) -> Void) {
    guard let number = intent.number as? Int,
          let value = maccy.delete(position: number - positionOffset) else {
      return completion(DeleteIntentResponse(code: .failure, userActivity: nil))
    }

    let response = DeleteIntentResponse(code: .success, userActivity: nil)
    response.value = value
    return completion(response)
  }

  func resolveNumber(for intent: DeleteIntent, with completion: @escaping (DeleteNumberResolutionResult) -> Void) {
    guard let number = intent.number as? Int else {
      return completion(.needsValue())
    }

    return completion(.success(with: number))
  }
}

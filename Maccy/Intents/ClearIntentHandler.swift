import Intents

@available(macOS 11.0, *)
class ClearIntentHandler: NSObject, ClearIntentHandling {
  private var maccy: Maccy!

  init(_ maccy: Maccy) {
    self.maccy = maccy
  }

  func handle(intent: ClearIntent, completion: @escaping (ClearIntentResponse) -> Void) {
    maccy.clearUnpinned()
    return completion(ClearIntentResponse(code: .success, userActivity: nil))
  }
}

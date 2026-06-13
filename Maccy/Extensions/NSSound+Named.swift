import AppKit.NSSound

extension NSSound {
  static let knock = Bundle.main.url(forResource: "Knock", withExtension: "caf").flatMap {
    NSSound(contentsOf: $0, byReference: true)
  }
  static let write = Bundle.main.url(forResource: "Write", withExtension: "caf").flatMap {
    NSSound(contentsOf: $0, byReference: true)
  }
}

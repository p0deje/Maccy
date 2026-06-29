import AppKit.NSSound

extension NSSound {
  /// The "Knock" feedback sound loaded from the app bundle, if present.
  static let knock = Bundle.main.url(forResource: "Knock", withExtension: "caf").flatMap {
    NSSound(contentsOf: $0, byReference: true)
  }
  /// The "Write" feedback sound loaded from the app bundle, if present.
  static let write = Bundle.main.url(forResource: "Write", withExtension: "caf").flatMap {
    NSSound(contentsOf: $0, byReference: true)
  }
}

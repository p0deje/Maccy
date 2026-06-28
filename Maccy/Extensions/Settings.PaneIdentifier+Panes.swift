import Settings

extension Settings.PaneIdentifier {
  // Swift 6 (SE-0412): a stored `static let` of this non-Sendable struct is
  // global shared mutable state. Computed `static var` getters have no backing
  // storage cell, so they are not global state at all — safe under complete
  // mode without @unchecked / nonisolated(unsafe). PaneIdentifier is a cheap
  // value struct wrapping a String; a fresh instance per access is negligible.
  static var advanced: Self { Self("advanced") }
  static var appearance: Self { Self("appearance") }
  static var general: Self { Self("general") }
  static var ignore: Self { Self("ignore") }
  static var pins: Self { Self("pins") }
  static var storage: Self { Self("storage") }
}

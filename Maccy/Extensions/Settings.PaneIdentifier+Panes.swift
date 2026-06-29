import Settings

extension Settings.PaneIdentifier {
  /// Identifiers for each settings pane shown in the settings window.
  ///
  /// These are computed `static var` getters rather than stored `static let`s because
  /// `PaneIdentifier` is a non-Sendable struct: a stored global would be shared mutable
  /// state under Swift's complete concurrency mode (SE-0412), whereas a computed getter
  /// has no backing storage cell and is therefore safe without `@unchecked` /
  /// `nonisolated(unsafe)`. The struct is a cheap value wrapping a `String`, so a fresh
  /// instance per access is negligible.
  static var advanced: Self { Self("advanced") }
  static var appearance: Self { Self("appearance") }
  static var general: Self { Self("general") }
  static var ignore: Self { Self("ignore") }
  static var pins: Self { Self("pins") }
  static var storage: Self { Self("storage") }
}

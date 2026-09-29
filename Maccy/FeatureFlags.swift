// Compile-time switches for features that this fork turns off.
enum FeatureFlags {
  // In-app updates through Sparkle. The feed points at upstream releases,
  // which would replace this fork and drop its own features, so keep it off
  // unless the feed is changed to one that serves this fork's builds.
  static let softwareUpdates = false
}

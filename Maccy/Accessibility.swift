import AppKit

/// Helpers for checking macOS Accessibility trust status.
struct Accessibility {
  /// Whether this process is currently trusted for Accessibility access.
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  /// Placeholder entry point for prompting the user when Accessibility
  /// permission is missing. The not-trusted branch is intentionally empty.
  static func check() {
    guard !allowed else {
      return
    }
  }
}

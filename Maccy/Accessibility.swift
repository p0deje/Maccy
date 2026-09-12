import AppKit

struct Accessibility {
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  /// Checks if the app has accessibility permissions.
  /// If not, prompts the user to grant them via System Settings.
  /// Returns true if permissions are granted, false otherwise.
  @discardableResult
  static func check() -> Bool {
    guard !allowed else {
      return true
    }

    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    return false
  }
}

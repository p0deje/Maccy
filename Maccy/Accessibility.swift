import AppKit

struct Accessibility {
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  static func check() {
    guard !allowed else {
      return
    }
  }
}

import AppKit.NSRunningApplication

// Originally on Lunar.
// https://github.com/alin23/Lunar/blob/master/Lunar/Data/Util.swift#L2401-L2409
// To test it without displaylink, change the identifier to something else running on your computer.
// Terminal is a good candidate, com.apple.Terminal.
let displayLinkIdentifier = "com.displaylink.DisplayLinkUserAgent"

extension NSRunningApplication {
  static func isDisplayLinkRunning() -> Bool {
      !NSRunningApplication.runningApplications(withBundleIdentifier: displayLinkIdentifier).isEmpty
  }
}

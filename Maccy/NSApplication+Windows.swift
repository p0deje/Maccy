import AppKit

extension NSApplication {
  static let statusBarWindowClass = "NSStatusBarWindow"

  var menuWindow: NSWindow? {
    windows.first { window in
      let className = String(describing: type(of: window))
      return (
        className == "NSPopupMenuWindow" // macOS 14 and later
          || className == "NSMenuWindowManagerWindow" // macOS 13 - 14
          || className == "NSCarbonMenuWindow" // macOS 12 and earlier
      )
    }
  }
}

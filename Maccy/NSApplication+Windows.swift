import AppKit

extension NSApplication {
  var characterPickerWindow: NSWindow? { windows.first { $0.className == "NSPanelViewBridge" } }
  var menuWindow: NSWindow? {
    windows.first { window in
      window.className == "NSPopupMenuWindow" // macOS 14 and later
        || window.className == "NSMenuWindowManagerWindow" // macOS 13 - 14
        || window.className == "NSCarbonMenuWindow" // macOS 12 and earlier
    }
  }
  var statusBarWindow: NSWindow? { windows.first { $0.className == "NSStatusBarWindow" } }
}

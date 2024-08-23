import AppKit

extension NSApplication {
  var alertWindow: NSWindow? { windows.first { $0.className == "_NSAlertPanel" } }
  var characterPickerWindow: NSWindow? { windows.first { $0.className == "NSPanelViewBridge" } }
}

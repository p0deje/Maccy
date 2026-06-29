import AppKit

extension NSApplication {
  /// The app's currently displayed alert panel, if any (matched by AppKit's internal class name).
  var alertWindow: NSWindow? { windows.first { $0.className == "_NSAlertPanel" } }
  /// The system character/emoji picker window, if currently open.
  var characterPickerWindow: NSWindow? { windows.first { $0.className == "NSPanelViewBridge" } }
}

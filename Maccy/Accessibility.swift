import AppKit

struct Accessibility {
  private static var alert: NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = NSLocalizedString("accessibility_alert_message", comment: "")
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_deny", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("accessibility_alert_open", comment: ""))
    alert.icon = NSImage(named: "NSSecurity")

    var locationName = NSLocalizedString("system_settings_name", comment: "")
    var paneName = NSLocalizedString("system_settings_pane", comment: "")
    if #unavailable(macOS 13) {
      locationName = NSLocalizedString("system_preferences_name", comment: "")
      paneName = NSLocalizedString("system_preferences_pane", comment: "")
    }

    alert.informativeText = NSLocalizedString("accessibility_alert_comment", comment: "")
      .replacingOccurrences(of: "{settings}", with: locationName)
      .replacingOccurrences(of: "{pane}", with: paneName)

    return alert
  }
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }
  private static let url = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  )

  static func check() {
    guard !allowed else { return }

    Maccy.returnFocusToPreviousApp = false
    // Show accessibility window async to allow menu to close.
    DispatchQueue.main.async {
      if alert.runModal() == NSApplication.ModalResponse.alertSecondButtonReturn,
         let url = url {
        NSWorkspace.shared.open(url)
      }
      Maccy.returnFocusToPreviousApp = true
    }
  }
}

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

  static var isAllowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  private static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  )

  static func check() {
    promptIfNeeded()
  }

  static func promptIfNeeded() {
    guard !isAllowed else { return }

    DispatchQueue.main.async {
      if alert.runModal() == .alertSecondButtonReturn, let settingsURL {
        NSWorkspace.shared.open(settingsURL)
      }
    }
  }
}

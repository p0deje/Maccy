import Cocoa
import Settings

class IgnorePreferenceViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.ignore
  public let paneTitle = NSLocalizedString("preferences_ignore", comment: "")
  public let toolbarItemIcon = NSImage(named: .nosign)!

  override var nibName: NSNib.Name? { "IgnorePreferenceViewController" }
}

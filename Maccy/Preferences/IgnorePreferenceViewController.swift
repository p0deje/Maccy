import Cocoa
import Preferences

class IgnorePreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.ignore
  public let preferencePaneTitle = NSLocalizedString("preferences_ignore", comment: "")
  public let toolbarItemIcon = NSImage(named: .nosign)!

  override var nibName: NSNib.Name? { "IgnorePreferenceViewController" }
}

import Cocoa
import Preferences

class AdvancedPreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.advanced
  public let preferencePaneTitle = NSLocalizedString("preferences_advanced", comment: "")
  public let toolbarItemIcon = NSImage(named: "advancedgearshape")!

  override var nibName: NSNib.Name? { "AdvancedPreferenceViewController" }

  @IBOutlet weak var turnOffButton: NSButton!
  @IBOutlet weak var avoidTakingFocusButton: NSButton!
  @IBOutlet weak var clearOnQuitButton: NSButton!

  private let exampleIgnoredType = "zzz.yyy.xxx"

  override func viewWillAppear() {
    super.viewWillAppear()
    populateTurnOff()
    populateAvoidTakingFocus()
    populateClearOnQuit()
  }

  @IBAction func turnOffChanged(_ sender: NSButton) {
    UserDefaults.standard.ignoreEvents = (sender.state == .on)
  }

  @IBAction func avoidTakingFocusChanged(_ sender: NSButton) {
    UserDefaults.standard.avoidTakingFocus = (sender.state == .on)
  }

  @IBAction func clearOnQuitChanged(_ sender: NSButton) {
    UserDefaults.standard.clearOnQuit = (sender.state == .on)
  }

  private func populateTurnOff() {
    turnOffButton.state = UserDefaults.standard.ignoreEvents ? .on : .off
  }

  private func populateAvoidTakingFocus() {
    avoidTakingFocusButton.state = UserDefaults.standard.avoidTakingFocus ? .on : .off
  }

  private func populateClearOnQuit() {
    clearOnQuitButton.state = UserDefaults.standard.clearOnQuit ? .on : .off
  }
}

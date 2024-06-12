import Cocoa
import Defaults
import Settings

class AdvancedSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.advanced
  public let paneTitle = NSLocalizedString("preferences_advanced", comment: "")
  public let toolbarItemIcon = NSImage(named: .gearshape2)!

  override var nibName: NSNib.Name? { "AdvancedSettingsViewController" }

  @IBOutlet weak var turnOffButton: NSButton!
  @IBOutlet weak var avoidTakingFocusButton: NSButton!
  @IBOutlet weak var clearOnQuitButton: NSButton!
  @IBOutlet weak var clearSystemClipboardButton: NSButton!

  private let exampleIgnoredType = "zzz.yyy.xxx"

  override func viewWillAppear() {
    super.viewWillAppear()
    populateTurnOff()
    populateAvoidTakingFocus()
    populateClearOnQuit()
    populateClearSystemClipboard()
  }

  @IBAction func turnOffChanged(_ sender: NSButton) {
    Defaults[.ignoreEvents] = (sender.state == .on)
  }

  @IBAction func avoidTakingFocusChanged(_ sender: NSButton) {
    Defaults[.avoidTakingFocus] = (sender.state == .on)
  }

  @IBAction func clearOnQuitChanged(_ sender: NSButton) {
    Defaults[.clearOnQuit] = (sender.state == .on)
  }

  @IBAction func clearSystemClipboardChanged(_ sender: NSButton) {
    Defaults[.clearSystemClipboard] = (sender.state == .on)
  }

  private func populateTurnOff() {
    turnOffButton.state = Defaults[.ignoreEvents] ? .on : .off
  }

  private func populateAvoidTakingFocus() {
    avoidTakingFocusButton.state = Defaults[.avoidTakingFocus] ? .on : .off
  }

  private func populateClearOnQuit() {
    clearOnQuitButton.state = Defaults[.clearOnQuit] ? .on : .off
  }

  private func populateClearSystemClipboard() {
    clearSystemClipboardButton.state = Defaults[.clearSystemClipboard] ? .on : .off
  }
}

import Cocoa
import KeyHolder
import LoginServiceKit
import Magnet
import Preferences
import Sparkle

class GeneralPreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = PreferencePane.Identifier.general
  public let preferencePaneTitle = NSLocalizedString("preferences_general", comment: "")
  public let toolbarItemIcon = NSImage(named: NSImage.preferencesGeneralName)!

  override var nibName: NSNib.Name? { "GeneralPreferenceViewController" }

  @IBOutlet weak var hotkeyButton: RecordView!
  @IBOutlet weak var launchAtLoginButton: NSButton!
  @IBOutlet weak var fuzzySearchButton: NSButton!
  @IBOutlet weak var pasteAutomaticallyButton: NSButton!
  @IBOutlet weak var historySizeSlider: NSSlider!
  @IBOutlet weak var historySizeLabel: NSTextField!
  @IBOutlet weak var sortByButton: NSPopUpButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    hotkeyButton.didChange = hotkeyChanged(_:)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateHotkey()
    populateLaunchAtLogin()
    populateFuzzySearch()
    populatePasteAutomatically()
    populateHistorySize()
    populateSortBy()
  }

  @IBAction func launchAtLoginChanged(_ sender: NSButton) {
    if sender.state == .on {
      LoginServiceKit.addLoginItems()
    } else {
      LoginServiceKit.removeLoginItems()
    }
  }

  @IBAction func checkForUpdatesClicked(_ sender: NSButton) {
    SUUpdater.shared()?.checkForUpdates(self)
  }

  @IBAction func fuzzySearchChanged(_ sender: NSButton) {
    UserDefaults.standard.fuzzySearch = (sender.state == .on)
  }

  @IBAction func pasteAutomaticallyChanged(_ sender: NSButton) {
    UserDefaults.standard.pasteByDefault = (sender.state == .on)
  }

  @IBAction func historySizeChanged(_ sender: NSSlider) {
    updateHistorySizeLabel(old: String(UserDefaults.standard.size), new: String(historySizeSlider.integerValue))
    UserDefaults.standard.size = sender.integerValue
  }

  @IBAction func sortByChanged(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 2:
      UserDefaults.standard.sortBy = "numberOfCopies"
    case 1:
      UserDefaults.standard.sortBy = "firstCopiedAt"
    default:
      UserDefaults.standard.sortBy = "lastCopiedAt"
    }
  }

  private func hotkeyChanged(_ keyCombo: KeyCombo?) {
    guard let keyCombo = keyCombo else {
      return
    }

    var hotkey: [String] = []
    if keyCombo.keyEquivalentModifierMask.contains(.command) {
      hotkey.append("command")
    }
    if keyCombo.keyEquivalentModifierMask.contains(.shift) {
      hotkey.append("shift")
    }
    if keyCombo.keyEquivalentModifierMask.contains(.control) {
      hotkey.append("control")
    }
    if keyCombo.keyEquivalentModifierMask.contains(.option) {
      hotkey.append("option")
    }

    hotkey.append(keyCombo.keyEquivalent)

    UserDefaults.standard.hotKey = hotkey.joined(separator: "+")
  }

  private func populateHotkey() {
    if let key = GlobalHotKey.key, let modifierFlags = GlobalHotKey.modifierFlags {
      hotkeyButton.keyCombo = KeyCombo(key: key, cocoaModifiers: modifierFlags)
    }
  }

  private func populateLaunchAtLogin() {
    launchAtLoginButton.state = LoginServiceKit.isExistLoginItems() ? .on : .off
  }

  private func populateFuzzySearch() {
    fuzzySearchButton.state = UserDefaults.standard.fuzzySearch ? .on : .off
  }

  private func populatePasteAutomatically() {
    pasteAutomaticallyButton.state = UserDefaults.standard.pasteByDefault ? .on : .off
  }

  private func populateHistorySize() {
    historySizeSlider.integerValue = UserDefaults.standard.size
    updateHistorySizeLabel(old: "{historySize}", new: String(historySizeSlider.integerValue))
  }

  private func updateHistorySizeLabel(old: String, new: String) {
    let newLabelValue = historySizeLabel.stringValue.replacingOccurrences(
      of: old,
      with: new,
      options: [],
      range: historySizeLabel.stringValue.range(of: old)
    )
    historySizeLabel.stringValue = newLabelValue
  }

  private func populateSortBy() {
    switch UserDefaults.standard.sortBy {
    case "numberOfCopies":
      sortByButton.selectItem(withTag: 2)
    case "firstCopiedAt":
      sortByButton.selectItem(withTag: 1)
    default:
      sortByButton.selectItem(withTag: 0)
    }
  }
}

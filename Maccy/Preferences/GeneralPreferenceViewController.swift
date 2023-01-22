import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import Preferences

class GeneralPreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.general
  public let preferencePaneTitle = NSLocalizedString("preferences_general", comment: "")
  public let toolbarItemIcon = NSImage(named: .gearshape)!

  override var nibName: NSNib.Name? { "GeneralPreferenceViewController" }

  private let hotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .popup)

  @IBOutlet weak var hotkeyContainerView: NSView!
  @IBOutlet weak var launchAtLoginButton: NSButton!
  @IBOutlet weak var searchModeButton: NSPopUpButton!
  @IBOutlet weak var pasteAutomaticallyButton: NSButton!
  @IBOutlet weak var removeFormattingButton: NSButton!
  @IBOutlet weak var modifiersDescriptionLabel: NSTextField!
  @IBOutlet weak var soundsButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    hotkeyContainerView.addSubview(hotkeyRecorder)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateLaunchAtLogin()
    populateSearchMode()
    populatePasteAutomatically()
    populateRemoveFormatting()
    updateModifiersDescriptionLabel()
    populateSounds()
  }

  @IBAction func launchAtLoginChanged(_ sender: NSButton) {
    LaunchAtLogin.isEnabled = (sender.state == .on)
  }

  @IBAction func searchModeChanged(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 3:
      UserDefaults.standard.searchMode = Search.Mode.mixed.rawValue
    case 2:
      UserDefaults.standard.searchMode = Search.Mode.regexp.rawValue
    case 1:
      UserDefaults.standard.searchMode = Search.Mode.fuzzy.rawValue
    default:
      UserDefaults.standard.searchMode = Search.Mode.exact.rawValue
    }
  }

  @IBAction func pasteAutomaticallyChanged(_ sender: NSButton) {
    UserDefaults.standard.pasteByDefault = (sender.state == .on)
    updateModifiersDescriptionLabel()
  }

  @IBAction func removeFormattingChanged(_ sender: NSButton) {
    UserDefaults.standard.removeFormattingByDefault = (sender.state == .on)
    updateModifiersDescriptionLabel()
  }

  @IBAction func soundsChanged(_ sender: NSButton) {
    UserDefaults.standard.playSounds = (sender.state == .on)
  }

  private func populateLaunchAtLogin() {
    launchAtLoginButton.state = LaunchAtLogin.isEnabled ? .on : .off
  }

  private func populateSearchMode() {
    switch Search.Mode(rawValue: UserDefaults.standard.searchMode) {
    case .mixed:
      searchModeButton.selectItem(withTag: 3)
    case .regexp:
      searchModeButton.selectItem(withTag: 2)
    case .fuzzy:
      searchModeButton.selectItem(withTag: 1)
    default:
      searchModeButton.selectItem(withTag: 0)
    }
  }

  private func populatePasteAutomatically() {
    pasteAutomaticallyButton.state = UserDefaults.standard.pasteByDefault ? .on : .off
  }

  private func populateRemoveFormatting() {
    removeFormattingButton.state = UserDefaults.standard.removeFormattingByDefault ? .on : .off
  }

  private func updateModifiersDescriptionLabel() {
    let descriptions = [
      String(format: NSLocalizedString("copy_modifiers_config", comment: ""),
             HistoryMenuItem.CopyMenuItem.keyEquivalentModifierMask.description),
      String(format: NSLocalizedString("paste_modifiers_config", comment: ""),
             HistoryMenuItem.PasteMenuItem.keyEquivalentModifierMask.description),
      String(format: NSLocalizedString("format_modifiers_config", comment: ""),
             HistoryMenuItem.PasteWithoutFormattingMenuItem.keyEquivalentModifierMask.description)
    ]
    modifiersDescriptionLabel.stringValue = descriptions.joined(separator: "\n")
  }

  private func populateSounds() {
    soundsButton.state = UserDefaults.standard.playSounds ? .on : .off
  }
}

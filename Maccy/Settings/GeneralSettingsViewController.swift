import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import Settings

class GeneralSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.general
  public let paneTitle = NSLocalizedString("preferences_general", comment: "")
  public let toolbarItemIcon = NSImage(named: .gearshape)!

  override var nibName: NSNib.Name? { "GeneralSettingsViewController" }

  private let popupHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .popup)
  private let pinHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .pin)
  private let deleteHotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .delete)

  private lazy var notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @IBOutlet weak var popupHotkeyContainerView: NSView!
  @IBOutlet weak var pinHotkeyContainerView: NSView!
  @IBOutlet weak var deleteHotkeyContainerView: NSView!
  @IBOutlet weak var launchAtLoginButton: NSButton!
  @IBOutlet weak var searchModeButton: NSPopUpButton!
  @IBOutlet weak var pasteAutomaticallyButton: NSButton!
  @IBOutlet weak var removeFormattingButton: NSButton!
  @IBOutlet weak var modifiersDescriptionLabel: NSTextField!
  @IBOutlet weak var notificationsButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    popupHotkeyContainerView.addSubview(popupHotkeyRecorder)
    pinHotkeyContainerView.addSubview(pinHotkeyRecorder)
    deleteHotkeyContainerView.addSubview(deleteHotkeyRecorder)
    loadNotificationsLink()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateLaunchAtLogin()
    populateSearchMode()
    populatePasteAutomatically()
    populateRemoveFormatting()
    updateModifiersDescriptionLabel()
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

  @IBAction func notificationsButtonClicked(_ sender: NSButton) {
    guard let notificationsURL else { return }

    NSWorkspace.shared.open(notificationsURL)
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

  private func loadNotificationsLink() {
    guard let notificationsURL else { return }

    notificationsButton.attributedTitle = NSMutableAttributedString(
      string: notificationsButton.title,
      attributes: [
        .link: notificationsURL
      ]
    )
  }
}

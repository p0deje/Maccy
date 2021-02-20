import Cocoa
import KeyboardShortcuts
import LoginServiceKit
import Preferences

class GeneralPreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.general
  public let preferencePaneTitle = NSLocalizedString("preferences_general", comment: "")
  public let toolbarItemIcon = NSImage(named: NSImage.preferencesGeneralName)!

  override var nibName: NSNib.Name? { "GeneralPreferenceViewController" }

  private let hotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .popup)
  
  private let privateModeHotkeyRecoder = KeyboardShortcuts.RecorderCocoa(for: .privateMode)


  @IBOutlet weak var hotkeyContainerView: NSView!
  @IBOutlet weak var privateModeHotkeyContainerView: NSView!
  @IBOutlet weak var launchAtLoginButton: NSButton!
  @IBOutlet weak var fuzzySearchButton: NSButton!
  @IBOutlet weak var pasteAutomaticallyButton: NSButton!
  @IBOutlet weak var removeFormattingButton: NSButton!
  @IBOutlet weak var modifiersDescriptionLabel: NSTextField!
  @IBOutlet weak var soundsButton: NSButton!
  @IBOutlet weak var historySizeSlider: NSSlider!
  @IBOutlet weak var historySizeLabel: NSTextField!
  @IBOutlet weak var sortByButton: NSPopUpButton!
  @IBOutlet weak var storeFilesButton: NSButton!
  @IBOutlet weak var storeImagesButton: NSButton!
  @IBOutlet weak var storeTextButton: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    hotkeyContainerView.addSubview(hotkeyRecorder)
    privateModeHotkeyContainerView.addSubview(privateModeHotkeyRecoder)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateLaunchAtLogin()
    populateFuzzySearch()
    populatePasteAutomatically()
    populateRemoveFormatting()
    updateModifiersDescriptionLabel()
    populateSounds()
    populateHistorySize()
    populateSortBy()
    populateStoredTypes()
  }

  @IBAction func launchAtLoginChanged(_ sender: NSButton) {
    if sender.state == .on {
      LoginServiceKit.addLoginItems()
    } else {
      LoginServiceKit.removeLoginItems()
    }
  }

  @IBAction func fuzzySearchChanged(_ sender: NSButton) {
    UserDefaults.standard.fuzzySearch = (sender.state == .on)
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

  @IBAction func storeFilesChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.fileURL]
    sender.state == .on ? addEnabledTypes(types) : removeEnabledTypes(types)
  }

  @IBAction func storeImagesChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png]
    sender.state == .on ? addEnabledTypes(types) : removeEnabledTypes(types)
  }

  @IBAction func storeTextChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.string]
    sender.state == .on ? addEnabledTypes(types) : removeEnabledTypes(types)
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

  private func populateStoredTypes() {
    let types = UserDefaults.standard.enabledPasteboardTypes
    storeFilesButton.state = types.contains(.fileURL) ? .on : .off
    storeImagesButton.state = types.isSuperset(of: [.tiff, .png]) ? .on : .off
    storeTextButton.state = types.contains(.string) ? .on : .off
  }

  private func addEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    UserDefaults.standard.enabledPasteboardTypes = UserDefaults.standard.enabledPasteboardTypes.union(types)
  }

  private func removeEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    UserDefaults.standard.enabledPasteboardTypes = UserDefaults.standard.enabledPasteboardTypes.subtracting(types)
  }
}

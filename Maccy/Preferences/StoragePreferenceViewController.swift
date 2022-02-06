import Cocoa
import Preferences

class StoragePreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.storage
  public let preferencePaneTitle = NSLocalizedString("preferences_storage", comment: "")
  public let toolbarItemIcon = NSImage(named: .externaldrive)!

  override var nibName: NSNib.Name? { "StoragePreferenceViewController" }

  @IBOutlet weak var historySizeSlider: NSSlider!
  @IBOutlet weak var historySizeLabel: NSTextField!
  @IBOutlet weak var sortByButton: NSPopUpButton!
  @IBOutlet weak var storeFilesButton: NSButton!
  @IBOutlet weak var storeImagesButton: NSButton!
  @IBOutlet weak var storeTextButton: NSButton!

  override func viewWillAppear() {
    super.viewWillAppear()
    populateHistorySize()
    populateSortBy()
    populateStoredTypes()
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

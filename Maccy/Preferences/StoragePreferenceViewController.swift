import Cocoa
import Preferences

class StoragePreferenceViewController: NSViewController, PreferencePane {
  let preferencePaneIdentifier = Preferences.PaneIdentifier.storage
  let preferencePaneTitle = NSLocalizedString("preferences_storage", comment: "")
  let toolbarItemIcon = NSImage(named: .externaldrive)!

  let sizeMin = 1
  let sizeMax = 999

  override var nibName: NSNib.Name? { "StoragePreferenceViewController" }

  @IBOutlet weak var sizeTextField: NSTextField!
  @IBOutlet weak var sizeStepper: NSStepper!
  @IBOutlet weak var sortByButton: NSPopUpButton!
  @IBOutlet weak var storeFilesButton: NSButton!
  @IBOutlet weak var storeImagesButton: NSButton!
  @IBOutlet weak var storeTextButton: NSButton!

  private var sizeFormatter: NumberFormatter!

  override func viewDidLoad() {
    super.viewDidLoad()
    setMinAndMaxSize()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateSize()
    populateSortBy()
    populateStoredTypes()
  }

  @IBAction func sizeFieldChanged(_ sender: NSTextField) {
    UserDefaults.standard.size = sender.integerValue
    sizeStepper.integerValue = sender.integerValue
  }

  @IBAction func sizeStepperChanged(_ sender: NSStepper) {
    UserDefaults.standard.size = sender.integerValue
    sizeTextField.integerValue = sender.integerValue
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

  private func setMinAndMaxSize() {
    sizeFormatter = NumberFormatter()
    sizeFormatter.minimum = sizeMin as NSNumber
    sizeFormatter.maximum = sizeMax as NSNumber
    sizeFormatter.maximumFractionDigits = 0
    sizeTextField.formatter = sizeFormatter
    sizeStepper.minValue = Double(sizeMin)
    sizeStepper.maxValue = Double(sizeMax)
  }

  private func populateSize() {
    sizeTextField.integerValue = UserDefaults.standard.size
    sizeStepper.integerValue = UserDefaults.standard.size
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

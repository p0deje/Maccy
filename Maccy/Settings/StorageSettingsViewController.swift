import Cocoa
import Defaults
import Settings

class StorageSettingsViewController: NSViewController, SettingsPane {
  let paneIdentifier = Settings.PaneIdentifier.storage
  let paneTitle = NSLocalizedString("preferences_storage", comment: "")
  let toolbarItemIcon = NSImage(named: .externaldrive)!

  let sizeMin = 1
  let sizeMax = 999

  override var nibName: NSNib.Name? { "StorageSettingsViewController" }

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
    Defaults[.size] = sender.integerValue
    sizeStepper.integerValue = sender.integerValue
  }

  @IBAction func sizeStepperChanged(_ sender: NSStepper) {
    Defaults[.size] = sender.integerValue
    sizeTextField.integerValue = sender.integerValue
  }

  @IBAction func sortByChanged(_ sender: NSPopUpButton) {
    switch sender.selectedTag() {
    case 2:
      Defaults[.sortBy] = "numberOfCopies"
    case 1:
      Defaults[.sortBy] = "firstCopiedAt"
    default:
      Defaults[.sortBy] = "lastCopiedAt"
    }
  }

  @IBAction func storeFilesChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.fileURL]
    if sender.state == .on {
      addEnabledTypes(types)
    } else {
      removeEnabledTypes(types)
    }
  }

  @IBAction func storeImagesChanged(_ sender: NSButton) {
    let types: Set = [NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png]
    if sender.state == .on {
      addEnabledTypes(types)
    } else {
      removeEnabledTypes(types)
    }
  }

  @IBAction func storeTextChanged(_ sender: NSButton) {
    let types: Set = [
      NSPasteboard.PasteboardType.html,
      NSPasteboard.PasteboardType.rtf,
      NSPasteboard.PasteboardType.string
    ]
    if sender.state == .on {
      addEnabledTypes(types)
    } else {
      removeEnabledTypes(types)
    }
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
    sizeTextField.integerValue = Defaults[.size]
    sizeStepper.integerValue = Defaults[.size]
  }

  private func populateSortBy() {
    switch Defaults[.sortBy] {
    case "numberOfCopies":
      sortByButton.selectItem(withTag: 2)
    case "firstCopiedAt":
      sortByButton.selectItem(withTag: 1)
    default:
      sortByButton.selectItem(withTag: 0)
    }
  }

  private func populateStoredTypes() {
    let types = Defaults[.enabledPasteboardTypes]
    storeFilesButton.state = types.contains(.fileURL) ? .on : .off
    storeImagesButton.state = types.isSuperset(of: [.tiff, .png]) ? .on : .off
    storeTextButton.state = types.contains(.string) ? .on : .off
  }

  private func addEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    Defaults[.enabledPasteboardTypes] = Defaults[.enabledPasteboardTypes].union(types)
  }

  private func removeEnabledTypes(_ types: Set<NSPasteboard.PasteboardType>) {
    Defaults[.enabledPasteboardTypes] = Defaults[.enabledPasteboardTypes].subtracting(types)
  }
}

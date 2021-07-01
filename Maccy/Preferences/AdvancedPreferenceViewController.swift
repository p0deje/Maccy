import Cocoa
import Preferences

class AdvancedPreferenceViewController: NSViewController, NSTableViewDataSource, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.advanced
  public let preferencePaneTitle = NSLocalizedString("preferences_advanced", comment: "")
  public let toolbarItemIcon = NSImage(named: "advancedgearshape")!

  override var nibName: NSNib.Name? { "AdvancedPreferenceViewController" }

  @IBOutlet weak var turnOffButton: NSButton!
  @IBOutlet weak var avoidTakingFocusButton: NSButton!
  @IBOutlet weak var clearOnQuitButton: NSButton!
  @IBOutlet weak var ignoredItemsTable: NSTableView!

  private let exampleIgnoredType = "zzz.yyy.xxx"

  private var ignoredTypes: [String] {
    get { UserDefaults.standard.ignoredPasteboardTypes.sorted() }
    set { UserDefaults.standard.ignoredPasteboardTypes = Set(newValue) }
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateTurnOff()
    populateAvoidTakingFocus()
    populateClearOnQuit()
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return ignoredTypes.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return ignoredTypes[row]
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let object = object as? String else {
      return
    }

    guard !object.isEmpty else {
      removeIgnoredType(row)
      return
    }

    ignoredTypes[row] = object
    ignoredItemsTable.reloadData()
    if let newIndex = ignoredTypes.firstIndex(of: object) {
      ignoredItemsTable.deselectRow(row)
      ignoredItemsTable.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
    }
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

  @IBAction func ignoredTypeAddedOrRemoved(_ sender: NSSegmentedCell) {
    switch sender.selectedSegment {
    case 0:
      addIgnoredType()
    case 1:
      guard ignoredItemsTable.selectedRow != -1 else {
        return
      }

      removeIgnoredType(ignoredItemsTable.selectedRow)
    default:
      return
    }
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

  private func addIgnoredType() {
    ignoredTypes.append(exampleIgnoredType)
    ignoredItemsTable.reloadData()
    ignoredItemsTable.editColumn(0, row: ignoredTypes.firstIndex(of: exampleIgnoredType)!, with: nil, select: true)
  }

  private func removeIgnoredType(_ row: Int) {
    ignoredTypes.remove(at: row)
    ignoredItemsTable.reloadData()
  }
}

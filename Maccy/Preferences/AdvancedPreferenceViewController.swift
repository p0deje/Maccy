import Cocoa
import Preferences

class AdvancedPreferenceViewController: NSViewController, NSTableViewDataSource, PreferencePane {
  public let preferencePaneIdentifier = PreferencePane.Identifier.advanced
  public let preferencePaneTitle = "Advanced"
  public let toolbarItemIcon = NSImage(named: NSImage.advancedName)!

  override var nibName: NSNib.Name? { "AdvancedPreferenceViewController" }

  @IBOutlet weak var turnOffButton: NSButton!
  @IBOutlet weak var ignoredItemsTable: NSTableView!

  private let exampleIgnoredType = "zzz.yyy.xxx"

  private var ignoredTypes: [String] {
    get { UserDefaults.standard.ignoredPasteboardTypes.sorted() }
    set { UserDefaults.standard.ignoredPasteboardTypes = Set(newValue) }
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    populateTurnOff()
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
    UserDefaults.standard.ignoreEvents = (turnOffButton.state == .on)
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

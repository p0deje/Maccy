import Cocoa

class IgnoreRegexViewController: NSViewController, NSTableViewDataSource {
  @IBOutlet weak var ignoredItemsTable: NSTableView!

  private let exampleIgnoredRegex = "^[a-zA-Z0-9]{50}$"

  private var ignoredRegexp: [String] {
    get { UserDefaults.standard.ignoreRegexp.sorted() }
    set { UserDefaults.standard.ignoreRegexp = newValue }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return ignoredRegexp.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return ignoredRegexp[row]
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let object = object as? String else {
      return
    }

    guard !object.isEmpty else {
      removeIgnoredRegex(row)
      return
    }

    ignoredRegexp[row] = object
    ignoredItemsTable.reloadData()
    if let newIndex = ignoredRegexp.firstIndex(of: object) {
      ignoredItemsTable.deselectRow(row)
      ignoredItemsTable.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
    }
  }

  @IBAction func ignoredRegexAddedOrRemoved(_ sender: NSSegmentedCell) {
    switch sender.selectedSegment {
    case 0:
      addIgnoredRegex()
    case 1:
      guard ignoredItemsTable.selectedRow != -1 else {
        return
      }

      removeIgnoredRegex(ignoredItemsTable.selectedRow)
    default:
      return
    }
  }

  private func addIgnoredRegex() {
    ignoredRegexp.append(exampleIgnoredRegex)
    ignoredItemsTable.reloadData()
    ignoredItemsTable.editColumn(0, row: ignoredRegexp.firstIndex(of: exampleIgnoredRegex)!, with: nil, select: true)
  }

  private func removeIgnoredRegex(_ row: Int) {
    ignoredRegexp.remove(at: row)
    ignoredItemsTable.reloadData()
  }
}

import Cocoa

class IgnoreApplicationsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  @IBOutlet weak var ignoredItemsTable: NSTableView!

  private let appCellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "appCell")

  private var chooseAppDialog: NSOpenPanel {
    let dialog = NSOpenPanel()
    dialog.allowedFileTypes = ["app"]
    dialog.allowsMultipleSelection = false
    dialog.canChooseDirectories = false
    dialog.directoryURL = URL(string: "/Applications")
    dialog.showsResizeIndicator = true
    dialog.showsHiddenFiles = false
    dialog.title = "Choose an application"
    return dialog
  }

  private var ignoredApps: [String] {
    get { UserDefaults.standard.ignoredApps }
    set { UserDefaults.standard.ignoredApps = newValue }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return ignoredApps.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let appCell = tableView.makeView(withIdentifier: appCellIdentifier, owner: self) as? NSTableCellView else {
      return nil
    }

    let appIdentifier = ignoredApps[row]
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appIdentifier) {
      appCell.imageView?.image = NSWorkspace.shared.icon(forFile: url.path)
      appCell.textField?.stringValue = NSWorkspace.shared.applicationName(url: url)
    } else {
      appCell.imageView?.image = nil
      appCell.textField?.stringValue = appIdentifier
    }

    return appCell
  }

  @IBAction func ignoredAppAddedOrRemoved(_ sender: NSSegmentedCell) {
    switch sender.selectedSegment {
    case 0:
      addIgnoredApp()
    case 1:
      guard ignoredItemsTable.selectedRow != -1 else {
        return
      }

      removeIgnoredApp(ignoredItemsTable.selectedRow)
    default:
      return
    }
  }

  @IBAction func ignoredAllAppsExceptListedChanged(_ sender: NSButton) {
    UserDefaults.standard.ignoreAllAppsExceptListed = (sender.state == .on)
  }

  private func addIgnoredApp() {
    let dialog = chooseAppDialog
    if dialog.runModal() == .OK {
      if let appUrl = dialog.url,
         let bundle = Bundle(path: appUrl.path),
         let bundleIdentifier = bundle.bundleIdentifier,
         !ignoredApps.contains(bundleIdentifier) {
        ignoredApps.append(bundleIdentifier)
        ignoredItemsTable.reloadData()
      }
    }
  }

  private func removeIgnoredApp(_ row: Int) {
    ignoredApps.remove(at: row)
    ignoredItemsTable.reloadData()
  }
}

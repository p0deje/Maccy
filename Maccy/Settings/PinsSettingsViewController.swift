import Cocoa
import Settings

class PinsSettingsViewController: NSViewController, SettingsPane {
  public let paneIdentifier = Settings.PaneIdentifier.pins
  public let paneTitle = NSLocalizedString("preferences_pins", comment: "")
  public let toolbarItemIcon = NSImage(named: .pincircle)!

  override var nibName: NSNib.Name? { "PinsSettingsViewController" }

  @objc dynamic private var context: NSManagedObjectContext!
  @IBOutlet private var itemsController: NSArrayController!
  private let fetchPinnedPredicate = NSPredicate(format: "pin != nil")

  override func viewDidLoad() {
    super.viewDidLoad()
    self.context = CoreDataManager.shared.viewContext
    itemsController.fetchPredicate = fetchPinnedPredicate
    itemsController.sortDescriptors = [HistoryItem.sortByFirstCopiedAt]
  }
}

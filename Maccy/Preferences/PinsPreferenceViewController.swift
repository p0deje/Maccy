import Cocoa
import Preferences

class PinsPreferenceViewController: NSViewController, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.pins
  public let preferencePaneTitle = NSLocalizedString("preferences_pins", comment: "")
  public let toolbarItemIcon = NSImage(named: .pincircle)!

  override var nibName: NSNib.Name? { "PinsPreferenceViewController" }

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

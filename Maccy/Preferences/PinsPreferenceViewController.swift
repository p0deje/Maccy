import Cocoa
import Preferences

class PinsPreferenceViewController: NSViewController, NSTableViewDataSource, PreferencePane {
  public let preferencePaneIdentifier = Preferences.PaneIdentifier.pins
  public let preferencePaneTitle = NSLocalizedString("preferences_pins", comment: "")
  public let toolbarItemIcon = NSImage(named: "pin.circle")!

  override var nibName: NSNib.Name? { "PinsPreferenceViewController" }

  @objc dynamic private var context: NSManagedObjectContext!
  @IBOutlet private var itemsController: NSArrayController!
  private let fetchPinnedPredicate = NSPredicate(format: "pin != nil")

  @IBOutlet weak var instructionsLabel: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()
    self.context = CoreDataManager.shared.viewContext
    itemsController.fetchPredicate = fetchPinnedPredicate
    itemsController.sortDescriptors = [HistoryItem.sortByFirstCopiedAt]
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    updateInstructionsLabel()
  }

  private func updateInstructionsLabel() {
    instructionsLabel.stringValue = String(
      format: instructionsLabel.stringValue,
      HistoryItem.availablePins.sorted().joined(separator: ", ")
    )
  }
}

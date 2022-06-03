import Cocoa
import CoreData

@objc(HistoryItem)
class HistoryItem: NSManagedObject {
  public static let availablePins = Set([
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
    "m", "n", "o", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ])
  public static let sortByFirstCopiedAt = NSSortDescriptor(key: #keyPath(HistoryItem.firstCopiedAt), ascending: false)

  public static var randomAvailablePin: String {
    let assignedPins = Set(all().compactMap({ $0.pin }))
    return availablePins.subtracting(assignedPins).randomElement() ?? ""
  }

  @NSManaged public var application: String?
  @NSManaged public var contents: NSSet?
  @NSManaged public var firstCopiedAt: Date!
  @NSManaged public var lastCopiedAt: Date!
  @NSManaged public var numberOfCopies: Int
  @NSManaged public var pin: String?
  @NSManaged public var title: String

  private let titleMaxLength = 50

  public static func all() -> [HistoryItem] {
    let fetchRequest = NSFetchRequest<HistoryItem>(entityName: "HistoryItem")
    fetchRequest.sortDescriptors = [HistoryItem.sortByFirstCopiedAt]
    do {
      return try CoreDataManager.shared.viewContext.fetch(fetchRequest)
    } catch {
      return []
    }
  }

  public static func unpinned() -> [HistoryItem] {
    all().filter({ $0.pin == nil })
  }

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.getContents().count == rhs.getContents().count && lhs.supersedes(rhs)
  }

  convenience init(contents: [HistoryItemContent], application: String? = nil) {
    let entity = NSEntityDescription.entity(forEntityName: "HistoryItem",
                                            in: CoreDataManager.shared.viewContext)!
    self.init(entity: entity, insertInto: CoreDataManager.shared.viewContext)

    self.application = application
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1
    self.title = generateTitle(contents)

    contents.forEach(addToContents(_:))
  }

  override func validateValue(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>, forKey key: String) throws {
    try super.validateValue(value, forKey: key)
    if key == "pin", let pin = value.pointee as? String {
      try validatePin(pin)
    }
  }

  @objc(addContentsObject:)
  @NSManaged public func addToContents(_ value: HistoryItemContent)

  func getContents() -> [HistoryItemContent] {
    return (contents?.allObjects as? [HistoryItemContent]) ?? []
  }

  func supersedes(_ item: HistoryItem) -> Bool {
    return item.getContents().allSatisfy({ content in
      getContents().contains(where: { $0 == content})
    })
  }

  func generateTitle(_ contents: [HistoryItemContent]) -> String {
    var title = ""

    guard !contents.contains(where: { [.png, .tiff].contains(NSPasteboard.PasteboardType($0.type)) }) else {
      return title
    }

    if let fileURLData = contents.first(where: { NSPasteboard.PasteboardType($0.type) == .fileURL })?.value {
      if let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil, isAbsolute: true) {
        title = fileURL.absoluteString.removingPercentEncoding ?? ""
      }
    } else if let stringData = contents.first(where: { NSPasteboard.PasteboardType($0.type) == .string })?.value {
      title = String(data: stringData, encoding: .utf8) ?? ""
    }

    return title
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: "⏎")
      .shortened(to: titleMaxLength)
  }

  private func validatePin(_ pin: String) throws {
    for item in HistoryItem.all() {
      if let existingPin = item.pin, existingPin == pin, item != self {
        throw NSError(
          domain: "keyUsed",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("key_used_error", comment: "")])
      }
    }
  }
}

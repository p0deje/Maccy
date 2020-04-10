import CoreData

@objc(HistoryItem)
class HistoryItem: NSManagedObject {
  @NSManaged public var contents: NSSet?
  @NSManaged public var firstCopiedAt: Date!
  @NSManaged public var lastCopiedAt: Date!
  @NSManaged public var numberOfCopies: Int
  @NSManaged public var pin: String?

  @objc(addContentsObject:)
  @NSManaged public func addToContents(_ value: HistoryItemContent)

  public static func all() -> [HistoryItem] {
    let fetchRequest = NSFetchRequest<HistoryItem>(entityName: "HistoryItem")
    let sortDescriptor = NSSortDescriptor(key: #keyPath(HistoryItem.firstCopiedAt), ascending: false)
    fetchRequest.sortDescriptors = [sortDescriptor]
    do {
      return try CoreDataManager.shared.viewContext.fetch(fetchRequest)
    } catch {
      return []
    }
  }

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    let lhsContents = lhs.getContents()
    let rhsContents = rhs.getContents()

    if lhsContents.count == rhsContents.count {
      return lhsContents.allSatisfy({ lhsContent -> Bool in
        rhsContents.contains(where: { $0 == lhsContent })
      })
    }

    return false
  }

  convenience init(contents: [HistoryItemContent]) {
    let entity = NSEntityDescription.entity(forEntityName: "HistoryItem",
                                            in: CoreDataManager.shared.viewContext)!
    self.init(entity: entity, insertInto: CoreDataManager.shared.viewContext)

    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1

    contents.forEach(addToContents(_:))
  }

  func getContents() -> [HistoryItemContent] {
    return ((contents?.allObjects ?? []) as [HistoryItemContent])
  }
}

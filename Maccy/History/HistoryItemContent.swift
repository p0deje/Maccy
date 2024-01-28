import CoreData

@objc(HistoryItemContent)
class HistoryItemContent: NSManagedObject {
  @NSManaged public var type: String!
  @NSManaged public var value: Data?
  @NSManaged public var item: HistoryItem?

  // swiftlint:disable nsobject_prefer_isequal
  // Class 'HistoryItemContent' for entity 'HistoryItemContent' has an illegal override of NSManagedObject -isEqual
  static func == (lhs: HistoryItemContent, rhs: HistoryItemContent) -> Bool {
    return (lhs.type == rhs.type) && (lhs.value == rhs.value)
  }
  // swiftlint:enable nsobject_prefer_isequal

  convenience init(type: String, value: Data?) {
    let entity = NSEntityDescription.entity(forEntityName: "HistoryItemContent",
                                            in: CoreDataManager.shared.viewContext)!
    self.init(entity: entity, insertInto: CoreDataManager.shared.viewContext)

    self.type = type
    self.value = value
  }
}

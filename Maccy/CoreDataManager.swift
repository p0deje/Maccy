import CoreData

class CoreDataManager {
  static public let shared = CoreDataManager()
  static public var inMemory = ProcessInfo.processInfo.arguments.contains("ui-testing")

  public var viewContext: NSManagedObjectContext {
    return CoreDataManager.shared.persistentContainer.viewContext
  }

  lazy private var persistentContainer: NSPersistentContainer = {
    let container = NSPersistentContainer(name: "Storage")

    if CoreDataManager.inMemory {
      let description = NSPersistentStoreDescription()
      description.type = NSInMemoryStoreType
      description.shouldAddStoreAsynchronously = false
      container.persistentStoreDescriptions = [description]
    }

    container.loadPersistentStores(completionHandler: { (_, error) in
      if let error = error as NSError? {
        print("Unresolved error \(error), \(error.userInfo)")
      }
    })
    return container
  }()

  private init() {}

  func saveContext() {
    let context = CoreDataManager.shared.viewContext
    if context.hasChanges {
      do {
        try context.save()
      } catch {
        let nserror = error as NSError
        print("Unresolved error \(nserror), \(nserror.userInfo)")
      }
    }
  }
}

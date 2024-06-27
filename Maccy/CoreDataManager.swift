import CoreData
import SwiftData

class CoreDataManager {
  static public let shared = CoreDataManager()
  static public var inMemory = ProcessInfo.processInfo.arguments.contains("ui-testing")

  public var viewContext: NSManagedObjectContext {
    return CoreDataManager.shared.persistentContainer.viewContext
  }

  lazy var persistentContainer: NSPersistentContainer = {
    let container = NSPersistentContainer(name: "Storage")

    if CoreDataManager.inMemory {
      let description = NSPersistentStoreDescription()
      description.type = NSInMemoryStoreType
      description.shouldAddStoreAsynchronously = false
      container.persistentStoreDescriptions = [description]
    } else {
      let description = NSPersistentStoreDescription()
      description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
//      description.url = description.url?.deletingLastPathComponent().appending(path: "default.store")
      description.shouldMigrateStoreAutomatically = true
      description.shouldInferMappingModelAutomatically = true
      description.url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
      container.persistentStoreDescriptions = [description]
//      if let description = container.persistentStoreDescriptions.first {
//        description.url = CoreDataManager.storeURL
//        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
//      }
    }

    // Enable persistent history tracking in anticipation for SwiftData migration.
    // https://developer.apple.com/documentation/coredata/adopting_swiftdata_for_a_core_data_app
    if let description = container.persistentStoreDescriptions.first {
      description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
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


//class SwiftDataManager {
//  static public let shared = try! SwiftDataManager()
//
//  let container: ModelContainer
//
//  init(useInMemoryStore: Bool = false) throws {
//    let storeURL = CoreDataManager.shared.persistentContainer.persistentStoreDescriptions.first!.url!
//    let config = ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite"))
//    container = try ModelContainer(for: HistoryItem.self, configurations: config)
//  }
//}

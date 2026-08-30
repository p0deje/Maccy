import Defaults
import Foundation
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")

  init() {
    var config = ModelConfiguration(url: url)

    if Defaults[.storeHistoryInMemoryOnly] {
      // Leaving a store behind would defeat the purpose of the option, and the
      // write-ahead log keeps items readable even after the history is cleared.
      Storage.removeStoreFromDisk(at: url)
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }

    #if DEBUG
    if AppDelegate.isTesting {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  func cleanupOrphanedContents() throws -> Int {
    let descriptor = FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { $0.item == nil }
    )
    let count = try context.fetchCount(descriptor)
    guard count > 0 else {
      return 0
    }

    try context.delete(
      model: HistoryItemContent.self,
      where: #Predicate { $0.item == nil }
    )
    context.processPendingChanges()
    try context.save()

    return count
  }

  private static func removeStoreFromDisk(at url: URL) {
    // SQLite keeps the write-ahead log and the shared memory file next to the
    // store, suffixed with "-wal" and "-shm". Items stay readable in the log
    // even after the history has been cleared, so those have to go as well.
    let store = url.lastPathComponent
    let directory = url.deletingLastPathComponent()
    for name in [store, "\(store)-wal", "\(store)-shm"] {
      try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
  }
}

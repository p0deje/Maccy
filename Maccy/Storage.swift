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

  // Stores leaking before #1509 can hold gigabytes of orphans and deleting
  // them in a single transaction grows the WAL to the size of the store,
  // blocking launch for minutes. Small batches keep transactions short and
  // preserve progress across force-quits, and a background context keeps
  // the main actor responsive.
  // See https://github.com/p0deje/Maccy/issues/1535.
  func cleanupOrphanedContents(batchSize: Int = 500) async throws -> Int {
    let container = self.container
    return try await Task.detached(priority: .utility) {
      let context = ModelContext(container)
      context.autosaveEnabled = false

      var deleted = 0
      while true {
        var orphans = FetchDescriptor<HistoryItemContent>(
          predicate: #Predicate { $0.item == nil }
        )
        orphans.fetchLimit = batchSize
        let batch = try context.fetch(orphans)
        if batch.isEmpty {
          break
        }

        for orphan in batch {
          context.delete(orphan)
        }
        context.processPendingChanges()
        try context.save()
        deleted += batch.count
      }

      return deleted
    }.value
  }

  // Titles stored before the sanitization in `HistoryItem.generateTitle()` may
  // contain scalars that hang CoreText on macOS 26. Such an item makes Maccy
  // spin at 100% CPU on every launch without ever drawing its window, so the
  // store has to be healed before the history is first rendered.
  // See https://github.com/p0deje/Maccy/issues/1520.
  func sanitizeTitles() throws -> Int {
    let items = try context.fetch(FetchDescriptor<HistoryItem>())
    var count = 0

    for item in items where item.title.containsScalarsUnsafeForTitleLayout {
      item.title = item.title.removingScalarsUnsafeForTitleLayout()
      count += 1
    }

    guard count > 0 else {
      return 0
    }

    context.processPendingChanges()
    try context.save()

    return count
  }
}

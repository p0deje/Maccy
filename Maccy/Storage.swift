import Foundation
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    // Large contents live in external storage next to the database.
    let externalStorage = url.deletingLastPathComponent().appending(path: ".Storage_SUPPORT")
    let externalFiles = FileManager.default.enumerator(at: externalStorage, includingPropertiesForKeys: [.fileSizeKey])?
      .allObjects as? [URL] ?? []
    let size = ([url] + externalFiles)
      .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
      .reduce(0, +)
    guard size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: Int64(size))
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

  // Reads `value` through a throwaway context, so the blob isn't kept in memory
  // by the long-lived model for the rest of the session.
  func detachedValue(of content: HistoryItemContent) -> Data? {
    let id = content.persistentModelID
    let descriptor = FetchDescriptor<HistoryItemContent>(predicate: #Predicate { $0.persistentModelID == id })
    guard !content.hasChanges, let detached = try? ModelContext(container).fetch(descriptor).first else {
      return content.value
    }

    return detached.value
  }

  // Contents stored before `value` became external storage stay inline in SQLite
  // and are loaded into memory with their rows. Re-inserting is the only way to
  // move them out. Each batch is one transaction, so an interrupted run resumes
  // where it stopped.
  func externalizeContents() throws -> Int {
    var count = 0

    while true {
      let batch: Int = try autoreleasepool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<HistoryItemContent>(
          predicate: #Predicate { $0.digest == nil && $0.value != nil }
        )
        descriptor.fetchLimit = 10

        let contents = try context.fetch(descriptor)
        for content in contents {
          guard let value = content.value else { continue }

          if let item = content.item {
            item.contents.append(HistoryItemContent(type: content.type, value: value))
            context.delete(content)
          } else {
            content.digest = HistoryItemContent.digest(value)
          }
        }
        try context.save()

        return contents.count
      }

      guard batch > 0 else {
        return count
      }
      count += batch
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

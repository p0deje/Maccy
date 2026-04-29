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
    container = Self.makeContainer(url: url)
  }

  // SwiftData has no public API to evict registered objects from a context.
  // Swapping the entire container is the only way to free hydrated relationship
  // blobs without quitting the app. Caller is responsible for ensuring no live
  // references to old managed objects exist (otherwise they keep the old
  // container alive).
  func recreateContainer() {
    try? context.save()
    container = Self.makeContainer(url: url)
  }

  private static func makeContainer(url: URL) -> ModelContainer {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      return try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }
}

// Generates `thumbnailData` for items that pre-date the migration. Runs on
// its own model context (created by `@ModelActor`) so it can hydrate items
// + their `contents` relationship in the background without bloating the
// main context that the UI uses.
//
// Items the actor processes get one of two outcomes:
//   - Image item: `thumbnailData` set to rendered JPEG bytes.
//   - Non-image item: `thumbnailData` set to empty `Data()` as a sentinel
//     so it gets filtered out of subsequent passes by the predicate, and
//     short-circuits the decoder in `HistoryItemDecorator.ensureThumbnailImage`.
@ModelActor
actor ThumbnailBackfiller {
  func backfillBatch(limit: Int = 10) async -> Int {
    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.thumbnailData == nil }
    )
    descriptor.fetchLimit = limit

    guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else {
      return 0
    }

    var processed = 0
    for item in items {
      if let data = item.imageData,
         let bytes = HistoryItem.makeThumbnailData(from: data) {
        item.thumbnailData = bytes
      } else {
        item.thumbnailData = Data()
      }
      processed += 1
    }

    try? modelContext.save()
    return processed
  }
}

// Fetches the full sorted history for search on a private SwiftData context.
// The UI resolves the returned ids on the main context in small batches, which
// avoids the long synchronous main-context fetch that stalls scrolling.
@ModelActor
actor SearchHistoryLoader {
  func sortedItemIDs(sortBy: Sorter.By, pinTo: PinsPosition) async -> [PersistentIdentifier] {
    let pinnedIDs = fetchIDs(
      predicate: #Predicate<HistoryItem> { $0.pin != nil },
      sortBy: sortDescriptors(sortBy)
    )
    let unpinnedIDs = fetchIDs(
      predicate: #Predicate<HistoryItem> { $0.pin == nil },
      sortBy: sortDescriptors(sortBy)
    )

    if pinTo == .bottom {
      return unpinnedIDs + pinnedIDs
    } else {
      return pinnedIDs + unpinnedIDs
    }
  }

  private func fetchIDs(
    predicate: Predicate<HistoryItem>,
    sortBy: [SortDescriptor<HistoryItem>]
  ) -> [PersistentIdentifier] {
    let descriptor = FetchDescriptor<HistoryItem>(
      predicate: predicate,
      sortBy: sortBy
    )
    let items = (try? modelContext.fetch(descriptor)) ?? []
    return items.map(\.persistentModelID)
  }

  private func sortDescriptors(_ sortBy: Sorter.By) -> [SortDescriptor<HistoryItem>] {
    switch sortBy {
    case .firstCopiedAt:
      return [SortDescriptor(\.firstCopiedAt, order: .reverse)]
    case .numberOfCopies:
      return [SortDescriptor(\.numberOfCopies, order: .reverse)]
    default:
      return [SortDescriptor(\.lastCopiedAt, order: .reverse)]
    }
  }
}

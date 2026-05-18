import Foundation
import Logging
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  private let logger = Logger(label: "org.p0deje.Maccy.Storage")

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
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try Self.makeContainer(configuration: config)
    } catch let error {
      logger.error("Failed to open store, recreating: \(error.localizedDescription)")
      Self.removeStoreFiles(at: url)
      do {
        container = try Self.makeContainer(configuration: config)
      } catch let retryError {
        fatalError("Cannot load database: \(retryError.localizedDescription).")
      }
    }
  }

  private static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
    // Register root models only; related models are pulled in via @Relationship.
    try ModelContainer(
      for: HistoryItem.self, TodoItem.self,
      configurations: configuration
    )
  }

  private static func removeStoreFiles(at url: URL) {
    let fileManager = FileManager.default
    let paths = [url, URL(fileURLWithPath: url.path + "-shm"), URL(fileURLWithPath: url.path + "-wal")]
    for path in paths where fileManager.fileExists(atPath: path.path) {
      try? fileManager.removeItem(at: path)
    }
  }
}

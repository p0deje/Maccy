import Foundation
import Logging
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  let logger = Logger(label: "org.p0deje.Maccy.Storage")

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
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch {
      logger.error("Database corrupted, recreating: \(error.localizedDescription)")
      // Remove corrupt database files and retry
      let sqliteFiles = [url, url.appendingPathExtension("shm"), url.appendingPathExtension("wal")]
      for file in sqliteFiles {
        try? FileManager.default.removeItem(at: file)
      }
      do {
        container = try ModelContainer(for: HistoryItem.self, configurations: config)
      } catch let retryError {
        fatalError("Cannot create database even after reset: \(retryError.localizedDescription)")
      }
    }
  }
}

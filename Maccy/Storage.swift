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
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch {
      // Recovery path: keep a backup of the broken store and recreate a fresh one.
      try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: url.path()) {
        let backupURL = url.deletingPathExtension()
          .appendingPathExtension("broken-\(Int(Date.now.timeIntervalSince1970)).sqlite")
        try? FileManager.default.moveItem(at: url, to: backupURL)
      }

      do {
        container = try ModelContainer(for: HistoryItem.self, configurations: config)
      } catch {
        assertionFailure("Cannot load database: \(error.localizedDescription). Falling back to in-memory store.")
        do {
          // Last resort so that app can still launch and users can export data manually.
          container = try ModelContainer(
            for: HistoryItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
          )
        } catch {
          fatalError("Cannot initialize in-memory database: \(error.localizedDescription).")
        }
      }
    }
  }
}

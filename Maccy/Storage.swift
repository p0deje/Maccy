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
      container = try ModelContainer(
        for: Schema(versionedSchema: StorageSchemaV2.self),
        migrationPlan: StorageMigrationPlan.self,
        configurations: config
      )
    } catch {
      print("Migration failed: \(error). Attempting recovery by recreating store.")
      try? FileManager.default.removeItem(at: url)
      for suffix in ["-wal", "-shm"] {
        let sidecar = url.deletingPathExtension()
          .appendingPathExtension(url.pathExtension + suffix)
        try? FileManager.default.removeItem(at: sidecar)
      }
      do {
        container = try ModelContainer(
          for: Schema(versionedSchema: StorageSchemaV2.self),
          migrationPlan: StorageMigrationPlan.self,
          configurations: config
        )
      } catch {
        fatalError("Cannot load database after recovery: \(error.localizedDescription).")
      }
    }
  }
}

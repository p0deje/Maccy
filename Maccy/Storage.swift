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

  #if os(macOS)
  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  #else
  private let url: URL = {
    // iOS uses app's documents directory within app group for sharing with potential widgets
    if let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.org.p0deje.Maccy"
    ) {
      return containerURL.appending(path: "Storage.sqlite")
    }
    return URL.documentsDirectory.appending(path: "Storage.sqlite")
  }()
  #endif

  init() {
    let config: ModelConfiguration

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    } else {
      config = createConfiguration()
    }
    #else
    config = createConfiguration()
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  private func createConfiguration() -> ModelConfiguration {
    // Enable CloudKit sync when user has opted in
    if Defaults[.iCloudSync] {
      return ModelConfiguration(
        url: url,
        cloudKitDatabase: .private("iCloud.org.p0deje.Maccy")
      )
    } else {
      return ModelConfiguration(url: url)
    }
  }
}

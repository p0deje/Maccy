import AppKit
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

  private static let defaultURL = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  private let url: URL

  init(
    url: URL = Storage.defaultURL,
    storedInMemoryForTesting: Bool = CommandLine.arguments.contains("enable-testing"),
    corruptionStamp: () -> String = { Storage.defaultCorruptionStamp() },
    onCorruption: ((URL) -> Void)? = nil
  ) {
    self.url = url
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if storedInMemoryForTesting {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      container = Self.recoverContainer(
        from: url,
        originalError: error,
        corruptionStamp: corruptionStamp(),
        onCorruption: onCorruption
      )
    }
  }

  private static func recoverContainer(
    from url: URL,
    originalError: Error,
    corruptionStamp: String,
    onCorruption: ((URL) -> Void)?
  ) -> ModelContainer {
    let quarantineURL: URL?
    do {
      quarantineURL = try quarantineStoreFiles(for: url, stamp: corruptionStamp)
    } catch {
      quarantineURL = nil
    }

    if let quarantineURL {
      do {
        let container = try ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(url: url))
        if let onCorruption {
          onCorruption(quarantineURL)
        } else {
          showRecoveryAlert(originalError: originalError, quarantineURL: quarantineURL, usesInMemoryStore: false)
        }
        return container
      } catch {
        showRecoveryAlert(originalError: originalError, quarantineURL: quarantineURL, usesInMemoryStore: true)
      }
    } else {
      showRecoveryAlert(originalError: originalError, quarantineURL: nil, usesInMemoryStore: true)
    }

    if let container = try? ModelContainer(
      for: HistoryItem.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
      return container
    }

    preconditionFailure("Cannot load persistent or in-memory database.")
  }

  private static func showRecoveryAlert(
    originalError: Error,
    quarantineURL: URL?,
    usesInMemoryStore: Bool
  ) {
    let alert = NSAlert()
    alert.messageText = "Maccy could not load clipboard history."
    if let quarantineURL {
      let storeDescription = usesInMemoryStore ? "temporary in-memory history" : "a new empty history store"
      alert.informativeText = """
      Maccy moved the existing history store to \(quarantineURL.path) and started with \(storeDescription). Original error: \(originalError.localizedDescription)
      """
    } else {
      alert.informativeText = """
      Maccy could not move the existing history store and started with temporary in-memory history. Original error: \(originalError.localizedDescription)
      """
    }
    alert.alertStyle = .warning
    alert.runModal()
  }

  nonisolated static func quarantineStoreFiles(for url: URL, stamp: String) throws -> URL {
    let fileManager = FileManager.default
    let quarantineURL = url
      .deletingLastPathComponent()
      .appending(path: "\(url.lastPathComponent).corrupted-\(stamp)", directoryHint: .isDirectory)

    try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
    for file in storeFiles(for: url) where fileManager.fileExists(atPath: file.path) {
      try fileManager.moveItem(at: file, to: quarantineURL.appending(path: file.lastPathComponent))
    }
    return quarantineURL
  }

  private nonisolated static func storeFiles(for url: URL) -> [URL] {
    [
      url,
      URL(fileURLWithPath: "\(url.path)-shm"),
      URL(fileURLWithPath: "\(url.path)-wal")
    ]
  }

  private nonisolated static func defaultCorruptionStamp() -> String {
    String(Int(Date().timeIntervalSince1970))
  }
}

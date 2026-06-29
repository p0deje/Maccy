import AppKit
import Foundation
import SwiftData

/// Owns the SwiftData model container for clipboard history and provides
/// corruption recovery.
@MainActor
class Storage {
  /// Shared storage instance.
  static let shared = Storage()

  /// The SwiftData container holding `HistoryItem`.
  var container: ModelContainer
  /// The main-context model context used for all main-actor reads/writes.
  var context: ModelContext { container.mainContext }
  /// Human-readable on-disk size of the store, or empty when unavailable.
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  /// Default on-disk URL for the SQLite store.
  nonisolated private static let defaultURL = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  private let url: URL

  /// Creates the container, falling back to an in-memory store under testing
  /// or to a recovered container when the on-disk store is corrupt.
  ///
  /// - Parameters:
  ///   - url: Store URL. Defaults to `defaultURL`.
  ///   - storedInMemoryForTesting: Force an in-memory store (overridden by the
  ///     `enable-testing` launch argument).
  ///   - corruptionStamp: Stamp appended to the quarantined directory name.
  ///   - onCorruption: Optional callback invoked with the quarantine URL when
  ///     the store is moved aside due to corruption. When `nil`, a modal alert
  ///     is shown instead.
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

  /// Recovers from a corrupt store by quarantining its files and recreating an
  /// empty store, falling back to an in-memory store if recovery also fails.
  ///
  /// - Parameters:
  ///   - from url: The store URL whose container failed to open.
  ///   - originalError: The error that triggered recovery.
  ///   - corruptionStamp: Stamp appended to the quarantined directory name.
  ///   - onCorruption: Optional callback invoked with the quarantine URL.
  /// - Returns: A fresh container over the (now-empty) store, or an in-memory
  ///   container when on-disk recovery fails.
  static func recoverContainer(
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

  /// Shows the modal alert presented when a store is quarantined or recovery
  /// falls back to an in-memory store.
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
      Maccy moved the existing history store to \(quarantineURL.path) and started with \(storeDescription).
      Original error: \(originalError.localizedDescription)
      """
    } else {
      alert.informativeText = """
      Maccy could not move the existing history store and started with temporary in-memory history.
      Original error: \(originalError.localizedDescription)
      """
    }
    alert.alertStyle = .warning
    alert.runModal()
  }

  /// Moves the store and its sidecar files (`-shm`, `-wal`) into a timestamped
  /// sibling directory so a fresh store can be created in place.
  ///
  /// - Parameters:
  ///   - for url: The store URL whose files should be moved.
  ///   - stamp: Stamp appended to the quarantine directory name.
  /// - Returns: The quarantine directory URL.
  /// - Throws: Any filesystem error encountered while moving files.
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

  /// Returns the store URL plus its `-shm` and `-wal` sidecar URLs.
  private nonisolated static func storeFiles(for url: URL) -> [URL] {
    [
      url,
      URL(fileURLWithPath: "\(url.path)-shm"),
      URL(fileURLWithPath: "\(url.path)-wal")
    ]
  }

  /// Returns a Unix-timestamp string used to name quarantine directories.
  private nonisolated static func defaultCorruptionStamp() -> String {
    String(Int(Date().timeIntervalSince1970))
  }
}

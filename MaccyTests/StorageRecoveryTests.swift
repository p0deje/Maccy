import XCTest
@testable import Maccy

class StorageRecoveryTests: XCTestCase {
  @MainActor
  func testStorageRecoveryMovesCorruptedStoreAndReportsQuarantine() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let storeURL = directory.appending(path: "Storage.sqlite")
    try Data("not a sqlite database".utf8).write(to: storeURL)

    var reportedQuarantineURL: URL?
    let container = Storage.recoverContainer(
      from: storeURL,
      originalError: CocoaError(.persistentStoreIncompatibleVersionHash),
      corruptionStamp: "fixed-stamp",
      onCorruption: { reportedQuarantineURL = $0 }
    )
    _ = container.mainContext

    let quarantineURL = try XCTUnwrap(reportedQuarantineURL)
    XCTAssertEqual(
      try String(contentsOf: quarantineURL.appending(path: "Storage.sqlite"), encoding: .utf8),
      "not a sqlite database"
    )
    if FileManager.default.fileExists(atPath: storeURL.path) {
      XCTAssertNotEqual(try Data(contentsOf: storeURL), Data("not a sqlite database".utf8))
    }
  }

  func testQuarantineStoreFilesMovesExistingStoreFiles() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let storeURL = directory.appending(path: "Storage.sqlite")
    let shmURL = URL(fileURLWithPath: "\(storeURL.path)-shm")
    let walURL = URL(fileURLWithPath: "\(storeURL.path)-wal")
    try Data("sqlite".utf8).write(to: storeURL)
    try Data("shm".utf8).write(to: shmURL)
    try Data("wal".utf8).write(to: walURL)

    let quarantineURL = try Storage.quarantineStoreFiles(for: storeURL, stamp: "fixed-stamp")

    XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
    XCTAssertEqual(
      try String(contentsOf: quarantineURL.appending(path: "Storage.sqlite"), encoding: .utf8),
      "sqlite"
    )
    XCTAssertEqual(
      try String(contentsOf: quarantineURL.appending(path: "Storage.sqlite-shm"), encoding: .utf8),
      "shm"
    )
    XCTAssertEqual(
      try String(contentsOf: quarantineURL.appending(path: "Storage.sqlite-wal"), encoding: .utf8),
      "wal"
    )
  }
}

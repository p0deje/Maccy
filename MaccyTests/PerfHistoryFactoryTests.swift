import Defaults
import XCTest
@testable import Maccy

/// Correctness tests for the scenario-history factory. These run in the unit
/// shard (they are not perf benchmarks). Sets `Defaults[.size]` high so the
/// requested counts are not trimmed, independent of other tests' state.
@MainActor
final class PerfHistoryFactoryTests: XCTestCase {
  private let savedSize = Defaults[.size]

  override func setUp() async throws {
    try await super.setUp()
    History.shared.clearAll()
    Defaults[.size] = 200
  }

  override func tearDown() async throws {
    History.shared.clearAll()
    Defaults[.size] = savedSize
    try await super.tearDown()
  }

  /// `makeImages` populates the requested number of image items.
  func testMakeImagesBuildsRequestedCount() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "PHFImg-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }

    let history = try PerfHistoryFactory.makeImages(count: 3, bucket: .halfMB, cacheDir: cacheDir)

    XCTAssertEqual(history.all.count, 3)
  }

  /// `makeTexts` populates the requested number of text items.
  func testMakeTextsBuildsRequestedCount() throws {
    let history = try PerfHistoryFactory.makeTexts(count: 2, long: true)

    XCTAssertEqual(history.all.count, 2)
  }

  /// `makeMixed` populates the sum of image and text items.
  func testMakeMixedBuildsRequestedCount() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "PHFMix-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }

    let history = try PerfHistoryFactory.makeMixed(images: 2, texts: 3, bucket: .halfMB, cacheDir: cacheDir)

    XCTAssertEqual(history.all.count, 5)
  }
}

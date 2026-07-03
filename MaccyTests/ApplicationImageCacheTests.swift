import SwiftData
import XCTest
@testable import Maccy

/// Regression tests for `ApplicationImageCache` — the `NSCache`-bounded,
/// bundle-id-keyed cache of source-application icons.
///
/// `NSCache` exposes no count accessor, so the `countLimit = 128` eviction is
/// left to the OS (it evicts under memory pressure); these tests lock the
/// testable contract instead — fallback sharing, instance reuse, and that
/// `purge()` forces a fresh `ApplicationImage` on the next lookup.
@MainActor
final class ApplicationImageCacheTests: XCTestCase {
  /// Builds a transient `HistoryItem` carrying only the source-application id
  /// that `getImage(item:)` keys on.
  private func item(application: String?) -> HistoryItem {
    let historyItem = HistoryItem(contents: [])
    historyItem.application = application
    return historyItem
  }

  /// Items with no source application share the single fallback instance.
  func testNilApplicationReturnsSharedFallback() {
    let cache = ApplicationImageCache.shared
    let first = cache.getImage(item: item(application: nil))
    let second = cache.getImage(item: item(application: nil))
    XCTAssertTrue(first === second, "Nil-application items must share the fallback instance.")
  }

  /// A known bundle id is cached: the second lookup returns the same instance.
  func testKnownApplicationIsCachedAndReused() {
    let cache = ApplicationImageCache.shared
    cache.purge()
    let bundle = "org.maccy.test.cached-app"
    let first = cache.getImage(item: item(application: bundle))
    let second = cache.getImage(item: item(application: bundle))
    XCTAssertTrue(first === second, "A second lookup for the same bundle id must hit the cache.")
  }

  /// `purge()` empties the cache, so the next lookup recreates the image.
  func testPurgeForcesRecreation() {
    let cache = ApplicationImageCache.shared
    cache.purge()
    let bundle = "org.maccy.test.purge-app"
    let before = cache.getImage(item: item(application: bundle))
    cache.purge()
    let after = cache.getImage(item: item(application: bundle))
    XCTAssertFalse(before === after, "After purge the image must be recreated.")
  }
}

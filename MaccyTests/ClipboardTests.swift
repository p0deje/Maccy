import XCTest
import Defaults
@testable import Maccy

// Clipboard is main-actor-bound (every mutator and `checkForChangesInPasteboard`
// is `@MainActor`), so the whole test class runs on the main actor. The old
// `onNewCopy` hook flow is gone (BS-2.4); these tests now drive the pasteboard,
// call `checkForChangesInPasteboard()`, and assert on an `IngestorSpy` injected
// via `clipboard.ingestor`. Pure filtering / ignore-rule coverage lives in
// `IngestFilterTests` and `BackgroundClipboardIngestorTests` (the actor's
// `filterContents` is the authoritative filter); what remains here is
// clipboard-specific: changeCount detection, the `ignoreEvents` /
// `ignoreOnlyNextEvent` gates, the paste-stack interrupt, and the shape of the
// `IngestRequest` `Clipboard` builds (contents non-empty, application carried
// through).
@MainActor
final class ClipboardTests: XCTestCase {
  let clipboard = Clipboard.shared
  let pasteboard = NSPasteboard.general

  let fileURLType = NSPasteboard.PasteboardType.fileURL
  let stringType = NSPasteboard.PasteboardType.string
  let tiffType = NSPasteboard.PasteboardType.tiff

  let savedEnabledTypes = Defaults[.enabledPasteboardTypes]
  let savedIgnoreEvents = Defaults[.ignoreEvents]
  let savedIgnoreAllAppsExceptListed = Defaults[.ignoreAllAppsExceptListed]
  let savedIgnoredApps = Defaults[.ignoredApps]
  let savedIgnoredPasteboardTypes = Defaults[.ignoredPasteboardTypes]
  let savedMaxClipboardContentSize = Defaults[.maxClipboardContentSize]

  private var savedIngestor: ClipboardIngestor?

  override func setUp() async throws {
    try await super.setUp()
    Defaults[.enabledPasteboardTypes] = Set(StorageType.all.types)
    Defaults[.maxClipboardContentSize] = 10
    Defaults[.ignoreAllAppsExceptListed] = false
    Defaults[.ignoreEvents] = false
    // Preserve whatever ingestor AppDelegate (or a prior test) wired so teardown
    // can restore it — tests in this class inject their own spy.
    savedIngestor = clipboard.ingestor
    // Drain fire-and-forget Tasks left by a prior test — notably copy()'s
    // `Task { checkForChangesInPasteboard() }`, which reads `self.ingestor` at
    // execution time. Running them here (while ingestor is the restored
    // savedIngestor — nil in tests) prevents a delayed dispatch from leaking
    // into this test's spy.
    try? await Task.sleep(nanoseconds: 100_000_000)
  }

  override func tearDown() async throws {
    try await super.tearDown()
    Defaults[.enabledPasteboardTypes] = savedEnabledTypes
    Defaults[.ignoreEvents] = savedIgnoreEvents
    Defaults[.ignoreOnlyNextEvent] = false
    Defaults[.ignoreAllAppsExceptListed] = savedIgnoreAllAppsExceptListed
    Defaults[.ignoredApps] = savedIgnoredApps
    Defaults[.ignoredPasteboardTypes] = savedIgnoredPasteboardTypes
    Defaults[.maxClipboardContentSize] = savedMaxClipboardContentSize
    clipboard.ingestor = savedIngestor
  }

  // MARK: - changeCount detection + dispatch shape

  func testChangeDispatchesIngestRequestToIngestor() async {
    let spy = IngestorSpy()
    clipboard.ingestor = spy

    setPasteboard(types: [.string], string: "bar", forType: .string)

    clipboard.checkForChangesInPasteboard()
    await waitForSpy(spy, expectedRequestCount: 1)

    let requests = await spy.requests
    XCTAssertEqual(requests.count, 1)
    // The request carries the raw, unfiltered pasteboard contents — at least
    // the string type we put on the pasteboard. Type filtering is the actor's
    // job (`filterContents`), so Clipboard records exactly what was there.
    XCTAssertTrue(requests.first?.contents.contains { $0.type == stringType.rawValue } == true)
  }

  func testNoChangeDoesNotDispatch() async {
    let spy = IngestorSpy()
    clipboard.ingestor = spy

    // Sync clipboard.changeCount first so the guard short-circuits.
    clipboard.changeCount = pasteboard.changeCount
    clipboard.checkForChangesInPasteboard()
    // Yield once so any (there should be none) dispatched Task would land.
    await Task.yield()

    let requests = await spy.requests
    XCTAssertEqual(requests.count, 0)
  }

  func testNilIngestorIsNoOp() async {
    // No ingestor wired — legacy/unwired caller. The gates run but the dispatch
    // must not crash and must not block.
    clipboard.ingestor = nil
    setPasteboard(types: [.string], string: "bar", forType: .string)
    clipboard.checkForChangesInPasteboard()
    await Task.yield()
  }

  func testRequestCarriesSourceApplication() async {
    let spy = IngestorSpy()
    clipboard.ingestor = spy

    setPasteboard(types: [.string], string: "bar", forType: .string)
    clipboard.checkForChangesInPasteboard()
    await waitForSpy(spy, expectedRequestCount: 1)

    let request = await spy.requests.first
    // In the test host the frontmost app is the test runner; whatever it is,
    // Clipboard forwards `sourceApp?.bundleIdentifier` verbatim (the actor
    // applies the ignored-apps filter, not Clipboard).
    XCTAssertEqual(request?.application, NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
  }

  func testRequestCarriesPasteboardChangeCount() async {
    let spy = IngestorSpy()
    clipboard.ingestor = spy

    setPasteboard(types: [.string], string: "bar", forType: .string)
    let expectedChangeCount = pasteboard.changeCount
    clipboard.checkForChangesInPasteboard()
    await waitForSpy(spy, expectedRequestCount: 1)

    let request = await spy.requests.first
    XCTAssertEqual(request?.source.changeCount, expectedChangeCount)
  }

  // MARK: - ignoreEvents / ignoreOnlyNextEvent gating

  func testIgnoreEventsSkipsDispatch() async {
    Defaults[.ignoreEvents] = true

    let spy = IngestorSpy()
    clipboard.ingestor = spy

    setPasteboard(types: [.string], string: "foo", forType: .string)
    clipboard.checkForChangesInPasteboard()
    await Task.yield()

    let requests = await spy.requests
    XCTAssertEqual(requests.count, 0)
    // `ignoreEvents` alone is sticky — it stays on.
    XCTAssertTrue(Defaults[.ignoreEvents])
  }

  func testIgnoreOnlyNextEventClearsFlagAndSkipsDispatch() async {
    Defaults[.ignoreEvents] = true
    Defaults[.ignoreOnlyNextEvent] = true

    let spy = IngestorSpy()
    clipboard.ingestor = spy

    setPasteboard(types: [.string], string: "foo", forType: .string)
    clipboard.checkForChangesInPasteboard()
    await Task.yield()

    let requests = await spy.requests
    XCTAssertEqual(requests.count, 0)
    XCTAssertFalse(Defaults[.ignoreEvents])
    XCTAssertFalse(Defaults[.ignoreOnlyNextEvent])
  }

  // MARK: - copy(_:) (unchanged runtime path; just needs a no-op ingestor)

  func testCopy() {
    let image = NSImage(named: "NSInfo")!
    let imageData = image.tiffRepresentation!
    let fileURL = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    // `copy(_:)` internally calls `checkForChangesInPasteboard`; leave ingestor
    // nil so that dispatch is a no-op (we assert pasteboard state, not ingest).
    clipboard.ingestor = nil

    let contents = [
      HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
      HistoryItemContent(type: tiffType.rawValue, value: imageData),
      HistoryItemContent(type: fileURLType.rawValue, value: fileURL.dataRepresentation)
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.application = "com.foo.bar"
    clipboard.copy(item)
    XCTAssertEqual(pasteboard.string(forType: .string), "foo")
    XCTAssertEqual(pasteboard.data(forType: .tiff), imageData)
    XCTAssertEqual(pasteboard.string(forType: .fileURL), fileURL.absoluteString)
    XCTAssertEqual(pasteboard.string(forType: .fromMaccy), "")
    XCTAssertEqual(pasteboard.string(forType: .source), "com.foo.bar")
  }

  func testCopyWithoutFormatting() {
    let coloredString = NSAttributedString(string: "foo",
                                           attributes: [.foregroundColor: NSColor.red])
    let fileURL = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let rtfType = NSPasteboard.PasteboardType.rtf
    clipboard.ingestor = nil

    let contents = [
      HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
      HistoryItemContent(type: fileURLType.rawValue, value: fileURL.dataRepresentation),
      HistoryItemContent(type: rtfType.rawValue,
                         value: coloredString.rtf(from: NSRange(location: 0, length: coloredString.length),
                                                  documentAttributes: [:]))
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.application = "com.foo.bar"
    clipboard.copy(item, removeFormatting: true)
    XCTAssertEqual(pasteboard.string(forType: .string), "foo")
    XCTAssertEqual(pasteboard.string(forType: .fromMaccy), "")
    XCTAssertEqual(pasteboard.string(forType: .source), "com.foo.bar")
    XCTAssertEqual(pasteboard.string(forType: .fileURL), fileURL.absoluteString)
    XCTAssertNil(pasteboard.data(forType: .rtf))
  }

  // MARK: - helpers

  /// Drives the pasteboard the way the old tests did: declare types, set the
  /// string payload, then bump `changeCount` so `checkForChangesInPasteboard`'s
  /// guard sees a change. `declareTypes` already bumps `changeCount`, but the
  /// shared `NSPasteboard.general` can be touched by other system code between
  /// setup and the call, so we sync `clipboard.changeCount` to *one less* than
  /// the current value to force the guard through.
  private func setPasteboard(types: [NSPasteboard.PasteboardType],
                             string: String,
                             forType type: NSPasteboard.PasteboardType) {
    pasteboard.declareTypes(types, owner: nil)
    pasteboard.setString(string, forType: type)
    // Force the change-detection guard to fire by lagging clipboard's counter.
    clipboard.changeCount = pasteboard.changeCount - 1
  }

  /// `checkForChangesInPasteboard` dispatches via `Task { await ingestor?.ingest }`,
  /// so the spy's `requests` won't be populated synchronously. Poll for up to
  /// ~1s (the spy is an `actor`, so each access is `await`ed).
  private func waitForSpy(_ spy: IngestorSpy, expectedRequestCount: Int) async {
    for _ in 0..<100 {
      let count = await spy.requests.count
      if count >= expectedRequestCount {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func temporaryFileURL() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("txt")
    let contents = Data("Maccy clipboard test".utf8)
    XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: contents))
    return url
  }
}

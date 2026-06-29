import XCTest
@testable import Maccy

/// Tests for the test-support doubles and fixtures: `PasteboardSimulator`,
/// `HistoryBuilder`, `FakeClock`, `IngestorSpy`, and the pasteboard source
/// adapters used by the ingest tests.
@MainActor
class SupportTests: XCTestCase {
  /// `PasteboardSimulator.copy` increments the change count and records items.
  func testPasteboardSimulatorTracksChangeCountAndItems() {
    var simulator = PasteboardSimulator()
    let item = PasteboardItemSnapshot(contents: [
      "public.utf8-plain-text": Data("hello".utf8)
    ])

    simulator.copy([item])

    XCTAssertEqual(simulator.changeCount, 1)
    XCTAssertEqual(simulator.items.first?.data(for: .string), Data("hello".utf8))
  }

  /// `HistoryBuilder` applies every configured field to the built item.
  func testHistoryBuilderBuildsConfiguredItem() {
    let item = HistoryBuilder()
      .withContent(type: "public.utf8-plain-text", value: Data("hello".utf8))
      .withApplication("org.example.App")
      .withNumberOfCopies(3)
      .withPin("a")
      .build()

    XCTAssertEqual(item.application, "org.example.App")
    XCTAssertEqual(item.numberOfCopies, 3)
    XCTAssertEqual(item.pin, "a")
    XCTAssertEqual(item.title, "hello")
  }

  /// `FakeClock.advance` moves the `nowProvider` forward by the given interval.
  func testFakeClockAdvancesNowProvider() {
    var clock = FakeClock(now: Date(timeIntervalSince1970: 10))

    clock.advance(by: 5)

    XCTAssertEqual(clock.nowProvider(), Date(timeIntervalSince1970: 15))
  }

  /// `IngestorSpy` records each ingested request and returns a neutral result.
  func testIngestorSpyRecordsRequests() async {
    let spy = IngestorSpy()
    let request = IngestRequest(
      source: CopyOrigin(changeCount: 1),
      contents: [],
      application: nil,
      now: Date(timeIntervalSince1970: 0)
    )

    let result = await spy.ingest(request)
    let requests = await spy.requests

    XCTAssertEqual(result, IngestResult(event: nil, metrics: .zero))
    XCTAssertEqual(requests, [request])
  }

  /// A `PasteboardItemSnapshot` exposes its content types and round-trips data
  /// lookups, returning nil for absent types.
  func testPasteboardItemSnapshotRoundTripsContents() {
    let snapshot = PasteboardItemSnapshot(contents: [
      "public.utf8-plain-text": Data("hi".utf8)
    ])

    XCTAssertTrue(snapshot.types.contains(.string))
    XCTAssertEqual(snapshot.data(for: .string), Data("hi".utf8))
    XCTAssertNil(snapshot.data(for: NSPasteboard.PasteboardType(rawValue: "public.not-present")))
  }

  /// `PasteboardSimulator` is readable as a `PasteboardSource` while mutation
  /// stays on the concrete value type.
  func testPasteboardSimulatorConformsToPasteboardSource() {
    let snapshot = PasteboardItemSnapshot(contents: [
      "public.utf8-plain-text": Data("hello".utf8)
    ])
    var simulator = PasteboardSimulator()

    // The protocol read-API is reachable through the existential…
    let asSource: PasteboardSource = simulator
    XCTAssertEqual(asSource.changeCount, 0)
    XCTAssertTrue(asSource.snapshot().isEmpty)

    // …while mutation stays on the concrete value type.
    simulator.copy([snapshot])

    let updated: PasteboardSource = simulator
    XCTAssertEqual(updated.changeCount, 1)
    XCTAssertEqual(
      updated.snapshot().first?.data(for: .string),
      Data("hello".utf8)
    )
  }

  /// `NSPasteboardSource` wraps the pasteboard it is given and reflects its live
  /// change count.
  ///
  /// A real `NSPasteboard` is not easily driven end-to-end in CI without a live
  /// macOS session posting copy events, so this test asserts only the minimal
  /// wrapping contract; the snapshot read-path is exercised via
  /// `PasteboardSimulator` in the ingestor tests.
  func testNSPasteboardSourceWrapsGivenPasteboard() {
    let pasteboard = NSPasteboard(name: .init("MaccyPasteboardSourceTest"))
    pasteboard.clearContents()
    let initialChangeCount = pasteboard.changeCount

    let source = NSPasteboardSource(pasteboard: pasteboard)

    XCTAssertEqual(source.changeCount, initialChangeCount)
    XCTAssertTrue(source.snapshot().isEmpty)

    pasteboard.clearContents()

    XCTAssertEqual(source.changeCount, pasteboard.changeCount)
  }

  /// `CopyOrigin` is stable across the two-argument and three-argument
  /// initializers, preserving the change count and optional name.
  func testCopyOriginConstructsIdenticallyAfterRename() {
    XCTAssertEqual(CopyOrigin(changeCount: 5, name: nil), CopyOrigin(changeCount: 5))
    XCTAssertEqual(CopyOrigin(changeCount: 5, name: "Safari").name, "Safari")
  }
}

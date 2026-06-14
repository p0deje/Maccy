import XCTest
@testable import Maccy

@MainActor
class SupportTests: XCTestCase {
  func testPasteboardSimulatorTracksChangeCountAndItems() {
    var simulator = PasteboardSimulator()
    let item = PasteboardItemSnapshot(contents: [
      "public.utf8-plain-text": Data("hello".utf8)
    ])

    simulator.copy([item])

    XCTAssertEqual(simulator.changeCount, 1)
    XCTAssertEqual(simulator.items.first?.data(for: .string), Data("hello".utf8))
  }

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

  func testFakeClockAdvancesNowProvider() {
    var clock = FakeClock(now: Date(timeIntervalSince1970: 10))

    clock.advance(by: 5)

    XCTAssertEqual(clock.nowProvider(), Date(timeIntervalSince1970: 15))
  }

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

  func testPasteboardItemSnapshotRoundTripsContents() {
    let snapshot = PasteboardItemSnapshot(contents: [
      "public.utf8-plain-text": Data("hi".utf8)
    ])

    XCTAssertTrue(snapshot.types.contains(.string))
    XCTAssertEqual(snapshot.data(for: .string), Data("hi".utf8))
    XCTAssertNil(snapshot.data(for: NSPasteboard.PasteboardType(rawValue: "public.not-present")))
  }

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

  // A live NSPasteboard isn't easily unit-testable end-to-end in CI without a real
  // macOS session driving copy events, so here we only assert the minimal contract:
  // NSPasteboardSource wraps the pasteboard it is given and reads changeCount through.
  // The ingestor tests exercise the snapshot path via PasteboardSimulator, which is
  // why that path is covered thoroughly above.
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

  func testCopyOriginConstructsIdenticallyAfterRename() {
    XCTAssertEqual(CopyOrigin(changeCount: 5, name: nil), CopyOrigin(changeCount: 5))
    XCTAssertEqual(CopyOrigin(changeCount: 5, name: "Safari").name, "Safari")
  }
}

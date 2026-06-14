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
      source: PasteboardSource(changeCount: 1),
      contents: [],
      application: nil,
      now: Date(timeIntervalSince1970: 0)
    )

    let result = await spy.ingest(request)
    let requests = await spy.requests

    XCTAssertEqual(result, IngestResult(event: nil, metrics: .zero))
    XCTAssertEqual(requests, [request])
  }
}

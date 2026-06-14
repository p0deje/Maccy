import XCTest
@testable import Maccy

@MainActor
class ClipboardIngestorTests: XCTestCase {
  func testMainActorAdapterBuildsHistoryItemFromRequest() {
    let now = Date(timeIntervalSince1970: 1_717_171_717)
    let request = IngestRequest(
      source: PasteboardSource(changeCount: 7, name: "test"),
      contents: [
        ContentDTO(
          type: "public.utf8-plain-text",
          value: "Copied text".data(using: .utf8),
          fingerprint: nil,
          size: 11
        )
      ],
      application: "org.example.App",
      now: now
    )

    let item = MainActorIngestorAdapter.historyItem(from: request)

    XCTAssertEqual(item.contents.map(\.type), ["public.utf8-plain-text"])
    XCTAssertEqual(item.contents.first?.value, "Copied text".data(using: .utf8))
    XCTAssertEqual(item.application, "org.example.App")
    XCTAssertEqual(item.firstCopiedAt, now)
    XCTAssertEqual(item.lastCopiedAt, now)
    XCTAssertEqual(item.title, "Copied text")
  }

  func testIngestorProtocolAcceptsSendableImplementations() async {
    let ingestor: any ClipboardIngestor = StubIngestor()
    let result = await ingestor.ingest(
      IngestRequest(
        source: PasteboardSource(changeCount: 1),
        contents: [],
        application: nil,
        now: Date(timeIntervalSince1970: 0)
      )
    )

    XCTAssertEqual(result, IngestResult(event: nil, metrics: .zero))
  }
}

private struct StubIngestor: ClipboardIngestor {
  func ingest(_ request: IngestRequest) async -> IngestResult {
    IngestResult(event: nil, metrics: .zero)
  }
}

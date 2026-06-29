import XCTest
@testable import Maccy

/// Tests for the clipboard ingest protocol and its main-actor adapter.
@MainActor
class ClipboardIngestorTests: XCTestCase {
  /// The main-actor adapter builds a `HistoryItem` carrying the request's
  /// contents, application, timestamps, and derived title.
  func testMainActorAdapterBuildsHistoryItemFromRequest() {
    let now = Date(timeIntervalSince1970: 1_717_171_717)
    let request = IngestRequest(
      source: CopyOrigin(changeCount: 7, name: "test"),
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

  /// The ingest protocol accepts any `Sendable` implementation and returns its result.
  func testIngestorProtocolAcceptsSendableImplementations() async {
    let ingestor: any ClipboardIngestor = StubIngestor()
    let result = await ingestor.ingest(
      IngestRequest(
        source: CopyOrigin(changeCount: 1),
        contents: [],
        application: nil,
        now: Date(timeIntervalSince1970: 0)
      )
    )

    XCTAssertEqual(result, IngestResult(event: nil, metrics: .zero))
  }
}

/// Minimal `ClipboardIngestor` stub returning an empty result.
private struct StubIngestor: ClipboardIngestor {
  func ingest(_ request: IngestRequest) async -> IngestResult {
    IngestResult(event: nil, metrics: .zero)
  }
}

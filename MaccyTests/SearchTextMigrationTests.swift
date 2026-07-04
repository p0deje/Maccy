import Defaults
import SwiftData
import XCTest

@testable import Maccy

/// Tests the persisted full-text search column: that the untruncated searchable
/// body is extracted once at ingest (plain text, RTF, HTML, file URL), that an
/// image-only item carries no searchable text, that oversized rich text
/// degrades to empty, and that the column persists across a save and refetch
/// (the lightweight-migration guarantee).
///
/// Under the test plan's `enable-testing` launch argument, `Storage.shared` is
/// an in-memory SwiftData store shared between the main context and the ingest
/// actor's isolated context.
@MainActor
final class SearchTextMigrationTests: XCTestCase {
  /// Standard pasteboard UTI for UTF-8 plain text.
  private let stringType = NSPasteboard.PasteboardType.string.rawValue

  private var savedSize: Int = 200

  override func setUp() async throws {
    try await super.setUp()
    // `Storage.shared` is an in-memory singleton shared across every test in
    // this run; clear it so each test starts from a known-empty store.
    try? Storage.shared.context.delete(model: HistoryItem.self)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()

    savedSize = Defaults[.size]
    Defaults[.size] = 200
  }

  override func tearDown() async throws {
    Defaults[.size] = savedSize
    try await super.tearDown()
  }

  // MARK: - Extraction semantics (pure engine)

  /// Plain-text payload extracts whole — not shortened to the title preview
  /// length — so a match anywhere in a long clip stays searchable.
  func testPlainTextExtractsUntruncated() {
    let body = String(repeating: "a", count: 5_000)
    let contents = [contentEntry(stringType, body)]

    let extracted = HistoryItemEngine.searchableBody(
      contents: contents,
      richTextParsingLimit: 512 * 1024
    )

    XCTAssertEqual(extracted.count, 5_000)
    XCTAssertEqual(extracted, body)
  }

  /// RTF payload extracts to its plain-text content.
  func testRTFExtractsPlainText() {
    let rtf = NSAttributedString(string: "foo").rtf(
      from: NSRange(0...2),
      documentAttributes: [:]
    )
    let contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.rtf.rawValue, value: rtf)
    ]

    let extracted = HistoryItemEngine.searchableBody(
      contents: contents,
      richTextParsingLimit: 512 * 1024
    )

    XCTAssertEqual(extracted, "foo")
  }

  /// HTML payload extracts to its plain-text content.
  func testHTMLExtractsPlainText() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue, value: html)
    ]

    let extracted = HistoryItemEngine.searchableBody(
      contents: contents,
      richTextParsingLimit: 512 * 1024
    )

    XCTAssertEqual(extracted, "foo")
  }

  /// A file-URL payload extracts to its absolute URL string.
  func testFileURLExtractsURLString() {
    let url = URL(fileURLWithPath: "/tmp/report.pdf")
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fileURL.rawValue,
        value: url.dataRepresentation
      )
    ]

    let extracted = HistoryItemEngine.searchableBody(
      contents: contents,
      richTextParsingLimit: 512 * 1024
    )

    XCTAssertEqual(extracted, url.absoluteString)
  }

  /// An image-only payload carries no searchable text.
  func testImageOnlyExtractsEmpty() {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.tiff.rawValue,
        value: Data(repeating: 0x00, count: 16)
      )
    ]

    let extracted = HistoryItemEngine.searchableBody(
      contents: contents,
      richTextParsingLimit: 512 * 1024
    )

    XCTAssertEqual(extracted, "")
  }

  /// Rich text larger than the parse limit is skipped — parsing it is costly and
  /// main-thread-affine — so the body degrades to empty rather than blocking.
  func testOversizedRichTextDegradesToEmpty() {
    let oversize = Data(repeating: 0x41, count: 512 * 1024 + 1)
    let contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.rtf.rawValue, value: oversize)
    ]

    let extracted = HistoryItemEngine.searchableBody(
      contents: contents,
      richTextParsingLimit: 512 * 1024
    )

    XCTAssertEqual(extracted, "")
  }

  // MARK: - Persistence (lightweight migration)

  /// The search column persists across a save and refetch, proving it is a real
  /// stored column (a computed property would not survive the round trip).
  func testSearchTextPersistsAcrossSaveAndRefetch() {
    let item = HistoryItem(
      contents: [contentEntry(stringType, "hello body")]
    )
    item.title = item.generateTitle()
    item.searchText = item.searchableBody()
    Storage.shared.context.insert(item)
    XCTAssertNoThrow(try Storage.shared.context.save())

    let refetched = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(refetched?.count, 1)
    XCTAssertEqual(refetched?.first?.searchText, "hello body")
  }

  /// A row that predates the column (never assigned) reads `nil`, the state in
  /// which search degrades to title-only until a future backfill.
  func testRowWithoutSearchTextReadsNil() {
    let item = HistoryItem(
      contents: [contentEntry(stringType, "never assigned")]
    )
    Storage.shared.context.insert(item)
    XCTAssertNoThrow(try Storage.shared.context.save())

    let refetched = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertNil(refetched?.first?.searchText)
  }

  // MARK: - Ingest wiring

  /// A newly ingested plain-text row has its search column populated with the
  /// full text (longer than the title preview length), end-to-end through the
  /// off-main ingest actor and the shared store.
  func testIngestActorStoresSearchTextOnNewRow() async {
    let body = String(repeating: "a", count: 2_400)
    let ingestor = makeIngestor()

    let result = await ingestor.ingest(request([content(type: stringType, value: Data(body.utf8))]))

    if case .added = result.event {
      // Expected: a unique long clip is added, not merged.
    } else {
      XCTFail("Expected .added, got \(String(describing: result.event))")
    }

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1)
    XCTAssertEqual(stored?.first?.searchText, body)
    XCTAssertEqual(stored?.first?.title.count, HistoryItem.titlePreviewLimit)
  }

  // MARK: - Helpers

  /// Builds a single plain-string content entry.
  private func contentEntry(_ type: String, _ value: String) -> HistoryItemContent {
    HistoryItemContent(type: type, value: value.data(using: .utf8))
  }

  /// Constructs the ingest actor against the shared in-memory container with a
  /// fixed clock and a no-op event sink.
  private func makeIngestor() -> BackgroundClipboardIngestor {
    BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )
  }

  /// Builds a `ContentDTO` with its fingerprint and size derived from the value.
  private func content(type: String, value: Data) -> ContentDTO {
    ContentDTO(
      type: type,
      value: value,
      fingerprint: ClipboardDataProcessor.fingerprintIfLarge(value),
      size: value.count
    )
  }

  /// Builds an `IngestRequest` from plain content.
  private func request(_ contents: [ContentDTO], changeCount: Int = 1) -> IngestRequest {
    IngestRequest(
      source: CopyOrigin(changeCount: changeCount),
      contents: contents,
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }
}

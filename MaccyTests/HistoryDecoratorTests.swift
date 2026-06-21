import XCTest
import Defaults
@testable import Maccy

@MainActor
class HistoryItemDecoratorTests: XCTestCase { // swiftlint:disable:this type_body_length
  let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
  let savedHighlightMatch = Defaults[.highlightMatch]
  let savedImageMaxHeight = Defaults[.imageMaxHeight]

  var firstCopiedAt: Date! {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
    return formatter.date(from: "2020/07/10 12:31:34")
  }

  var lastCopiedAt: Date! {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
    return formatter.date(from: "2020/07/10 12:41:34")
  }

  override func setUp() {
    super.setUp()
    Defaults[.highlightMatch] = .bold
    Defaults[.imageMaxHeight] = 40
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.imageMaxHeight] = savedImageMaxHeight
    Defaults[.highlightMatch] = savedHighlightMatch
  }

  func testString() {
    let title = "foo"
    let itemDecorator = historyItemDecorator(title)
    XCTAssertEqual(itemDecorator.title, title)
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testRTF() {
    let rtf = NSAttributedString(string: "foo").rtf(
      from: NSRange(0...2),
      documentAttributes: [:]
    )
    let itemDecorator = historyItemDecorator(rtf, .rtf)
    XCTAssertEqual(itemDecorator.title, "foo")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testHTML() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let itemDecorator = historyItemDecorator(html, .html)
    XCTAssertEqual(itemDecorator.title, "foo")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testImage() async {
    let image = NSImage(named: "StatusBarMenuImage")!
    let itemDecorator = historyItemDecorator(image)
    itemDecorator.sizeImages()
    // Generation now runs off-main (BS-3.5); wait for the structured tasks to
    // publish before asserting. PassthroughImageProcessor mirrors the old
    // on-main resize path so the size contract is unchanged.
    _ = await itemDecorator.previewImageGenerationTask?.result
    _ = await itemDecorator.thumbnailImageGenerationTask?.result
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertEqual(itemDecorator.previewImage!.size, image.size)
    XCTAssertEqual(itemDecorator.thumbnailImage!.size, image.size)
  }

  // We also need to add test for image with width bigger than max width.
  func testImageWithHeightBiggerThanMaxHeight() async {
    let image = NSImage(named: "NSApplicationIcon")!
    let itemDecorator = historyItemDecorator(image)
    itemDecorator.sizeImages()
    _ = await itemDecorator.thumbnailImageGenerationTask?.result
    XCTAssertEqual(itemDecorator.thumbnailImage!.size, NSSize(width: 40, height: 40))
  }

  // MARK: - Preview cancellation (P2 / IMG-023 gap)

  /// `cancelPreviewGeneration()` must cancel an in-flight preview decode, drop
  /// the task handle, and leave `previewImage` untouched. This is the BS-3 收尾:
  /// previously only `invalidate()`/`cleanupImages()` cancelled the decorator's
  /// preview task, so navigating off a lead item left its decode running on the
  /// single serial `ImageProcessor` actor — the stale-decode pile-up (1.5s
  /// spike, mouse-hover worst case). See
  /// docs/audit/2026-06-21-render-feedback-stopgap.md.
  ///
  /// Uses `StallableImageProcessor`, whose `preview` spins on `Task.isCancelled`
  /// (cooperative cancellation, like the production `ImageProcessor`'s
  /// `Task.isCancelled` checkpoints) — so a cancelled decode returns nil and
  /// never publishes. A poll loop (not `withCheckedContinuation`) guarantees the
  /// cancellation is observed within one tick, so this test cannot hang.
  func testCancelPreviewGenerationCancelsInFlightDecode() async {
    let processor = StallableImageProcessor()
    let itemDecorator = historyItemDecorator(largeImageData(), .png, imageProcessor: processor)
    itemDecorator.ensurePreviewImage()
    XCTAssertNotNil(itemDecorator.previewImageGenerationTask, "preview task should be kicked")
    XCTAssertNil(itemDecorator.previewImage, "no preview yet — decode is stalled in the mock")

    // Cancel while the decode is in-flight. The task must be cancelled + nil'd;
    // the (still-nil) previewImage must be untouched. Await the captured task:
    // the stallable mock observes the cancellation and returns nil, so the task
    // completes (and its `guard !isInvalidated`/publish path publishes nothing).
    let task = itemDecorator.previewImageGenerationTask
    itemDecorator.cancelPreviewGeneration()
    XCTAssertNil(itemDecorator.previewImageGenerationTask, "task handle cleared on cancel")
    if let task {
      _ = await task.value
    }
    XCTAssertNil(itemDecorator.previewImage, "cancelled decode must not publish an image")
    XCTAssertFalse(processor.previewCompleted, "the stalled decode must not have completed")
  }

  /// A cached preview survives `cancelPreviewGeneration()` (re-selecting an
  /// already-decoded item must stay instant). Uses the real
  /// `PassthroughImageProcessor` (decodes synchronously) so the preview caches
  /// before cancel — exercising the actual cache-survives-cancel contract.
  func testCancelPreviewGenerationKeepsCachedPreview() async {
    let itemDecorator = historyItemDecorator(largeImageData(), .png, imageProcessor: PassthroughImageProcessor())
    itemDecorator.ensurePreviewImage()
    _ = await itemDecorator.previewImageGenerationTask?.result
    XCTAssertNotNil(itemDecorator.previewImage, "preview decoded + cached")

    itemDecorator.cancelPreviewGeneration()
    XCTAssertNotNil(itemDecorator.previewImage, "cached preview survives cancel")
    XCTAssertNil(itemDecorator.previewImageGenerationTask, "task handle cleared")

    // A subsequent `ensurePreviewImage` must be a no-op (cache hit) — it should
    // NOT kick a new task (previewImage is non-nil, guard short-circuits).
    itemDecorator.ensurePreviewImage()
    XCTAssertNil(itemDecorator.previewImageGenerationTask, "cache hit must not re-kick")
    XCTAssertNotNil(itemDecorator.previewImage, "preview still cached")
  }

  /// `cancelPreviewGeneration()` is idempotent and safe when no task is running
  /// (e.g. a text item, or an item whose preview was never requested).
  func testCancelPreviewGenerationNoOpWhenIdle() {
    let itemDecorator = historyItemDecorator("text")
    itemDecorator.cancelPreviewGeneration() // text item — no preview task ever
    XCTAssertNil(itemDecorator.previewImageGenerationTask)
    XCTAssertNil(itemDecorator.previewImage)
  }

  func testFile() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let itemDecorator = historyItemDecorator(url)
    XCTAssertEqual(itemDecorator.title, "file:///tmp/foo.bar")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let itemDecorator = historyItemDecorator(url)
    XCTAssertEqual(itemDecorator.title, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testItemWithoutData() {
    let itemDecorator = historyItemDecorator(nil)
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testLargeTextPreviewIsBounded() {
    let itemDecorator = historyItemDecorator(String(repeating: "a", count: 50_000))
    XCTAssertEqual(itemDecorator.text.count, HistoryItem.textPreviewLimit)
  }

  func testLargeTextPreviewBenchmark() {
    let itemDecorator = historyItemDecorator(String(repeating: "abcdef\n", count: 20_000))

    measure {
      _ = itemDecorator.text
    }
  }

  func testLargeImageHasImageDoesNotGenerateRenderedImages() {
    let itemDecorator = historyItemDecorator(largeImageData(), .png)
    XCTAssertTrue(itemDecorator.hasImage)
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  func testLargeImageSizingBenchmark() {
    // Passthrough keeps the benchmark off disk (the production ImageProcessor
    // would persist thumbnails) so it measures the synchronous main-thread
    // cost of cleanup + dispatch, not disk I/O variance.
    let itemDecorator = historyItemDecorator(largeImageData(), .png, imageProcessor: PassthroughImageProcessor())

    measure {
      itemDecorator.cleanupImages()
      itemDecorator.sizeImages()
    }
  }

  func testUnpinnedByDefault() {
    let itemDecorator = historyItemDecorator("foo")
    XCTAssertNil(itemDecorator.item.pin)
    XCTAssertFalse(itemDecorator.isPinned)
  }

  func testPin() {
    let itemDecorator = historyItemDecorator("foo")
    itemDecorator.togglePin()
    XCTAssertNotNil(itemDecorator.item.pin)
    XCTAssertTrue(itemDecorator.isPinned)
  }

  func testUnpin() {
    let itemDecorator = historyItemDecorator("foo")
    itemDecorator.togglePin()
    itemDecorator.togglePin()
    XCTAssertNil(itemDecorator.item.pin)
    XCTAssertFalse(itemDecorator.isPinned)
  }

  func testHighlight() {
    let itemDecorator = historyItemDecorator("foo bar baz")
    itemDecorator.highlight("random", [
      range(from: 1, to: 2, in: itemDecorator),
      range(from: 8, to: 10, in: itemDecorator)
    ])
    var expectedTitle = AttributedString("foo bar baz")
    expectedTitle[expectedTitle.range(of: "oo")!].font = .bold(.body)()
    expectedTitle[expectedTitle.range(of: "baz")!].font = .bold(.body)()
    XCTAssertEqual(itemDecorator.attributedTitle, expectedTitle)
    itemDecorator.highlight("", [])
    XCTAssertEqual(itemDecorator.attributedTitle, nil)
  }

  private func historyItemDecorator(
    _ value: String?,
    application: String? = "com.apple.finder"
  ) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value?.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = application
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt

    return HistoryItemDecorator(item)
  }

  private func historyItemDecorator(
    _ value: Data?,
    _ type: NSPasteboard.PasteboardType,
    imageProcessor: ImageProcessing = HistoryItemDecorator.defaultImageProcessor
  ) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: type.rawValue,
        value: value
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2

    return HistoryItemDecorator(item, imageProcessor: imageProcessor)
  }

  private func historyItemDecorator(_ value: NSImage) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.tiff.rawValue,
        value: value.tiffRepresentation!
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2

    // Inject the synchronous passthrough processor so image generation completes
    // deterministically (awaited in the test); the production ImageProcessor
    // is exercised by ImageProcessorTests.
    return HistoryItemDecorator(item, imageProcessor: PassthroughImageProcessor())
  }

  private func historyItemDecorator(_ value: URL) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fileURL.rawValue,
        value: value.dataRepresentation
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.lastPathComponent.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2

    return HistoryItemDecorator(item)
  }

  private func largeImageData() -> Data {
    let image = NSImage(size: NSSize(width: 2_048, height: 2_048), flipped: false) { rect in
      NSColor.systemBlue.setFill()
      rect.fill()
      return true
    }

    return image.tiffRepresentation!
  }

  // swiftlint:disable:next identifier_name
  private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
    let startIndex = item.title.startIndex
    let lowerBound = item.title.index(startIndex, offsetBy: from)
    let upperBound = item.title.index(startIndex, offsetBy: to + 1)

    return lowerBound..<upperBound
  }
}

/// An `ImageProcessing` double whose `preview` STALLS until the task is
/// cancelled — so a test can kick a preview, cancel it mid-decode, and assert
/// the decode never publishes. Mirrors the production `ImageProcessor`'s
/// cooperative cancellation: it spins on `Task.isCancelled` (5 ms tick) and
/// returns nil the moment cancellation lands. A poll loop (not
/// `withCheckedContinuation`/`withTaskCancellationHandler`) is used because it
/// CANNOT hang — cancellation is always observed within one tick, and there is
/// no continuation-resume handshake to get wrong. `previewCompleted` records
/// whether a decode ran to completion (uncancelled) — a cancelled decode must
/// leave it false.
///
/// Swift 6 safe: `previewCompleted` is a lock-guarded stored property (no
/// captured local-var mutation across concurrency boundaries).
private final class StallableImageProcessor: ImageProcessing, @unchecked Sendable {
  private let lock = NSLock()
  private var previewCompletedValue = false

  var previewCompleted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return previewCompletedValue
  }

  func thumbnail(for data: Data, max: CGSize) async -> NSImage? {
    // Not exercised by the preview-cancellation tests; pass through.
    NSImage(data: data)
  }

  func preview(for data: Data, max: CGSize) async -> NSImage? {
    // Stall until cancelled (cooperative, like ImageProcessor's checkpoints).
    // The 5 ms tick guarantees cancellation is observed fast; no continuation =
    // no hang risk.
    while !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(5))
    }
    // Cancelled → return nil (the decorator discards; no publish). We never
    // reach the "completed" path on a cancelled decode.
    if Task.isCancelled {
      return nil
    }
    lock.lock()
    previewCompletedValue = true
    lock.unlock()
    return NSImage()
  }
}

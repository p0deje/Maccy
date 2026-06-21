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
  /// the task handle (so a later re-select can re-kick), and NOT clear an
  /// already-cached `previewImage`. This is the BS-3 收尾: previously only
  /// `invalidate()`/`cleanupImages()` cancelled the decorator's preview task,
  /// so navigating off a lead item left its decode running on the single serial
  /// `ImageProcessor` actor — the stale-decode pile-up (1.5s spike, mouse-hover
  /// worst case). See docs/audit/2026-06-21-render-feedback-stopgap.md.
  func testCancelPreviewGenerationCancelsInFlightAndKeepsCache() async {
    let processor = ControllableImageProcessor()
    let itemDecorator = historyItemDecorator(largeImageData(), .png, imageProcessor: processor)
    itemDecorator.ensurePreviewImage()
    XCTAssertNotNil(itemDecorator.previewImageGenerationTask, "preview task should be kicked")
    XCTAssertNil(itemDecorator.previewImage, "no preview yet — decode is gated on the mock")

    // Cancel while the decode is parked in the mock. The task must be cancelled
    // + nil'd; the (still-nil) previewImage must be untouched.
    itemDecorator.cancelPreviewGeneration()
    XCTAssertNil(itemDecorator.previewImageGenerationTask, "task handle cleared on cancel")
    // Release the mock so the cancelled task can finish without publishing.
    processor.releaseAll()
    // Give the cancelled task a turn to observe cancellation.
    await Task.yield()
    await Task.yield()
    XCTAssertNil(itemDecorator.previewImage, "cancelled decode must not publish an image")
  }

  /// A cached preview survives `cancelPreviewGeneration()` (re-selecting an
  /// already-decoded item must stay instant), and the task handle is nil so a
  /// subsequent `ensurePreviewImage` is a no-op (cache hit).
  func testCancelPreviewGenerationKeepsCachedPreview() async {
    let processor = ControllableImageProcessor()
    let itemDecorator = historyItemDecorator(largeImageData(), .png, imageProcessor: processor)
    // Let one decode complete and cache.
    processor.releaseAll()
    itemDecorator.ensurePreviewImage()
    _ = await itemDecorator.previewImageGenerationTask?.result
    XCTAssertNotNil(itemDecorator.previewImage, "preview decoded + cached")

    itemDecorator.cancelPreviewGeneration()
    XCTAssertNotNil(itemDecorator.previewImage, "cached preview survives cancel")
    XCTAssertNil(itemDecorator.previewImageGenerationTask, "task handle cleared")
  }

  /// `cancelPreviewGeneration()` is idempotent and safe when no task is running.
  func testCancelPreviewGenerationNoOpWhenIdle() {
    let itemDecorator = historyItemDecorator("text")
    itemDecorator.cancelPreviewGeneration() // text item — no preview task ever
    XCTAssertNil(itemDecorator.previewImageGenerationTask)
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

/// A controllable `ImageProcessing` double for the preview-cancellation tests.
/// `preview(for:max:)` parks on a continuation until `releaseAll()` is called
/// or the awaiting task is cancelled — so a test can kick a preview, cancel it
/// mid-decode, and assert the decode never publishes. Honours cooperative
/// cancellation (`Task.isCancelled`) so the parked await returns nil on cancel.
private final class ControllableImageProcessor: ImageProcessing, @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [CheckedContinuation<NSImage?, Never>] = []

  func thumbnail(for data: Data, max: CGSize) async -> NSImage? {
    // Not exercised by the preview-cancellation tests; pass through.
    NSImage(data: data)
  }

  func preview(for data: Data, max: CGSize) async -> NSImage? {
    // Park until released or cancelled. On cancellation return nil (the
    // decorator discards it; no publish). Uses withTaskCancellationHandler so
    // a cancel of the awaiting task resumes the continuation with nil.
    let cancellation = NSLock()
    var didCancel = false
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
        lock.lock()
        if didCancel {
          lock.unlock()
          continuation.resume(returning: nil)
          return
        }
        continuations.append(continuation)
        lock.unlock()
      }
    } onCancel: {
      cancellation.lock()
      didCancel = true
      cancellation.unlock()
      // Resume one parked continuation (the cancelled one) with nil.
      lock.lock()
      let pending = continuations.isEmpty ? nil : continuations.removeFirst()
      lock.unlock()
      pending?.resume(returning: nil)
    }
  }

  /// Resumes all parked previews with an image (lets a decode "complete").
  func releaseAll() {
    lock.lock()
    let pending = continuations
    continuations.removeAll()
    lock.unlock()
    for continuation in pending {
      continuation.resume(returning: NSImage())
    }
  }
}

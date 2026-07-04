import XCTest
import Defaults
import os
@testable import Maccy

/// Tests for `HistoryItemDecorator`: title generation, image sizing, pin state,
/// and preview cancellation.
@MainActor
class HistoryItemDecoratorTests: XCTestCase {
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

  /// A plain-string content entry yields its text as the title and no images.
  func testString() {
    let title = "foo"
    let itemDecorator = historyItemDecorator(title)
    XCTAssertEqual(itemDecorator.title, title)
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  /// An RTF content entry yields its plain-text content as the title.
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

  /// An HTML content entry yields its plain-text content as the title.
  func testHTML() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let itemDecorator = historyItemDecorator(html, .html)
    XCTAssertEqual(itemDecorator.title, "foo")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  /// An image content entry yields an empty title and matching preview/thumbnail sizes.
  func testImage() async {
    let image = NSImage(named: "StatusBarMenuImage")!
    let itemDecorator = historyItemDecorator(image)
    itemDecorator.sizeImages()
    // Image generation runs off-main; wait for the structured tasks to publish
    // before asserting. `PassthroughImageProcessor` mirrors the old on-main
    // resize path so the size contract is unchanged.
    _ = await itemDecorator.previewImageGenerationTask?.result
    _ = await itemDecorator.thumbnailImageGenerationTask?.result
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertEqual(itemDecorator.previewImage!.size, image.size)
    XCTAssertEqual(itemDecorator.thumbnailImage!.size, image.size)
  }

  /// A thumbnail taller than `imageMaxHeight` is capped to the max-height square.
  func testImageWithHeightBiggerThanMaxHeight() async {
    let image = NSImage(named: "NSApplicationIcon")!
    let itemDecorator = historyItemDecorator(image)
    itemDecorator.sizeImages()
    _ = await itemDecorator.thumbnailImageGenerationTask?.result
    XCTAssertEqual(itemDecorator.thumbnailImage!.size, NSSize(width: 40, height: 40))
  }

  // MARK: - Preview cancellation

  /// `cancelPreviewGeneration()` cancels an in-flight preview decode, drops the
  /// task handle, and leaves `previewImage` untouched.
  ///
  /// Previously only `invalidate()`/`cleanupImages()` cancelled the decorator's
  /// preview task, so navigating off a lead item left its decode running on the
  /// single serial image-processor actor — a stale-decode pile-up (a 1.5s spike,
  /// worst case on hover).
  ///
  /// Uses `StallableImageProcessor`, whose `preview` spins on `Task.isCancelled`
  /// (cooperative cancellation, like the production image processor's
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
  /// already-decoded item must stay instant).
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
    // text item — no preview task ever
    itemDecorator.cancelPreviewGeneration()
    XCTAssertNil(itemDecorator.previewImageGenerationTask)
    XCTAssertNil(itemDecorator.previewImage)
  }

  /// A file-URL content entry yields the URL string as the title.
  func testFile() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let itemDecorator = historyItemDecorator(url)
    XCTAssertEqual(itemDecorator.title, "file:///tmp/foo.bar")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  /// A file URL with non-ASCII path segments keeps its escaped form in the title.
  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let itemDecorator = historyItemDecorator(url)
    XCTAssertEqual(itemDecorator.title, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  /// A content entry with no data yields an empty title and no images.
  func testItemWithoutData() {
    let itemDecorator = historyItemDecorator(nil)
    XCTAssertEqual(itemDecorator.title, "")
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  /// The text preview is truncated to `textPreviewLimit` for very long content.
  func testLargeTextPreviewIsBounded() {
    let itemDecorator = historyItemDecorator(String(repeating: "a", count: 50_000))
    XCTAssertEqual(itemDecorator.text.count, HistoryItem.textPreviewLimit)
  }

  /// Benchmark for the text-prefix preview computation, amplified to overcome timer jitter.
  func testLargeTextPreviewBenchmark() {
    let itemDecorator = historyItemDecorator(String(repeating: "abcdef\n", count: 20_000))

    // Measure the underlying preview computation directly. `.text` caches its
    // result in `textPreviewCache`, so measuring `_ = itemDecorator.text` was
    // measuring a cache hit after iteration 1 — a broken benchmark (one cold
    // compute, nine ~3µs lookups → chronic RSD ~240%). Compute the prefix
    // afresh each call and amplify N× so the signal rises above the shared-
    // runner timer noise (the measure{} RSD gate is 10%).
    let item = itemDecorator.item
    _ = item.previewableTextPrefix(maxLength: HistoryItem.textPreviewLimit)
    measure {
      for _ in 0..<50 {
        _ = item.previewableTextPrefix(maxLength: HistoryItem.textPreviewLimit)
      }
    }
  }

  /// A large image is recognized as an image but renders no preview/thumbnail until sized.
  func testLargeImageHasImageDoesNotGenerateRenderedImages() {
    let itemDecorator = historyItemDecorator(largeImageData(), .png)
    XCTAssertTrue(itemDecorator.hasImage)
    XCTAssertNil(itemDecorator.previewImage)
    XCTAssertNil(itemDecorator.thumbnailImage)
  }

  /// Benchmark for the synchronous image sizing/dispatch path, amplified to overcome timer jitter.
  func testLargeImageSizingBenchmark() {
    // InstantImageProcessor returns nil with no decode, so this measures only
    // the synchronous main-thread kick path (cleanupImages + sizeImages dispatch).
    // PassthroughImageProcessor actually decodes — and the ImageIO thumbnail
    // decode is non-cancellable once started, so any task that began before the
    // next cleanupImages ran to completion (ms-scale outliers) → chronic RSD
    // ~40–150%. Amplified 100× per sample for a stable signal above timer jitter.
    let itemDecorator = historyItemDecorator(largeImageData(), .png, imageProcessor: InstantImageProcessor())
    itemDecorator.cleanupImages()
    itemDecorator.sizeImages()
    measure {
      for _ in 0..<100 {
        itemDecorator.cleanupImages()
        itemDecorator.sizeImages()
      }
    }
  }

  /// A new item is unpinned by default.
  func testUnpinnedByDefault() {
    let itemDecorator = historyItemDecorator("foo")
    XCTAssertNil(itemDecorator.item.pin)
    XCTAssertFalse(itemDecorator.isPinned)
  }

  /// `togglePin()` pins an unpinned item.
  func testPin() {
    let itemDecorator = historyItemDecorator("foo")
    itemDecorator.togglePin()
    XCTAssertNotNil(itemDecorator.item.pin)
    XCTAssertTrue(itemDecorator.isPinned)
  }

  /// `togglePin()` toggles a pinned item back to unpinned.
  func testUnpin() {
    let itemDecorator = historyItemDecorator("foo")
    itemDecorator.togglePin()
    itemDecorator.togglePin()
    XCTAssertNil(itemDecorator.item.pin)
    XCTAssertFalse(itemDecorator.isPinned)
  }

  /// `highlight` applies bold styling to the matched ranges of the title.
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

  /// Highlighting reaches matches past the old fixed 500-char render cap.
  /// The render window now tracks the title-preview window, so a match near the
  /// end of a long title is styled instead of silently dropped.
  func testHighlight_appliesToMatchesPastOldRenderCap() {
    let title = String(repeating: "a", count: 600) + "bcdef"
    let itemDecorator = historyItemDecorator(title)
    Defaults[.highlightMatch] = .bold

    let marker = itemDecorator.title.range(of: "bcdef")!
    itemDecorator.highlight("bcdef", [marker])

    var expectedTitle = AttributedString(title)
    expectedTitle[expectedTitle.range(of: "bcdef")!].font = .bold(.body)()
    XCTAssertEqual(itemDecorator.attributedTitle, expectedTitle)
  }

  /// Builds a decorator backed by a single UTF-8 string content entry.
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

  /// Builds a decorator backed by a single raw-data content entry of the given type.
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

  /// Builds a decorator backed by a TIFF image content entry with a synchronous
  /// image processor so generation completes deterministically within the test.
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

  /// Builds a decorator backed by a file-URL content entry (URL plus its filename string).
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

  /// Returns the TIFF data of a 2048×2048 solid-blue image.
  private func largeImageData() -> Data {
    let image = NSImage(size: NSSize(width: 2_048, height: 2_048), flipped: false) { rect in
      NSColor.systemBlue.setFill()
      rect.fill()
      return true
    }

    return image.tiffRepresentation!
  }

  /// Converts half-open `[from...to]` integer offsets into a `String.Index` range
  /// within the decorator's title.
  private func range(from startOffset: Int, to endOffset: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
    let startIndex = item.title.startIndex
    let lowerBound = item.title.index(startIndex, offsetBy: startOffset)
    let upperBound = item.title.index(startIndex, offsetBy: endOffset + 1)

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
/// Swift 6 safe: `previewCompleted` is guarded by an `OSAllocatedUnfairLock`
/// (Sendable; available macOS 13+). Apple's docs state that when using a lock
/// with asynchronous code, "lock using a closure" — `withLock(_:)` is the
/// async-safe form. `NSLock.lock()`/`unlock()` are unavailable from async
/// contexts in Swift 6 (cooperative-pool deadlock risk), which is why the
/// closure form is used here instead. The lock is held only for a trivial
/// boolean read/write — never across an `await` suspension point.
private final class StallableImageProcessor: ImageProcessing, Sendable {
  private let completed = OSAllocatedUnfairLock(initialState: false)

  /// Whether a decode ran to completion (uncancelled).
  var previewCompleted: Bool {
    completed.withLock { $0 }
  }

  /// Not exercised by the preview-cancellation tests; decodes synchronously.
  func thumbnail(for data: Data, max: CGSize) async -> NSImage? {
    // Not exercised by the preview-cancellation tests; pass through.
    NSImage(data: data)
  }

  /// Stalls until the task is cancelled, then returns nil (no publish).
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
    completed.withLock { flag in flag = true }
    return NSImage()
  }
}

/// Returns `nil` instantly with no decode — for benchmarks that measure the
/// synchronous main-thread kick path (`ensureThumbnailImage`/`ensurePreviewImage`
/// → `cleanupImages`/`sizeImages` dispatch) without off-main decode variance.
/// `PassthroughImageProcessor` actually decodes (`NSImage(data:).resized`), and
/// the ImageIO thumbnail decode is non-cancellable once started, so tasks that
/// began before a `cleanupImages` produced ms-scale outliers (RSD ~40–150%).
private struct InstantImageProcessor: ImageProcessing {
  func thumbnail(for data: Data, max: CGSize) async -> NSImage? { nil }
  func preview(for data: Data, max: CGSize) async -> NSImage? { nil }
}

import AppKit
import Testing
import Defaults
@testable import Maccy

private final class DecoratorBundleToken {}

extension SharedStateTests {
  @MainActor
  final class HistoryItemDecoratorTests {
    let savedHighlightMatch = Defaults[.highlightMatch]
    let savedImageMaxHeight = Defaults[.imageMaxHeight]
    let savedLowMemoryImageMode = Defaults[.lowMemoryImageMode]

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

    init() {
      Defaults[.highlightMatch] = .bold
      Defaults[.imageMaxHeight] = 40
      Defaults[.lowMemoryImageMode] = false
    }

    deinit {
      Defaults[.imageMaxHeight] = savedImageMaxHeight
      Defaults[.highlightMatch] = savedHighlightMatch
      Defaults[.lowMemoryImageMode] = savedLowMemoryImageMode
    }

    @Test("String")
    func string() {
      let title = "foo"
      let itemDecorator = historyItemDecorator(title)
      #expect(itemDecorator.title == title)
      #expect(itemDecorator.previewImage == nil)
      #expect(itemDecorator.thumbnailImage == nil)
    }

    @Test("RTF")
    func rtf() {
      let rtf = NSAttributedString(string: "foo").rtf(
        from: NSRange(0...2),
        documentAttributes: [:]
      )
      let itemDecorator = historyItemDecorator(rtf, .rtf)
      #expect(itemDecorator.title == "foo")
      #expect(itemDecorator.previewImage == nil)
      #expect(itemDecorator.thumbnailImage == nil)
    }

    @Test("HTML")
    func html() {
      let html = "<a href='#'>foo</a>".data(using: .utf8)
      let itemDecorator = historyItemDecorator(html, .html)
      #expect(itemDecorator.title == "foo")
      #expect(itemDecorator.previewImage == nil)
      #expect(itemDecorator.thumbnailImage == nil)
    }

    @Test("Image")
    func image() throws {
      let image = try #require(NSImage(named: "StatusBarMenuImage"))
      let itemDecorator = historyItemDecorator(image)
      itemDecorator.sizeImages()
      #expect(itemDecorator.title == "")
      #expect(try #require(itemDecorator.previewImage).size == image.size)
      #expect(try #require(itemDecorator.thumbnailImage).size == image.size)
    }

    // We also need to add test for image with width bigger than max width.
    @Test("Image with height bigger than max height")
    func imageWithHeightBiggerThanMaxHeight() throws {
      let image = try #require(NSImage(named: "NSApplicationIcon"))
      let itemDecorator = historyItemDecorator(image)
      itemDecorator.sizeImages()
      #expect(try #require(itemDecorator.thumbnailImage).size == NSSize(width: 40, height: 40))
    }

    @Test("Downsampled image uses requested maximum pixel size")
    func downsampledImageUsesRequestedMaximumPixelSize() throws {
      let image = try #require(NSImage.downsampled(from: try testImageData(), maxPixelSize: 64, scale: 2))
      #expect(max(image.pixelSize.width, image.pixelSize.height) == 64)
    }

    @Test("Pixel size reads image header")
    func pixelSizeReadsImageHeader() throws {
      #expect(NSImage.pixelSize(from: try testImageData()) == NSSize(width: 262, height: 320))
    }

    @Test("Image data loader reads from throwaway context")
    func imageDataLoaderReadsFromThrowawayContext() throws {
      let data = try testImageData()
      let item = HistoryItem(contents: [
        HistoryItemContent(type: NSPasteboard.PasteboardType.jpeg.rawValue, value: data)
      ])
      let context = Storage.shared.context
      context.insert(item)
      try context.save()
      defer {
        context.delete(item)
        try? context.save()
      }

      #expect(HistoryItem.imageData(for: item.persistentModelID, in: Storage.shared.container) == item.imageData)
    }

    @Test("Cleanup images releases low-memory images")
    func cleanupImagesReleasesLowMemoryImages() async throws {
      Defaults[.lowMemoryImageMode] = true
      let itemDecorator = historyItemDecorator(try #require(NSImage(named: "NSApplicationIcon")), save: true)
      itemDecorator.ensureThumbnailImage()
      itemDecorator.ensurePreviewImage()
      let thumbnailTask = itemDecorator.thumbnailImageGenerationTask
      let previewTask = itemDecorator.previewImageGenerationTask
      _ = await thumbnailTask?.result
      _ = await previewTask?.result

      itemDecorator.cleanupImages()

      #expect(itemDecorator.thumbnailImage == nil)
      #expect(itemDecorator.previewImage == nil)
    }

    @Test("Low-memory mode does not cache decoded image")
    func lowMemoryModeDoesNotCacheDecodedImage() throws {
      Defaults[.lowMemoryImageMode] = true
      let itemDecorator = historyItemDecorator(try #require(NSImage(named: "NSApplicationIcon")))

      let firstImage = try #require(itemDecorator.item.image)
      let secondImage = try #require(itemDecorator.item.image)

      #expect(firstImage !== secondImage)
    }

    @Test("File", arguments: ["/tmp/foo.bar", "/tmp/产品培训/产品培训.txt"])
    func file(path: String) {
      let url = URL(fileURLWithPath: path)
      let itemDecorator = historyItemDecorator(url)
      #expect(itemDecorator.title == "file://\(path)")
      #expect(itemDecorator.previewImage == nil)
      #expect(itemDecorator.thumbnailImage == nil)
    }

    @Test("Item without data")
    func itemWithoutData() {
      let itemDecorator = historyItemDecorator(nil)
      #expect(itemDecorator.title == "")
      #expect(itemDecorator.previewImage == nil)
      #expect(itemDecorator.thumbnailImage == nil)
    }

    @Test("Unpinned by default")
    func unpinnedByDefault() {
      let itemDecorator = historyItemDecorator("foo")
      #expect(itemDecorator.item.pin == nil)
      #expect(!itemDecorator.isPinned)
    }

    @Test("Deallocates when no longer referenced")
    func deallocatesWhenNoLongerReferenced() {
      weak var weakDecorator: HistoryItemDecorator?

      autoreleasepool {
        let itemDecorator = historyItemDecorator("foo")
        weakDecorator = itemDecorator
        #expect(weakDecorator != nil)
      }

      #expect(weakDecorator == nil)
    }

    @Test("Highlight")
    func highlight() throws {
      let itemDecorator = historyItemDecorator("foo bar baz")
      itemDecorator.highlight("random", [
        range(from: 1, to: 2, in: itemDecorator),
        range(from: 8, to: 10, in: itemDecorator)
      ])
      var expectedTitle = AttributedString("foo bar baz")
      expectedTitle[try #require(expectedTitle.range(of: "oo"))].font = .bold(.body)()
      expectedTitle[try #require(expectedTitle.range(of: "baz"))].font = .bold(.body)()
      #expect(itemDecorator.attributedTitle == expectedTitle)
      itemDecorator.highlight("", [])
      #expect(itemDecorator.attributedTitle == nil)
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
      _ type: NSPasteboard.PasteboardType
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

      return HistoryItemDecorator(item)
    }

    private func historyItemDecorator(_ value: NSImage, save: Bool = false) -> HistoryItemDecorator {
      let contents = [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.tiff.rawValue,
          value: value.tiffRepresentation
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
      if save {
        try? Storage.shared.context.save()
      }

      return HistoryItemDecorator(item)
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

    private func testImageData() throws -> Data {
      let url = try #require(Bundle(for: DecoratorBundleToken.self).url(forResource: "guy", withExtension: "jpeg"))
      return try Data(contentsOf: url)
    }

    // swiftlint:disable:next identifier_name
    private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
      let startIndex = item.title.startIndex
      let lowerBound = item.title.index(startIndex, offsetBy: from)
      let upperBound = item.title.index(startIndex, offsetBy: to + 1)

      return lowerBound..<upperBound
    }
  }
}

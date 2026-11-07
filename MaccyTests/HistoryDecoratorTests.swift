import AppKit
import Testing
import Defaults
import Observation
@testable import Maccy

extension SharedStateTests {
  @MainActor
  final class HistoryItemDecoratorTests {
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

    init() {
      Defaults[.highlightMatch] = .bold
      Defaults[.imageMaxHeight] = 40
    }

    deinit {
      Defaults[.imageMaxHeight] = savedImageMaxHeight
      Defaults[.highlightMatch] = savedHighlightMatch
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

    @Test("Text previews stay lazy until accessed", arguments: [
      NSPasteboard.PasteboardType.string, .rtf, .html
    ])
    func textPreviewStaysLazy(type: NSPasteboard.PasteboardType) throws {
      let fullText = "A complete preview, beyond the stored title."
      let data: Data
      switch type {
      case .rtf:
        data = try #require(NSAttributedString(string: fullText).rtf(
          from: NSRange(location: 0, length: fullText.utf16.count),
          documentAttributes: [:]
        ))
      case .html:
        data = Data("<span>\(fullText)</span>".utf8)
      default:
        data = Data(fullText.utf8)
      }
      let item = HistoryItem(contents: [HistoryItemContent(type: type.rawValue, value: data)])
      Storage.shared.context.insert(item)
      item.title = "Stored title"
      let decorator = HistoryItemDecorator(item)

      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.title == "Stored title")
      #expect(decorator.accessibilityLabel.contains("Stored title"))
      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == fullText)
      #expect(decorator.previewText.byteCount == fullText.utf8.count)
      #expect(decorator.isPreviewTextMaterialized)
      #expect(!decorator.previewText.isTruncated)
      #expect(item.contents.first?.value == data)
    }

    @Test("Preview preserves text beyond the search title")
    func textPreviewPreservesFullContent() {
      let fullText = String(repeating: "A line of text.\n", count: 300)
      let decorator = historyItemDecorator(fullText)
      #expect(decorator.title.count <= 1_000)
      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == fullText)
      #expect(decorator.previewText.byteCount == fullText.utf8.count)
      #expect(!decorator.previewText.isTruncated)
    }

    @Test("Pinned text edits invalidate previews without eagerly rebuilding them")
    func pinnedTextEditInvalidatesPreview() async {
      let decorator = historyItemDecorator("Original content")
      decorator.item.pin = "b"
      #expect(decorator.previewText.string == "Original content")

      await confirmation("Preview readers observe content edits") { changed in
        _ = withObservationTracking {
          decorator.previewText
        } onChange: {
          changed()
        }
        decorator.item.contents[0].value = Data("Edited content".utf8)
        await drainObservationCallbacks()
      }

      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == "Edited content")
      #expect(decorator.item.pin == "b")
      #expect(decorator.title == "Original content")
    }

    @Test("Replacing rich content and editing it again refreshes previews")
    func replacementContentInvalidatesPreview() async {
      let decorator = historyItemDecorator(Data("<span>Rich content</span>".utf8), .html)
      #expect(decorator.previewText.string == "Rich content")

      // The editor removes rich formats and stores the edited plain text.
      decorator.item.contents = [HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: Data("Plain replacement".utf8)
      )]
      await drainObservationCallbacks()
      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == "Plain replacement")

      decorator.item.contents[0].value = Data("Second edit".utf8)
      await drainObservationCallbacks()
      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == "Second edit")
    }

    @Test("Unopened previews remain lazy after edits; title fallback stays current")
    func unopenedPreviewAndTitleFallback() async {
      let decorator = historyItemDecorator(nil)
      decorator.item.title = "First fallback"
      await drainObservationCallbacks()
      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == "First fallback")

      decorator.item.title = "Edited fallback"
      await drainObservationCallbacks()
      #expect(!decorator.isPreviewTextMaterialized)
      #expect(decorator.previewText.string == "Edited fallback")
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

    private func historyItemDecorator(_ value: NSImage) -> HistoryItemDecorator {
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

    // swiftlint:disable:next identifier_name
    private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
      let startIndex = item.title.startIndex
      let lowerBound = item.title.index(startIndex, offsetBy: from)
      let upperBound = item.title.index(startIndex, offsetBy: to + 1)

      return lowerBound..<upperBound
    }

    private func drainObservationCallbacks() async {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
          continuation.resume()
        }
      }
    }
  }
}

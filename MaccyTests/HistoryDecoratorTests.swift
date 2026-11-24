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

import Darwin
import Foundation

// Opt in explicitly; the parent suite serializes tests which share Storage and Defaults.
extension SharedStateTests {
  @MainActor
  @Suite(.enabled(if: ProcessInfo.processInfo.environment["MACCY_RUN_BENCHMARKS"] == "1"))
  struct TextPreviewBenchmarks {
    private func memory() -> (resident: UInt64, footprint: UInt64) {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
      let capacity = Int(count)
      let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      guard result == KERN_SUCCESS else { return (0, 0) }
      return (info.resident_size, info.phys_footprint)
    }

    private func emit(_ values: [String: Any]) throws {
      let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
      print("MACCY_BENCHMARK " + String(decoding: data, as: UTF8.self))
    }

    private func milliseconds(_ start: UInt64) -> Double {
      Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    @Test("Decorator construction and one selected text preview", arguments: [200, 2_000])
    func decorators(count: Int) throws {
      let text = String(repeating: "A realistic line of clipboard text. ", count: 80)
      let plain = Data(text.utf8)
      let rtf = try #require(NSAttributedString(string: text).rtf(
        from: NSRange(location: 0, length: text.utf16.count), documentAttributes: [:]))
      let context = Storage.shared.context
      let items = (0..<count).map { index in
        let item = HistoryItem(contents: [HistoryItemContent(
          type: index.isMultiple(of: 2) ? NSPasteboard.PasteboardType.string.rawValue : NSPasteboard.PasteboardType.rtf.rawValue,
          value: index.isMultiple(of: 2) ? plain : rtf)])
        item.title = "Stored title \(index)"
        context.insert(item)
        return item
      }
      defer { items.forEach { context.delete($0) } }
      let before = memory()
      let start = DispatchTime.now().uptimeNanoseconds
      let decorators = items.map { HistoryItemDecorator($0) }
      let constructionMs = milliseconds(start)
      let afterConstruction = memory()
      let previewStart = DispatchTime.now().uptimeNanoseconds
      let preview = decorators[1].previewText.string
      let previewMs = milliseconds(previewStart)
      #expect(decorators.count == count)
      #expect(decorators.last?.title == "Stored title \(count - 1)")
      #expect(preview == text)
      #expect(items[0].contents.first?.value == plain)
      #expect(items[1].contents.first?.value == rtf)
      try emit([
        "case": "decorators", "count": count, "construction_ms": constructionMs,
        "selected_rtf_preview_ms": previewMs, "resident_before": before.resident,
        "resident_after": afterConstruction.resident, "footprint_before": before.footprint,
        "footprint_after": afterConstruction.footprint,
        "preview_utf8_bytes": preview.utf8.count, "plain_bytes": plain.count, "rtf_bytes": rtf.count
      ])
    }

  }
}

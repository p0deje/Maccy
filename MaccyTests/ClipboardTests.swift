import AppKit
import Testing
import Defaults
import SwiftData
@testable import Maccy

private actor OCRTestGate {
  private var started = false
  private var resultWaiters: [CheckedContinuation<HistoryItem.OCRResult, Never>] = []
  private var completedResult: HistoryItem.OCRResult?
  private(set) var invocationCount = 0

  func recognize(imageData: Data?, fileURL: URL?) async -> HistoryItem.OCRResult {
    invocationCount += 1
    started = true
    if let completedResult {
      return completedResult
    }

    return await withCheckedContinuation { resultWaiters.append($0) }
  }

  func waitUntilStarted() async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while !started && clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    return started
  }

  func complete(with result: HistoryItem.OCRResult) {
    // Keep the result for callers scheduled after completion as well. If task
    // deduplication regresses, those callers must fail the count assertion, not hang.
    completedResult = result
    let waiters = resultWaiters
    resultWaiters.removeAll()
    waiters.forEach { $0.resume(returning: result) }
  }
}

private actor OCRCallCounter {
  private(set) var count = 0

  func increment() {
    count += 1
  }
}

extension SharedStateTests {
  // swiftlint:disable type_body_length
  @MainActor
  final class ClipboardTests {
    let clipboard = Clipboard.shared
    let pasteboard = NSPasteboard.general
    let image: NSImage
    let coloredString = NSAttributedString(string: "foo",
                                           attributes: [.foregroundColor: NSColor.red])

    let dynamicType = NSPasteboard.PasteboardType(rawValue: "dyn.ah62d4qmxhk4d425try1g44pdsm11g55gsu1e82xnqzv")
    let customType = NSPasteboard.PasteboardType(rawValue: "org.maccy.ConfidentialType")
    let fileURLType = NSPasteboard.PasteboardType.fileURL
    let htmlType = NSPasteboard.PasteboardType.html
    let rtfType = NSPasteboard.PasteboardType.rtf
    let stringType = NSPasteboard.PasteboardType.string
    let tiffType = NSPasteboard.PasteboardType.tiff
    let transientType = NSPasteboard.PasteboardType.transient
    let unknownType = NSPasteboard.PasteboardType(rawValue: "com.apple.AnnotationKit.AnnotationItem")

    let savedEnabledTypes = Defaults[.enabledPasteboardTypes]
    let savedIgnoreEvents = Defaults[.ignoreEvents]
    let savedIgnoreAllAppsExceptListed = Defaults[.ignoreAllAppsExceptListed]
    let savedIgnoredApps = Defaults[.ignoredApps]
    let savedIgnoredPasteboardTypes = Defaults[.ignoredPasteboardTypes]

    init() throws {
      image = try #require(NSImage(named: "NSInfo"))
      Defaults[.ignoreAllAppsExceptListed] = false
      Defaults[.ignoreEvents] = false
      clipboard.clearHooks()
    }

    deinit {
      Defaults[.enabledPasteboardTypes] = savedEnabledTypes
      Defaults[.ignoreEvents] = savedIgnoreEvents
      Defaults[.ignoreOnlyNextEvent] = false
      Defaults[.ignoreAllAppsExceptListed] = savedIgnoreAllAppsExceptListed
      Defaults[.ignoredApps] = savedIgnoredApps
      Defaults[.ignoredPasteboardTypes] = savedIgnoredPasteboardTypes
    }

    @Test("Changes listener and add hooks")
    func changesListenerAndAddHooks() async throws {
      let copies = try await waitForCopies(after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("bar", forType: .string)
      })
      #expect(copies.count == 1)
    }

    @Test("Ignore string with only spaces")
    func ignoreStringWithOnlySpaces() async throws {
      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(" ", forType: .string)
      })
      #expect(copies.isEmpty)
    }

    @Test("Ignore string with only newlines")
    func ignoreStringWithOnlyNewlines() async throws {
      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("\n", forType: .string)
      })
      #expect(copies.isEmpty)
    }

    @Test("Does not ignore RTF")
    func doesNotIgnoreRTF() async throws {
      let copies = try await waitForCopies(after: {
        let rtf = NSAttributedString(string: "foo").rtf(
          from: NSRange(0...2),
          documentAttributes: [:]
        )
        pasteboard.declareTypes([.rtf], owner: nil)
        pasteboard.setData(rtf, forType: .rtf)
      })
      #expect(copies.count == 1)
    }

    @Test("Does not ignore HTML")
    func doesNotIgnoreHTML() async throws {
      let copies = try await waitForCopies(after: {
        pasteboard.declareTypes([.html], owner: nil)
        pasteboard.setString("foo", forType: .html)
      })
      #expect(copies.count == 1)
    }

    @Test("Ignore events is enabled")
    func ignoreEventsIsEnabled() async throws {
      Defaults[.ignoreEvents] = true

      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("foo", forType: .string)
      })
      #expect(copies.isEmpty)
    }

    @Test("Ignore only next event is enabled")
    func ignoreOnlyNextEventIsEnabled() async throws {
      Defaults[.ignoreEvents] = true
      Defaults[.ignoreOnlyNextEvent] = true

      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("foo", forType: .string)
      })
      #expect(copies.isEmpty)

      #expect(!Defaults[.ignoreEvents])
      #expect(!Defaults[.ignoreOnlyNextEvent])
    }

    @Test("Ignore application")
    func ignoreApplication() async throws {
      Defaults[.ignoredApps] = [try frontmostAppBundleIdentifier()]

      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("bar", forType: .string)
      })
      #expect(copies.isEmpty)
    }

    @Test("Ignore all applications except")
    func ignoreAllApplicationsExcept() async throws {
      Defaults[.ignoreAllAppsExceptListed] = true
      Defaults[.ignoredApps] = [try frontmostAppBundleIdentifier()]

      let copies = try await waitForCopies(after: {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("bar", forType: .string)
      })
      #expect(copies.count == 1)
    }

    @Test("Ignore transient types")
    func ignoreTransientTypes() async throws {
      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string, transientType], owner: nil)
        pasteboard.setString("bar", forType: .string)
      })
      #expect(copies.isEmpty)
    }

    @Test("Ignore custom types")
    func ignoreCustomTypes() async throws {
      Defaults[.ignoredPasteboardTypes] = [customType.rawValue]

      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([.string, customType], owner: nil)
        pasteboard.setString("bar", forType: .string)
      })
      #expect(copies.isEmpty)
    }

    @Test("Ignore copies with unknown types")
    func ignoreCopiesWithUnknownTypes() async throws {
      let copies = try await waitForCopies(expectingCopy: false, after: {
        pasteboard.declareTypes([unknownType], owner: nil)
        pasteboard.setString(" ", forType: unknownType)
      })
      #expect(copies.isEmpty)
    }

    @Test("Copy")
    func copy() async {
      let imageData = image.tiffRepresentation!
      let contents = [
        HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
        HistoryItemContent(type: tiffType.rawValue, value: imageData),
        HistoryItemContent(type: fileURLType.rawValue, value: "file://foo.bar".data(using: .utf8)!)
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.application = "com.foo.bar"
      await clipboard.copy(item)
      #expect(pasteboard.string(forType: .string) == "foo")
      #expect(pasteboard.data(forType: .tiff) == imageData)
      #expect(pasteboard.string(forType: .fileURL) == "file://foo.bar")
      #expect(pasteboard.string(forType: .fromMaccy) == "")
      #expect(pasteboard.string(forType: .source) == "com.foo.bar")
    }

    @Test("Copy string")
    func copyString() {
      clipboard.copyInMaccy("foo")
      #expect(pasteboard.string(forType: .string) == "foo")
      #expect(pasteboard.string(forType: .source) == NSPasteboard.PasteboardType.fromMaccy.rawValue)
    }

    @Test("Copy without formatting")
    func copyWithoutFormatting() async {
      let contents = [
        HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
        HistoryItemContent(type: fileURLType.rawValue, value: "file://foo.bar".data(using: .utf8)!),
        HistoryItemContent(type: rtfType.rawValue,
                           value: coloredString.rtf(from: NSRange(location: 0, length: coloredString.length),
                                                    documentAttributes: [:]))
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.application = "com.foo.bar"
      await clipboard.copy(item, removeFormatting: true)
      #expect(pasteboard.string(forType: .string) == "foo")
      #expect(pasteboard.string(forType: .fromMaccy) == "")
      #expect(pasteboard.string(forType: .source) == "com.foo.bar")
      #expect(pasteboard.string(forType: .fileURL) == "file://foo.bar")
      #expect(pasteboard.data(forType: .rtf) == nil)
    }

    @Test("Copy without formatting image with OCR")
    func copyWithoutFormattingImageWithOCR() async {
      let imageData = image.tiffRepresentation!
      let contents = [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.title = "Recognized Text from Image"
      item.application = "com.apple.screencapture"

      await clipboard.copy(item, removeFormatting: true)

      #expect(pasteboard.string(forType: .string) == "Recognized Text from Image")
      #expect(pasteboard.string(forType: .fromMaccy) == "")
      #expect(pasteboard.string(forType: .source) == "com.apple.screencapture")
      #expect(pasteboard.data(forType: .tiff) == nil)
    }

    @Test("Copy without formatting replaces file URL with OCR text when item also has image data")
    func copyWithoutFormattingReplacesFileURLWithOCRTextWhenItemAlsoHasImageData() async {
      let imageData = image.tiffRepresentation!
      let fileURL = "file:///tmp/image.jpg"
      let contents = [
        HistoryItemContent(type: tiffType.rawValue, value: imageData),
        HistoryItemContent(type: fileURLType.rawValue, value: fileURL.data(using: .utf8)!)
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.title = "Recognized Text from Image"

      await clipboard.copy(item, removeFormatting: true)

      #expect(pasteboard.string(forType: .string) == "Recognized Text from Image")
      #expect(pasteboard.string(forType: .fileURL) == nil)
      #expect(pasteboard.data(forType: .tiff) == nil)
    }

    @Test("Copy without formatting preserves existing string representation even when item has image data")
    func copyWithoutFormattingPreservesExistingStringWhenItemAlsoHasImageData() async {
      let imageData = image.tiffRepresentation!
      let originalText = "Original Cell Text\t123"
      let contents = [
        HistoryItemContent(type: tiffType.rawValue, value: imageData),
        HistoryItemContent(type: stringType.rawValue, value: originalText.data(using: .utf8)!)
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.title = "Some OCR Text"

      await clipboard.copy(item, removeFormatting: true)

      #expect(pasteboard.string(forType: .string) == originalText)
      #expect(pasteboard.data(forType: .tiff) == nil)
    }

    @Test("A real image file is recognized through the supported Universal Clipboard source",
          arguments: ["jpeg", "png", "tiff"])
    func copyWithoutFormattingRealImageFile(pathExtension: String) async throws {
      let expectedText = "Hello Maccy"
      let bitmap = try textBitmap(expectedText)
      let formats: [String: NSBitmapImageRep.FileType] = ["jpeg": .jpeg, "png": .png, "tiff": .tiff]
      let format = try #require(formats[pathExtension])
      let data = try #require(bitmap.representation(using: format, properties: [:]))
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension(pathExtension)
      try data.write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }

      // No raw image data or cached title: JPEG must actually be read by Vision.
      let item = HistoryItem(contents: [
        HistoryItemContent(type: fileURLType.rawValue, value: url.dataRepresentation),
        HistoryItemContent(type: NSPasteboard.PasteboardType.universalClipboard.rawValue, value: Data())
      ])
      Storage.shared.context.insert(item)
      #expect(await clipboard.copy(item, removeFormatting: true))

      if pathExtension == "jpeg" {
        #expect(item.ocrCompleted)
        #expect(item.title == expectedText)
        #expect(pasteboard.string(forType: .string) == expectedText)
        #expect(pasteboard.string(forType: .fileURL) == nil)
      } else {
        // These formats need raw image data; a file URL alone stays a file.
        #expect(!item.ocrCompleted)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.string(forType: .fileURL) == url.absoluteString)
      }
      #expect(pasteboard.data(forType: .tiff) == nil)
      #expect(pasteboard.data(forType: .png) == nil)
    }

    @Test("Screenshot clipboard representations survive normal copy and paste recognized text",
          arguments: [["png"], ["tiff"], ["png", "tiff"], ["tiff", "png"]])
    func screenshotClipboardRepresentations(formats: [String]) async throws {
      let expectedText = "Hello Maccy"
      let bitmap = try textBitmap(expectedText)
      let monitoredClipboard = Clipboard()
      var captured: HistoryItem?
      monitoredClipboard.onNewCopy { item in
        Storage.shared.context.insert(item)
        captured = item
      }
      defer { monitoredClipboard.clearHooks() }
      let screenshot = NSPasteboardItem()
      var expectedData: [NSPasteboard.PasteboardType: Data] = [:]
      for format in formats {
        let type: NSPasteboard.PasteboardType = format == "png" ? .png : .tiff
        let encoding: NSBitmapImageRep.FileType = format == "png" ? .png : .tiff
        let data = try #require(bitmap.representation(using: encoding, properties: [:]))
        screenshot.setData(data, forType: type)
        expectedData[type] = data
      }
      pasteboard.clearContents()
      pasteboard.writeObjects([screenshot])
      monitoredClipboard.checkForChangesInPasteboard()
      let item = try #require(captured)

      #expect(await monitoredClipboard.copy(item))
      for (type, data) in expectedData {
        #expect(pasteboard.data(forType: type) == data)
      }
      #expect(await monitoredClipboard.copy(item, removeFormatting: true))
      #expect(item.ocrCompleted)
      #expect(pasteboard.string(forType: .string) == expectedText)
      #expect(pasteboard.data(forType: .png) == nil)
      #expect(pasteboard.data(forType: .tiff) == nil)
      #expect(pasteboard.string(forType: .fileURL) == nil)
    }

    private func textBitmap(_ value: String) throws -> NSBitmapImageRep {
      let text = NSAttributedString(string: value, attributes: [
        .font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.black
      ])
      let fixture = NSImage(size: NSSize(width: 400, height: 100), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        text.draw(at: NSPoint(x: 20, y: 20))
        return true
      }
      let tiff = try #require(fixture.tiffRepresentation)
      return try #require(NSBitmapImageRep(data: tiff))
    }

    @Test("File-backed OCR checks the supported source without reading the file first",
          arguments: [false, true], [false, true])
    func fileBackedOCRSource(universalClipboard: Bool, cachedText: Bool) async {
      for pathExtension in ["jpeg", "mp3"] {
        // Deliberately missing: cached OCR must work without reopening the image,
        // while an uncached read failure must preserve the original file URL.
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).\(pathExtension)")
        var contents = [HistoryItemContent(type: fileURLType.rawValue, value: url.dataRepresentation)]
        if universalClipboard {
          contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.universalClipboard.rawValue,
                                             value: Data()))
        }
        let item = HistoryItem(contents: contents)
        Storage.shared.context.insert(item)
        item.title = cachedText ? "Previously recognized text" : ""
        let eligible = universalClipboard && pathExtension == "jpeg"
        #expect(item.hasOCRImageSource == eligible)

        await clipboard.copy(item, removeFormatting: true)

        if eligible && cachedText {
          #expect(pasteboard.string(forType: .string) == "Previously recognized text")
          #expect(pasteboard.string(forType: .fileURL) == nil)
        } else {
          #expect(pasteboard.string(forType: .string) == nil)
          #expect(pasteboard.string(forType: .fileURL) == url.absoluteString)
        }
        #expect(!item.ocrCompleted)
        #expect(item.ocrTask == nil)
      }
    }

    @Test("OCR without text is complete, while failures can be retried")
    func ocrWithoutTextIsCompleteAndFailuresCanBeRetried() async {
      let imageData = image.tiffRepresentation!
      let noTextItem = HistoryItem(contents: [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ])
      Storage.shared.context.insert(noTextItem)
      let noTextCalls = OCRCallCounter()
      noTextItem.ocrRecognizerOverride = { _, _ in
        await noTextCalls.increment()
        return .noText
      }

      #expect(await noTextItem.getRecognizedText() == nil)
      #expect(noTextItem.ocrCompleted)
      #expect(await noTextItem.getRecognizedText() == nil)
      #expect(await noTextCalls.count == 1)

      let failedItem = HistoryItem(contents: [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ])
      Storage.shared.context.insert(failedItem)
      let failedCalls = OCRCallCounter()
      failedItem.ocrRecognizerOverride = { _, _ in
        await failedCalls.increment()
        return .failed
      }

      #expect(await failedItem.getRecognizedText() == nil)
      #expect(!failedItem.ocrCompleted)
      #expect(failedItem.ocrTask == nil)

      failedItem.ocrRecognizerOverride = { _, _ in
        await failedCalls.increment()
        return .text("Retry succeeded")
      }
      #expect(await failedItem.getRecognizedText() == "Retry succeeded")
      #expect(failedItem.ocrCompleted)
      #expect(await failedCalls.count == 2)
    }

    @Test("Paste without formatting waits for in-flight OCR and copies its text")
    func pasteWithoutFormattingWaitsForInflightOCRAndCopiesItsText() async {
      let imageData = image.tiffRepresentation!
      let fileURL = "file:///tmp/ocr-image.jpg"
      let item = HistoryItem(contents: [
        HistoryItemContent(type: tiffType.rawValue, value: imageData),
        HistoryItemContent(type: fileURLType.rawValue, value: fileURL.data(using: .utf8)!)
      ])
      Storage.shared.context.insert(item)

      let gate = OCRTestGate()
      item.ocrRecognizerOverride = { imageData, fileURL in
        await gate.recognize(imageData: imageData, fileURL: fileURL)
      }

      pasteboard.clearContents()
      pasteboard.setString("Previous clipboard contents", forType: .string)
      let copyTask = Task {
        await clipboard.copy(item, removeFormatting: true)
      }

      #expect(await gate.waitUntilStarted())
      #expect(pasteboard.string(forType: .string) == "Previous clipboard contents")
      #expect(await gate.invocationCount == 1)

      await gate.complete(with: .text("Delayed OCR result"))
      #expect(await copyTask.value)

      #expect(pasteboard.string(forType: .string) == "Delayed OCR result")
      #expect(pasteboard.data(forType: .tiff) == nil)
      #expect(pasteboard.string(forType: .fileURL) == nil)
      #expect(item.ocrCompleted)
    }

    @Test("Concurrent OCR requests for one item reuse the same task")
    func concurrentOCRRequestsForOneItemReuseTheSameTask() async {
      let imageData = image.tiffRepresentation!
      let item = HistoryItem(contents: [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ])
      Storage.shared.context.insert(item)

      let gate = OCRTestGate()
      item.ocrRecognizerOverride = { imageData, fileURL in
        await gate.recognize(imageData: imageData, fileURL: fileURL)
      }

      let firstTask = item.runOCRTask(imageData: imageData, fileURL: nil)
      #expect(await gate.waitUntilStarted())
      let secondTask = item.runOCRTask(imageData: imageData, fileURL: nil)
      #expect(firstTask == secondTask)
      #expect(await gate.invocationCount == 1)

      await gate.complete(with: .text("One shared OCR result"))
      #expect(await firstTask.value == "One shared OCR result")
      #expect(await secondTask.value == "One shared OCR result")
      #expect(await gate.invocationCount == 1)
      #expect(item.title == "One shared OCR result")
      #expect(item.ocrCompleted)
    }

    @Test("External copy during OCR is kept and saved while the old paste is cancelled",
          arguments: [false, true], [HistoryItem.OCRResult.text("Recognized text from A"), .noText, .failed])
    func externalCopyDuringOCRIsSavedBeforePendingPaste(
      pollBeforeOCRCompletes: Bool,
      ocrResult: HistoryItem.OCRResult
    ) async throws {
      let imageData = image.tiffRepresentation!
      let item = HistoryItem(contents: [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ])
      Storage.shared.context.insert(item)
      let gate = OCRTestGate()
      item.ocrRecognizerOverride = { imageData, fileURL in
        await gate.recognize(imageData: imageData, fileURL: fileURL)
      }

      pasteboard.clearContents()
      pasteboard.setString("Clipboard before pending OCR", forType: .string)
      // No timer: the two parameters control whether B is observed before OCR finishes.
      let monitoredClipboard = Clipboard()
      let history = History()
      monitoredClipboard.onNewCopy { history.add($0) }
      defer { monitoredClipboard.clearHooks() }

      let copyTask = Task {
        await monitoredClipboard.copy(item, removeFormatting: true)
      }
      let started = await gate.waitUntilStarted()
      if !started {
        await gate.complete(with: .failed)
        _ = await copyTask.value
        #expect(started)
        return
      }

      let copiedB = "External B \(UUID().uuidString)"
      let imageB = try #require(NSImage(named: "NSBluetoothTemplate"))
      let imageBData = try #require(imageB.tiffRepresentation)
      let fileURLB = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).tiff")
      pasteboard.clearContents()
      pasteboard.setString(copiedB, forType: .string)
      pasteboard.setData(imageBData, forType: .tiff)
      pasteboard.setString(fileURLB.absoluteString, forType: .fileURL)
      if pollBeforeOCRCompletes {
        monitoredClipboard.checkForChangesInPasteboard()
      }

      await gate.complete(with: ocrResult)
      let didCopyA = await copyTask.value

      let verificationContext = ModelContext(Storage.shared.container)
      let persistedItems = try verificationContext.fetch(FetchDescriptor<HistoryItem>())
      let storedB = try #require(persistedItems.first { $0.text == copiedB })
      #expect(!didCopyA)
      #expect(storedB.imageData == imageBData)
      #expect(storedB.fileURLs == [fileURLB])
      #expect(pasteboard.string(forType: .string) == copiedB)
      #expect(pasteboard.data(forType: .tiff) == imageBData)
      #expect(pasteboard.string(forType: .fileURL) == fileURLB.absoluteString)

      monitoredClipboard.checkForChangesInPasteboard()
      #expect(history.items.toArray().filter { $0.item.text == copiedB }.count == 1)
    }

    @Test("The newer OCR copy request wins regardless of completion order", arguments: [false, true])
    func newerOCRCopyRequestWins(olderCompletesFirst: Bool) async {
      let imageData = image.tiffRepresentation!
      let firstItem = HistoryItem(contents: [HistoryItemContent(type: tiffType.rawValue, value: imageData)])
      let secondItem = HistoryItem(contents: [HistoryItemContent(type: tiffType.rawValue, value: imageData)])
      Storage.shared.context.insert(firstItem)
      Storage.shared.context.insert(secondItem)
      let firstGate = OCRTestGate()
      let secondGate = OCRTestGate()
      firstItem.ocrRecognizerOverride = { imageData, fileURL in
        await firstGate.recognize(imageData: imageData, fileURL: fileURL)
      }
      secondItem.ocrRecognizerOverride = { imageData, fileURL in
        await secondGate.recognize(imageData: imageData, fileURL: fileURL)
      }

      pasteboard.clearContents()
      pasteboard.setString("Previous clipboard contents", forType: .string)
      let monitoredClipboard = Clipboard()
      let firstCopy = Task { await monitoredClipboard.copy(firstItem, removeFormatting: true) }
      #expect(await firstGate.waitUntilStarted())
      let secondCopy = Task { await monitoredClipboard.copy(secondItem, removeFormatting: true) }
      #expect(await secondGate.waitUntilStarted())

      if olderCompletesFirst {
        await firstGate.complete(with: .text("Older request"))
        #expect(await firstCopy.value == false)
        #expect(pasteboard.string(forType: .string) == "Previous clipboard contents")
        await secondGate.complete(with: .text("Newer request"))
      } else {
        await secondGate.complete(with: .text("Newer request"))
        #expect(await secondCopy.value)
        await firstGate.complete(with: .text("Older request"))
      }

      #expect(await firstCopy.value == false)
      #expect(await secondCopy.value)
      #expect(pasteboard.string(forType: .string) == "Newer request")
    }

    @Test("Invalid image data causes a retryable Vision failure")
    func invalidImageDataCausesRetryableVisionFailure() async {
      let item = HistoryItem(contents: [
        HistoryItemContent(type: tiffType.rawValue, value: Data("not an image".utf8))
      ])
      Storage.shared.context.insert(item)

      #expect(await item.getRecognizedText() == nil)
      #expect(!item.ocrCompleted)
      #expect(item.ocrTask == nil)
    }

    @Test("Copy image preserves image when not removing formatting")
    func copyImagePreservesImageWhenNotRemovingFormatting() async {
      let imageData = image.tiffRepresentation!
      let contents = [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.title = "Recognized Text from Image"

      await clipboard.copy(item, removeFormatting: false)

      #expect(pasteboard.data(forType: .tiff) == imageData)
    }

    @Test("Copy without formatting image without OCR text falls back to image")
    func copyWithoutFormattingImageWithoutOCRTextFallsBackToImage() async {
      let blankImage = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
        NSColor.black.setFill()
        rect.fill()
        return true
      }
      let imageData = blankImage.tiffRepresentation!
      let contents = [
        HistoryItemContent(type: tiffType.rawValue, value: imageData)
      ]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.title = ""

      await clipboard.copy(item, removeFormatting: true)

      #expect(pasteboard.data(forType: .tiff) == imageData)
      #expect(item.ocrCompleted)
    }

    @Test("Handles items without data")
    func handlesItemsWithoutData() async throws {
      pasteboard.clearContents()

      let copies = try await waitForCopies(after: {
        pasteboard.declareTypes([.fileURL, .string], owner: nil)
        // fileURL is left without data
        pasteboard.setString("bar", forType: .string)
      })
      #expect(copies.count == 1)
    }

    @Test("Merges multiple items")
    func mergesMultipleItems() async throws {
      let item1 = NSPasteboardItem()
      item1.setString("foo", forType: .string)
      let item2 = NSPasteboardItem()
      item2.setData(image.tiffRepresentation!, forType: .tiff)

      let copies = try await waitForCopies(after: {
        pasteboard.clearContents()
        pasteboard.writeObjects([item1, item2])
      })
      let copied = try #require(copies.first)
      #expect(copies.count == 1)
      #expect(
        Set(copied.contents.map({ $0.type })) ==
        Set([tiffType.rawValue, stringType.rawValue])
      )
    }

    @Test("Removes disabled types")
    func removesDisabledTypes() async throws {
      Defaults[.enabledPasteboardTypes] = [.fileURL]

      let item = NSPasteboardItem()
      item.setString("foo", forType: .string)
      item.setData(image.tiffRepresentation!, forType: .tiff)
      item.setData("file://foo.bar".data(using: .utf8)!, forType: .fileURL)

      let copies = try await waitForCopies(after: {
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
      })
      let copied = try #require(copies.first)
      #expect(copies.count == 1)
      #expect(copied.contents.map({ $0.type }) == [fileURLType.rawValue])
    }

    @Test("Removes dynamic types")
    func removesDynamicTypes() async throws {
      let item = NSPasteboardItem()
      item.setString("foo", forType: .string)
      item.setData("".data(using: .utf8)!, forType: dynamicType)

      let copies = try await waitForCopies(after: {
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
      })
      let copied = try #require(copies.first)
      #expect(copies.count == 1)
      #expect(copied.contents.map({ $0.type }) == [stringType.rawValue])
    }

    @Test("Does not store Safari web archive")
    func doesNotStoreSafariWebArchive() async throws {
      let webArchive = NSPasteboard.PasteboardType.safariWebArchve

      let item = NSPasteboardItem()
      item.setString("hello from safari", forType: .string)
      item.setData(Data(repeating: 0x61, count: 1024 * 1024), forType: webArchive)

      let copies = try await waitForCopies(after: {
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
      })
      let copied = try #require(copies.first)
      #expect(copies.count == 1)
      #expect(Set(copied.contents.map(\.type)) == [stringType.rawValue])
    }

    private func waitForCopies(expectingCopy: Bool = true, after trigger: () -> Void) async throws -> [HistoryItem] {
      var copies: [HistoryItem] = []
      clipboard.onNewCopy { copies.append($0) }
      clipboard.start()
      trigger()
      let deadline = ContinuousClock.now + .seconds(2)
      while (!expectingCopy || copies.isEmpty) && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
      }
      return copies
    }

    private func frontmostAppBundleIdentifier() throws -> String {
      guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
        try Test.cancel("No frontmost application to attribute a copy to")
      }

      return bundleIdentifier
    }
  }
  // swiftlint:enable type_body_length
}

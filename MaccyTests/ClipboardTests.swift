import XCTest
@testable import Maccy

class ClipboardTests: XCTestCase {
  let clipboard = Clipboard()
  let pasteboard = NSPasteboard.general
  let image = NSImage(named: "NSInfo")!
  let coloredString = NSAttributedString(string: "foo",
                                         attributes: [NSAttributedString.Key.foregroundColor: NSColor.red])

  let dynamicType = NSPasteboard.PasteboardType(rawValue: "dyn.ah62d4qmxhk4d425try1g44pdsm11g55gsu1e82xnqzv")
  let customType = NSPasteboard.PasteboardType(rawValue: "org.maccy.ConfidentialType")
  let fileURLType = NSPasteboard.PasteboardType.fileURL
  let rtfType = NSPasteboard.PasteboardType.rtf
  let stringType = NSPasteboard.PasteboardType.string
  let tiffType = NSPasteboard.PasteboardType.tiff
  let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")
  let unknownType = NSPasteboard.PasteboardType(rawValue: "com.apple.AnnotationKit.AnnotationItem")

  let savedEnabledTypes = UserDefaults.standard.enabledPasteboardTypes
  let savedIgnoreEvents = UserDefaults.standard.ignoreEvents
  let savedIgnoredApps = UserDefaults.standard.ignoredApps
  let savedIgnoredPasteboardTypes = UserDefaults.standard.ignoredPasteboardTypes

  override func setUp() {
    super.setUp()
    CoreDataManager.inMemory = true
    UserDefaults.standard.ignoreEvents = false
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.enabledPasteboardTypes = savedEnabledTypes
    UserDefaults.standard.ignoreEvents = savedIgnoreEvents
    UserDefaults.standard.ignoreOnlyNextEvent = false
    UserDefaults.standard.ignoredApps = savedIgnoredApps
    UserDefaults.standard.ignoredPasteboardTypes = savedIgnoredPasteboardTypes
    clipboard.onNewCopyHooks = []
  }

  func testChangesListenerAndAddHooks() {
    let hookExpectation = expectation(description: "Hook is called")
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string], owner: nil)
    pasteboard.setString("bar", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreStringWithOnlySpaces() {
    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string, transientType], owner: nil)
    pasteboard.setString(" ", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreStringWithOnlyNewlines() {
    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string, transientType], owner: nil)
    pasteboard.setString("\n", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreEventsIsEnabled() {
    UserDefaults.standard.ignoreEvents = true

    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string, transientType], owner: nil)
    pasteboard.setString("foo", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreOnlyNextEventIsEnabled() {
    UserDefaults.standard.ignoreEvents = true
    UserDefaults.standard.ignoreOnlyNextEvent = true

    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string, transientType], owner: nil)
    pasteboard.setString("foo", forType: .string)
    waitForExpectations(timeout: 2)

    XCTAssertFalse(UserDefaults.standard.ignoreEvents)
    XCTAssertFalse(UserDefaults.standard.ignoreOnlyNextEvent)
  }

  func testIgnoreApplication() {
    UserDefaults.standard.ignoredApps = ["com.apple.dt.Xcode", "com.apple.finder"] // Finder is on Bitrise

    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string], owner: nil)
    pasteboard.setString("bar", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreTransientTypes() {
    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string, transientType], owner: nil)
    pasteboard.setString("bar", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreCustomTypes() {
    UserDefaults.standard.ignoredPasteboardTypes = [customType.rawValue]

    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.string, customType], owner: nil)
    pasteboard.setString("bar", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testIgnoreCopiesWithUnknownTypes() {
    let hookExpectation = expectation(description: "Hook is called")
    hookExpectation.isInverted = true
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([unknownType], owner: nil)
    pasteboard.setString(" ", forType: unknownType)
    waitForExpectations(timeout: 2)
  }

  func testCopy() {
    let imageData = image.tiffRepresentation!
    let item = HistoryItem(contents: [
      HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
      HistoryItemContent(type: tiffType.rawValue, value: imageData),
      HistoryItemContent(type: fileURLType.rawValue, value: "file://foo.bar".data(using: .utf8)!)
    ])
    clipboard.copy(item)
    XCTAssertEqual(pasteboard.string(forType: .string), "foo")
    XCTAssertEqual(pasteboard.data(forType: .tiff), imageData)
    XCTAssertEqual(pasteboard.string(forType: .fileURL), "file://foo.bar")
  }

  func testCopyWithoutFormatting() {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
      HistoryItemContent(type: rtfType.rawValue,
                         value: coloredString.rtf(from: NSRange(location: 0, length: coloredString.length),
                                                  documentAttributes: [:]))
    ])
    clipboard.copy(item, removeFormatting: true)
    XCTAssertEqual(pasteboard.string(forType: .string), "foo")
    XCTAssertNil(pasteboard.data(forType: .rtf))
  }

  func testHandlesItemsWithoutData() {
    let hookExpectation = expectation(description: "Hook is called")
    pasteboard.clearContents()
    clipboard.onNewCopy({ (_: HistoryItem) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()
    pasteboard.declareTypes([.fileURL, .string], owner: nil)
    // fileURL is left without data
    pasteboard.setString("bar", forType: .string)
    waitForExpectations(timeout: 2)
  }

  func testRemovesDisabledTypes() {
    UserDefaults.standard.enabledPasteboardTypes = [.fileURL]

    let hookExpectation = expectation(description: "Hook is called")
    clipboard.onNewCopy({ (item: HistoryItem) -> Void in
      XCTAssertEqual(item.getContents().map({ $0.type }), [self.fileURLType.rawValue])
      hookExpectation.fulfill()
    })

    let item = NSPasteboardItem()
    item.setString("foo", forType: .string)
    item.setData(image.tiffRepresentation!, forType: .tiff)
    item.setData("file://foo.bar".data(using: .utf8)!, forType: .fileURL)

    clipboard.startListening()
    pasteboard.clearContents()
    pasteboard.writeObjects([item])

    waitForExpectations(timeout: 2)
  }

  func testRemovesDynamicTypes() {
    let hookExpectation = expectation(description: "Hook is called")
    clipboard.onNewCopy({ (item: HistoryItem) -> Void in
      XCTAssertEqual(item.getContents().map({ $0.type }), [self.stringType.rawValue])
      hookExpectation.fulfill()
    })

    let item = NSPasteboardItem()
    item.setString("foo", forType: .string)
    item.setData("".data(using: .utf8)!, forType: dynamicType)

    clipboard.startListening()
    pasteboard.clearContents()
    pasteboard.writeObjects([item])

    waitForExpectations(timeout: 2)
  }
}

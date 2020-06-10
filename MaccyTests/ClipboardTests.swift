import XCTest
@testable import Maccy

class ClipboardTests: XCTestCase {
  let clipboard = Clipboard()
  let pasteboard = NSPasteboard.general
  let image = NSImage(named: "NSInfo")!

  let customType = NSPasteboard.PasteboardType(rawValue: "org.maccy.ConfidentialType")
  let fileURLType = NSPasteboard.PasteboardType.fileURL
  let tiffType = NSPasteboard.PasteboardType.tiff
  let stringType = NSPasteboard.PasteboardType.string
  let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")
  let unknownType = NSPasteboard.PasteboardType(rawValue: "com.apple.AnnotationKit.AnnotationItem")

  let savedIgnoreEvents = UserDefaults.standard.ignoreEvents
  let savedIgnoredPasteboardTypes = UserDefaults.standard.ignoredPasteboardTypes

  override func setUp() {
    super.setUp()
    CoreDataManager.inMemory = true
    UserDefaults.standard.ignoreEvents = false
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.ignoreEvents = savedIgnoreEvents
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

  func testIgnoreCopiesWithUknownTypes() {
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
}

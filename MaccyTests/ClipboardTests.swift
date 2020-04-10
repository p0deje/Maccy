import XCTest
@testable import Maccy

class ClipboardTests: XCTestCase {
  let clipboard = Clipboard()
  let pasteboard = NSPasteboard.general
  let image = NSImage(named: "NSInfo")!

  let tiffType = NSPasteboard.PasteboardType.tiff
  let stringType = NSPasteboard.PasteboardType.string
  let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")

  let savedIgnoreEvents = UserDefaults.standard.ignoreEvents

  override func setUp() {
    super.setUp()
    CoreDataManager.inMemory = true
    UserDefaults.standard.ignoreEvents = false
  }

  override func tearDown() {
    super.setUp()
    CoreDataManager.inMemory = false
    UserDefaults.standard.ignoreEvents = savedIgnoreEvents
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

  func testCopy() {
    let imageData = image.tiffRepresentation!
    let item = HistoryItem(contents: [
      HistoryItemContent(type: stringType.rawValue, value: "foo".data(using: .utf8)!),
      HistoryItemContent(type: tiffType.rawValue, value: imageData)
    ])
    clipboard.copy(item)
    XCTAssertEqual(pasteboard.string(forType: .string), "foo")
    XCTAssertEqual(pasteboard.data(forType: .tiff), imageData)
  }
}

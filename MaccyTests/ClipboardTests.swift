import XCTest
@testable import Maccy

class ClipboardTests: XCTestCase {
  let clipboard = Clipboard()
  let pasteboard = NSPasteboard.general

  func testChangesListenerAndAddHooks() {
    let hookExpectation = expectation(description: "Hook is called")

    clipboard.onNewCopy({ (_: String) -> Void in
      hookExpectation.fulfill()
    })
    clipboard.startListening()

    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
    pasteboard.setString("bar", forType: NSPasteboard.PasteboardType.string)

    waitForExpectations(timeout: 5)
  }

  func testChangesListenerAndRemoveHooks() {
    let hookExpectation = expectation(description: "Hook is called")

    clipboard.onRemovedCopy(hookExpectation.fulfill)
    clipboard.startListening()

    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
    pasteboard.setString("bar", forType: NSPasteboard.PasteboardType.string)
    pasteboard.clearContents()

    waitForExpectations(timeout: 5)
  }

  func testCopy() {
    clipboard.copy("foo")
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "foo")
  }
}

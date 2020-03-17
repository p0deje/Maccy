import XCTest
@testable import Maccy

class ClipboardTests: XCTestCase {
  let clipboard = Clipboard()
  let pasteboard = NSPasteboard.general
  let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")

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

  func testIgnoredCopies() {
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

  func testCopyString() {
    clipboard.copy("foo".data(using: .utf8)!, .string)
    XCTAssertEqual(pasteboard.string(forType: .string), "foo")
  }

  func testCopyTiffImage() {
    let data = NSImage(named: "NSInfo")?.tiffRepresentation
    clipboard.copy(data!, .tiff)
    XCTAssertEqual(pasteboard.data(forType: .tiff), data)
  }

  func testCopyPngImage() {
    let cgImage = NSImage(named: "NSInfo")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    let imageRep = NSBitmapImageRep(cgImage: cgImage!)
    let data = imageRep.representation(using: .png, properties: [:])
    clipboard.copy(data!, .png)
    XCTAssertEqual(pasteboard.data(forType: .png), data)
  }
}

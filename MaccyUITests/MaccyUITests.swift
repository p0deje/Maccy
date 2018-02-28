import Carbon
import XCTest

class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString
  let copy3 = UUID().uuidString
  
  var popUpEvents: [CGEvent] {
    let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)!
    eventDown.flags = [CGEventFlags.maskCommand,CGEventFlags.maskShift]
    
    let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)!
    eventUp.flags = [CGEventFlags.maskCommand,CGEventFlags.maskShift]
    
    return [eventDown, eventUp]
  }
  
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app.launch()
    
    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
    copyToClipboard("foo") // the first item is not copied for some reason
    copyToClipboard(copy1)
    copyToClipboard(copy2)
    copyToClipboard(copy3)
  }

  func testSearchAndCopy() {
    popUp()
    app.typeText(copy1)
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy1)
    
    popUp()
    app.typeText(copy3)
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)

    popUp()
    app.typeText(copy2)
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)
  }
  
  func testSelectWithArrowKeysAndCopy() {
    popUp()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)
    
    popUp()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)
    
    popUp()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy1)
  }

  private func popUp() {
    for event in popUpEvents {
      event.post(tap: CGEventTapLocation.cghidEventTap)
    }
  }
  
  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: NSPasteboard.PasteboardType.string)
    sleep(2) // make sure Maccy knows about new item
  }
}

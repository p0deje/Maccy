import Carbon
import XCTest

class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString
  let copy3 = UUID().uuidString

  var statusItem: XCUIElement {
    return app.statusItems.firstMatch
  }
  
  var statusItemCoordinates: XCUICoordinate {
    return statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
  }
  
  var popUpEvents: [CGEvent] {
    let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_C), keyDown: true)!
    eventDown.flags = [.maskCommand, .maskShift]

    let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_C), keyDown: false)!
    eventUp.flags = [.maskCommand, .maskShift]

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
    popUpWithHotkey()
    app.typeText(copy1)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy1)

    popUpWithHotkey()
    app.typeText(copy3)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)

    popUpWithHotkey()
    app.typeText(copy2)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)
  }

  func testSelectWithDownArrowKeysAndCopy() {
    popUpWithHotkey()
    typeKey(.downArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)

    popUpWithHotkey()
    typeKey(.downArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)

    popUpWithHotkey()
    typeKey(.downArrow)
    typeKey(.downArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy1)

    popUpWithHotkey()
    typeKey(.downArrow, [.command])
    typeKey(.downArrow)
    typeKey(.downArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)
  }

  func testSelectWithUpArrowKeysAndCopy() {
    popUpWithHotkey()
    typeKey(.downArrow)
    typeKey(.downArrow)
    typeKey(.upArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)

    popUpWithHotkey()
    typeKey(.downArrow)
    typeKey(.downArrow)
    typeKey(.upArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)

    popUpWithHotkey()
    typeKey(.downArrow)
    typeKey(.downArrow)
    typeKey(.downArrow)
    typeKey(.upArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy1)

    popUpWithHotkey()
    typeKey(.upArrow)
    typeKey(.upArrow, [.command])
    typeKey(.downArrow)
    typeKey(.enter)
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy3)
  }

  func testCloseWithMouseAndSelectWithArrowKeys() {
    for _ in 1...2 {
      popUpWithMouse()
      typeKey(.downArrow)
      hoverTitleField()
      hideWithMouse()
    }

    popUpWithMouse()
    typeKey(.downArrow)
    typeKey(.enter)
    
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)
  }

  private func popUpWithHotkey() {
    for event in popUpEvents {
      event.post(tap: .cghidEventTap)
    }
    sleep(1) // give Maccy some time to popup
  }
  
  private func popUpWithMouse() {
    statusItem.click()
    sleep(1) // give Maccy some time to popup
  }
  
  private func hoverTitleField() {
    statusItemCoordinates.withOffset(CGVector(dx: 20, dy: 40)).hover()
  }
  
  private func hideWithMouse() {
    statusItemCoordinates.withOffset(CGVector(dx: -40, dy: 40)).click()
    sleep(1)
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: NSPasteboard.PasteboardType.string)
    sleep(3) // make sure Maccy knows about new item
  }

  private func typeKey(_ key: XCUIKeyboardKey, _ modifierFlags: XCUIElement.KeyModifierFlags = []) {
    app.typeKey(key, modifierFlags: modifierFlags)
    sleep(1) // give Maccy some time to process key
  }
}

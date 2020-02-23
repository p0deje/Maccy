import Carbon
import XCTest

class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString

  var sortBy = "lastCopiedAt"

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
    app.launchArguments.append("ui-testing")
    app.launchArguments.append(contentsOf: ["sortBy", sortBy])
    app.launch()

    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
    copyToClipboard(copy2)
    copyToClipboard(copy1)
  }

  override func tearDown() {
    super.tearDown()
    app.terminate()
  }

  func testPopupWithHotkey() {
    popUpWithHotkey()
    XCTAssertTrue(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].exists)
  }

  func testCloseWithHotkey() {
    popUpWithHotkey()
    let historyItem = app.menuItems[copy1]
    expectation(for: NSPredicate(format: "exists = 0"), evaluatedWith: historyItem)

    for event in popUpEvents {
      event.post(tap: .cghidEventTap)
    }
    waitForExpectations(timeout: 3)
  }

  func testPopupWithMenubar() {
    popUpWithMouse()
    XCTAssertTrue(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].exists)
  }

  func testSearch() {
    popUpWithHotkey()
    app.typeText(copy1)
    XCTAssertEqual(app.textFields.firstMatch.value as? String, copy1)
    XCTAssertTrue(app.menuItems[copy1].exists)
    XCTAssertFalse(app.menuItems[copy2].exists)
  }

  func testCopyWithClick() {
    popUpWithHotkey()
    app.menuItems.matching(identifier: copy2).firstMatch.click()
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyWithEnter() {
    popUpWithHotkey()
    app.menuItems.matching(identifier: copy2).firstMatch.hover()
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyWithCommandShortcut() {
    popUpWithHotkey()
    app.typeKey("2", modifierFlags: [.command])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testSearchAndCopyWithCommandShortcut() {
    popUpWithHotkey()
    app.typeText(copy2)
    app.typeKey("1", modifierFlags: [.command])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testDownArrow() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCommandDownArrow() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [.command]) // "Quit"
    app.typeKey(.downArrow, modifierFlags: []) // copy1
    app.typeKey(.downArrow, modifierFlags: []) // copy2
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testUpArrow() {
    popUpWithHotkey()
    app.typeKey(.upArrow, modifierFlags: []) // "Quit"
    app.typeKey(.upArrow, modifierFlags: []) // "About"
    app.typeKey(.upArrow, modifierFlags: []) // "Clear"
    app.typeKey(.upArrow, modifierFlags: []) // "Launch at login"
    app.typeKey(.upArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)
  }

  func testCommandUpArrow() {
    popUpWithHotkey()
    app.typeKey(.upArrow, modifierFlags: []) // "Quit"
    app.typeKey(.upArrow, modifierFlags: [.command]) // copy1
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), copy2)
  }

  func testDeleteEntry() {
    popUpWithHotkey()
    app.typeKey(.delete, modifierFlags: [.option])
    XCTAssertFalse(app.menuItems[copy1].exists)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
  }

  func testDeleteEntryDuringSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    XCTAssertFalse(app.menuItems[copy2].exists)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy2].exists)
  }

  func testClear() {
    popUpWithHotkey()
    app.menuItems["Clear"].click()
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
    XCTAssertFalse(app.menuItems[copy2].exists)
  }

  func testClearDuringSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    app.menuItems["Clear"].click()
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
    XCTAssertFalse(app.menuItems[copy2].exists)
  }

  func testPin() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey("p", modifierFlags: [.option])
    XCTAssertEqual(visibleMenuItemTitles()[1...2], [copy2, copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithHotkey()
    XCTAssertEqual(visibleMenuItemTitles()[1...2], [copy2, copy1])
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
  }

  func testPinDuringSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    app.typeKey("p", modifierFlags: [.option])
    XCTAssertEqual(app.textFields.firstMatch.value as? String, "")
    XCTAssertEqual(visibleMenuItemTitles()[1...2], [copy2, copy1])
  }

  func testUnpin() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey("p", modifierFlags: [.option]) // pin
    app.typeKey("p", modifierFlags: [.option]) // unpin
    XCTAssertEqual(visibleMenuItemTitles()[1...2], [copy1, copy2])
  }

  // Temporarily disable the test as it is flaky.
  //
  // func testHideAndShowMenubarIcon() {
  //   let statusItem = app.statusItems.firstMatch
  //   let dragFrom = statusItem.coordinate(withNormalizedOffset: CGVector.zero)
  //   let dragTo = statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 10))
  //   XCUIElement.perform(withKeyModifiers: .command, block: {
  //     dragFrom.click(forDuration: 1, thenDragTo: dragTo)
  //   })
  //   expectation(for: NSPredicate(format: "isHittable = 0"), evaluatedWith: statusItem)
  //   waitForExpectations(timeout: 3)

  //   app.launch()
  //   expectation(for: NSPredicate(format: "isHittable = 1"), evaluatedWith: statusItem)
  //   waitForExpectations(timeout: 3)
  // }

  private func popUpWithHotkey() {
    for event in popUpEvents {
      event.post(tap: .cghidEventTap)
    }
    waitUntilPoppedUp()
  }

  private func popUpWithMouse() {
    app.statusItems.firstMatch.click()
    waitUntilPoppedUp()
  }

  private func waitUntilPoppedUp() {
    if !app.menuItems.firstMatch.waitForExistence(timeout: 3) {
      XCTFail("Maccy did not pop up")
    }
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: NSPasteboard.PasteboardType.string)
    usleep(1500000) // default interval for Maccy to check clipboard is 1 second
  }

  private func visibleMenuItemTitles() -> [String] {
    return app.menuItems.allElementsBoundByIndex.filter({ $0.isHittable }).map({ $0.title })
  }
}

import Carbon
import XCTest

class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString

  // https://hetima.github.io/fucking_nsimage_syntax
  let image1 = NSImage(named: "NSAddTemplate")!
  let image2 = NSImage(named: "NSBluetoothTemplate")!

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
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
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
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
    XCTAssertTrue(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].exists)
  }

  func testSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    XCTAssertEqual(app.textFields.firstMatch.value as? String, copy2)
    XCTAssertTrue(app.menuItems[copy2].exists)
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)
    XCTAssertFalse(app.menuItems[copy1].exists)
  }

  func testCopyWithClick() {
    popUpWithHotkey()
    app.menuItems[copy2].firstMatch.click()
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyWithEnter() {
    popUpWithHotkey()
    app.menuItems[copy2].firstMatch.hover()
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

  func testCopyImage() {
    copyToClipboard(image2)
    copyToClipboard(image1)
    popUpWithHotkey()
    visibleMenuItems()[2].click()
    XCTAssertEqual(pasteboard.data(forType: .tiff)!.count, image2.tiffRepresentation!.count)
  }

  func testDownArrow() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [])
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)
  }

  func testCyclingWithDownArrow() {
    popUpWithHotkey()
    app.typeKey(.upArrow, modifierFlags: [])
    app.typeKey(.downArrow, modifierFlags: [])
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
  }

  func testCommandDownArrow() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [.command])
    XCTAssertTrue(app.menuItems["Quit"].firstMatch.isSelected)
  }

  func testUpArrow() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.upArrow, modifierFlags: [])
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
  }

  func testCyclingWithUpArrow() {
    popUpWithHotkey()
    app.typeKey(.upArrow, modifierFlags: [])
    XCTAssertTrue(app.menuItems["Quit"].firstMatch.isSelected)
  }

  func testCommandUpArrow() {
    popUpWithHotkey()
    app.typeKey(.upArrow, modifierFlags: []) // "Quit"
    app.typeKey(.upArrow, modifierFlags: [.command])
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
  }

  func testDeleteEntry() {
    popUpWithHotkey()
    app.typeKey(.delete, modifierFlags: [.option])
    XCTAssertFalse(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
  }

  func testDeleteEntryDuringSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    XCTAssertFalse(app.menuItems[copy2].exists)
    XCTAssertTrue(app.menuItems["Clear"].firstMatch.isSelected)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy2].exists)
  }

  func testClear() {
    popUpWithHotkey()
    pin(copy2)
    app.menuItems["Clear"].click()
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].exists)
    for item in app.menuItems.allElementsBoundByIndex {
      XCTAssertFalse(item.isSelected)
    }
  }

  func testClearDuringSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    app.menuItems["Clear"].click()
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
    XCTAssertFalse(app.menuItems[copy2].exists)
  }

  func testClearAll() {
    popUpWithHotkey()
    pin(copy2)
    app.menuItems["Clear"].firstMatch.hover()
    app.typeKey(.enter, modifierFlags: [.option])
    popUpWithHotkey()
    XCTAssertFalse(app.menuItems[copy1].exists)
    XCTAssertFalse(app.menuItems[copy2].exists)
    for item in app.menuItems.allElementsBoundByIndex {
      XCTAssertFalse(item.isSelected)
    }
  }

  func testPin() {
    popUpWithHotkey()
    pin(copy2)
    XCTAssertEqual(visibleMenuItemTitles()[1...2], [copy2, copy1])
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)

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
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)
  }

  func testUnpin() {
    popUpWithHotkey()
    pin(copy2)
    app.typeKey("p", modifierFlags: [.option]) // unpin
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)
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
    pasteboard.setString(content, forType: .string)
    usleep(1500000) // default interval for Maccy to check clipboard is 1 second
  }

  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    usleep(1500000) // default interval for Maccy to check clipboard is 1 second
  }

  private func visibleMenuItemTitles() -> [String] {
    return visibleMenuItems().map({ $0.title })
  }

  private func visibleMenuItems() -> [XCUIElement] {
    return app.menuItems.allElementsBoundByIndex.filter({ $0.isHittable })
  }

  private func pin(_ title: String) {
    app.menuItems[title].firstMatch.hover()
    app.typeKey("p", modifierFlags: [.option])
  }
}

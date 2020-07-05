import Carbon
import XCTest

// swiftlint:disable type_body_length
class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString

  // https://hetima.github.io/fucking_nsimage_syntax
  let image1 = NSImage(named: "NSAddTemplate")!
  let image2 = NSImage(named: "NSBluetoothTemplate")!

  let file1 = URL(fileURLWithPath: "/tmp/file1")
  let file2 = URL(fileURLWithPath: "/tmp/file2")

  var sortBy = "lastCopiedAt"

  override func setUp() {
    super.setUp()
    app.launchArguments.append("ui-testing")
    app.launchArguments.append(contentsOf: ["sortBy", sortBy])
    app.launch()

    copyToClipboard(copy2)
    copyToClipboard(copy1)
  }

  override func tearDown() {
    super.tearDown()
    app.terminate()
  }

  func testPopupWithHotkey() {
    popUpWithHotkey()
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
    XCTAssertTrue(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].exists)
  }

  func testCloseWithHotkey() {
    popUpWithHotkey()
    let historyItem = app.menuItems[copy1]
    expectation(for: NSPredicate(format: "exists = 0"), evaluatedWith: historyItem)
    simulatePopupHotkey()
    waitForExpectations(timeout: 3)
  }

  func testPopupWithMenubar() {
    popUpWithMouse()
    XCTAssertTrue(app.menuItems[copy1].firstMatch.isSelected)
    XCTAssertTrue(app.menuItems[copy1].exists)
    XCTAssertTrue(app.menuItems[copy2].exists)
  }

  func testNewCopyIsAdded() {
    popUpWithHotkey()
    let copy3 = UUID().uuidString
    copyToClipboard(copy3)
    XCTAssertFalse(app.menuItems[copy3].exists)
    app.typeKey(.escape, modifierFlags: [])
    popUpWithHotkey()
    XCTAssertTrue(app.menuItems[copy3].exists)
    XCTAssertTrue(app.menuItems[copy3].firstMatch.isSelected)
  }

  func testSearch() {
    popUpWithHotkey()
    app.typeText(copy2)
    XCTAssertEqual(app.textFields.firstMatch.value as? String, copy2)
    XCTAssertTrue(app.menuItems[copy2].exists)
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)
    XCTAssertFalse(app.menuItems[copy1].exists)
  }

  func testSearchFiles() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithHotkey()
    app.typeText(file2.lastPathComponent)
    XCTAssertTrue(app.menuItems[file2.absoluteString].exists)
    XCTAssertTrue(app.menuItems[file2.absoluteString].firstMatch.isSelected)
    XCTAssertFalse(app.menuItems[file1.absoluteString].exists)
  }

  func testCopyWithClick() {
    popUpWithHotkey()
    app.menuItems[copy2].firstMatch.click()
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyWithEnter() {
    popUpWithHotkey()
    hover(app.menuItems[copy2].firstMatch)
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

  func testCopyFile() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithHotkey()
    XCTAssertEqual(visibleMenuItemTitles()[1...2], [file1.absoluteString, file2.absoluteString])

    app.menuItems[file2.absoluteString].firstMatch.click()
    XCTAssertEqual(pasteboard.string(forType: .fileURL), file2.absoluteString)
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

  func testControlN() {
    popUpWithHotkey()
    app.typeKey("n", modifierFlags: [.control])
    XCTAssertTrue(app.menuItems[copy2].firstMatch.isSelected)
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

  func testControlP() {
    popUpWithHotkey()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey("p", modifierFlags: [.control])
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
    XCUIElement.perform(withKeyModifiers: [.shift], block: {
      app.menuItems["Clear all"].click()
    })
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

  func testClearSearchWithCommandDelete() {
    popUpWithHotkey()
    app.typeText("foo bar")
    app.typeKey(.delete, modifierFlags: [.command])
    XCTAssertEqual(app.textFields.firstMatch.value as? String, "")
  }

  func testRemoveLastWordFromSearchWithControlW() {
    popUpWithHotkey()
    app.typeText("foo bar")
    app.typeKey("w", modifierFlags: [.control])
    XCTAssertEqual(app.textFields.firstMatch.value as? String, "foo ")
  }

  func testAllowsToFocusSearchField() {
    popUpWithHotkey()
    // The first click succeeds because application is frontmost.
    app.textFields.firstMatch.click()
    app.typeText("foo")
    XCTAssertEqual(app.textFields.firstMatch.value as? String, "foo")
    // Now close the window AND focus another application
    // by clicking outside of menu.
    let textFieldCoordinates = app.textFields.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
    let outsideCordinates = textFieldCoordinates.withOffset(CGVector(dx: 0, dy: -20))
    outsideCordinates.click()
    // Open again and try to click and focus search field again.
    popUpWithHotkey()
    app.textFields.firstMatch.click()
    app.typeText("foo")
    XCTAssertEqual(app.textFields.firstMatch.value as? String, "foo")
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
    simulatePopupHotkey()
    waitUntilPoppedUp()
  }

  private func popUpWithMouse() {
    app.statusItems.firstMatch.click()
    waitUntilPoppedUp()
  }

  private func simulatePopupHotkey() {
    let commandDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)!
    let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    let shiftDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)!
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftDown.flags = [.maskCommand]
    shiftUp.flags = [.maskCommand]
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cDown.flags = [.maskCommand, .maskShift]
    cUp.flags = [.maskCommand, .maskShift]
    commandDown.post(tap: .cghidEventTap)
    shiftDown.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)
    cUp.post(tap: .cghidEventTap)
    shiftUp.post(tap: .cghidEventTap)
    commandUp.post(tap: .cghidEventTap)
  }

  private func waitUntilPoppedUp() {
    if !app.menuItems.firstMatch.waitForExistence(timeout: 3) {
      XCTFail("Maccy did not pop up")
    }
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: URL) {
    pasteboard.clearContents()
    pasteboard.setData(content.dataRepresentation, forType: .fileURL)
    // WTF: The subsequent writes to pasteboard are not
    // visible unless we explicitly read the last one?!
    pasteboard.string(forType: .fileURL)
    waitTillClipboardCheck()
  }

  // Default interval for Maccy to check clipboard is 1 second
  private func waitTillClipboardCheck() {
    usleep(1500000)
  }

  private func visibleMenuItemTitles() -> [String] {
    return visibleMenuItems().map({ $0.title })
  }

  private func visibleMenuItems() -> [XCUIElement] {
    return app.menuItems.allElementsBoundByIndex.filter({ $0.isHittable })
  }

  private func pin(_ title: String) {
    hover(app.menuItems[title].firstMatch)
    app.typeKey("p", modifierFlags: [.option])
  }

  private func hover(_ element: XCUIElement) {
    element.hover()
    usleep(20000)
  }
}
// swiftlint:enable type_body_length

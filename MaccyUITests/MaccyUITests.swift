import Carbon
import XCTest

// swiftlint:disable file_length
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

  let rtf1 = NSAttributedString(string: "foo").rtf(
    from: NSRange(0...2),
    documentAttributes: [:]
  )
  let rtf2 = NSAttributedString(string: "bar").rtf(
    from: NSRange(0...2),
    documentAttributes: [:]
  )

  let html1 = "<a href='#'>foo</a>".data(using: .utf8)
  let html2 = "<a href='#'>bar</a>".data(using: .utf8)

  var visibleMenuItems: [XCUIElement] { app.menuItems.allElementsBoundByIndex.filter({ $0.isHittable }) }
  var visibleMenuItemTitles: [String] { visibleMenuItems.map({ $0.title }) }

  override func setUp() {
    super.setUp()
    app.launchArguments.append("ui-testing")
    app.launch()

    copyToClipboard(copy2)
    copyToClipboard(copy1)
  }

  override func tearDown() {
    super.tearDown()
    app.terminate()
  }

  func testPopupWithHotkey() throws {
    popUpWithHotkey()
    assertExists(app.menuItems[copy1])
    assertExists(app.menuItems[copy2])
    assertSelected(app.menuItems[copy1].firstMatch)
  }

  func testCloseWithHotkey() throws {
    popUpWithMouse()
    assertExists(app.menuItems[copy1])
    simulatePopupHotkey()
    assertNotExists(app.menuItems[copy1])
  }

  func testPopupWithMenubar() {
    popUpWithMouse()
    assertExists(app.menuItems[copy1])
    assertExists(app.menuItems[copy2])
    assertSelected(app.menuItems[copy1].firstMatch)
  }

  func testNewCopyIsAdded() {
    popUpWithMouse()
    let copy3 = UUID().uuidString
    copyToClipboard(copy3)
    assertNotVisible(app.menuItems[copy3])
    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertExists(app.menuItems[copy2])
    assertSelected(app.menuItems[copy3].firstMatch)
  }

  func testSearch() {
    popUpWithMouse()
    search(copy2)
    assertSearchFieldValue(copy2)
    assertExists(app.menuItems[copy2])
    assertSelected(app.menuItems[copy2].firstMatch)
    assertNotExists(app.menuItems[copy1])
  }

  func testSearchFiles() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()
    search(file2.lastPathComponent)
    assertExists(app.menuItems[file2.absoluteString])
    assertSelected(app.menuItems[file2.absoluteString].firstMatch)
    assertNotExists(app.menuItems[file1.absoluteString])
  }

  func testCopyWithClick() {
    popUpWithMouse()
    app.menuItems[copy2].firstMatch.click()
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyWithEnter() {
    popUpWithMouse()
    hover(app.menuItems[copy2].firstMatch)
    app.typeKey(.enter, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyWithCommandShortcut() {
    popUpWithMouse()
    app.typeKey("2", modifierFlags: [.command])
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testSearchAndCopyWithCommandShortcut() {
    popUpWithMouse()
    search(copy2)
    app.typeKey("1", modifierFlags: [.command])
    // FIXME: Test is flaky
    sleep(1)
    XCTAssertEqual(pasteboard.string(forType: .string), copy2)
  }

  func testCopyImage() {
    copyToClipboard(image2)
    copyToClipboard(image1)
    popUpWithMouse()
    visibleMenuItems[2].click()
    XCTAssertEqual(pasteboard.data(forType: .tiff)!.count, image2.tiffRepresentation!.count)
  }

  func testCopyFile() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()
    XCTAssertEqual(visibleMenuItemTitles[1...2], [file1.absoluteString, file2.absoluteString])

    app.menuItems[file2.absoluteString].firstMatch.click()
    XCTAssertEqual(pasteboard.string(forType: .fileURL), file2.absoluteString)
  }

  // This test does not work because NSPasteboardItem somehow becomes "empty".
  // 
  // func testCopyRTF() {
  //   copyToClipboard(rtf2, .rtf)
  //   copyToClipboard(rtf1, .rtf)
  //   popUpWithHotkey()
  //   XCTAssertEqual(visibleMenuItemTitles()[1...2], ["foo", "bar"])
  //
  //   app.menuItems["bar"].firstMatch.click()
  //  XCTAssertEqual(pasteboard.data(forType: .rtf), rtf2)
  // }

  func testCopyHTML() {
    copyToClipboard(html2, .html)
    copyToClipboard(html1, .html)
    popUpWithMouse()
    XCTAssertEqual(visibleMenuItemTitles[1...2], ["foo", "bar"])

    app.menuItems["bar"].firstMatch.click()
    XCTAssertEqual(pasteboard.data(forType: .html), html2)
  }

  func testControlJ() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    assertSelected(app.menuItems[copy2].firstMatch)
  }

  func testControlK() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey("k", modifierFlags: [.control])
    assertSelected(app.menuItems[copy1].firstMatch)
  }

  func testDeleteEntry() {
    popUpWithMouse()
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(app.menuItems[copy1])
    assertSelected(app.menuItems[copy2].firstMatch)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(app.menuItems[copy1])
  }

  func testDeleteEntryDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(app.menuItems[copy2])
    assertSelected(app.menuItems[copy1].firstMatch)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(app.menuItems[copy2])
  }

  func testClear() {
    popUpWithMouse()
    pin(copy2)
    app.menuItems["Clear"].click()
    confirmClear()
    popUpWithMouse()
    assertNotExists(app.menuItems[copy1])
    assertExists(app.menuItems[copy2])
  }

  func testClearDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.menuItems["Clear"].click()
    confirmClear()
    popUpWithMouse()
    assertNotExists(app.menuItems[copy1])
    assertNotExists(app.menuItems[copy2])
  }

  func testClearAll() {
    popUpWithMouse()
    pin(copy2)
    XCUIElement.perform(withKeyModifiers: [.shift], block: {
      app.menuItems["Clear all"].click()
    })
    confirmClear()
    popUpWithMouse()
    assertNotExists(app.menuItems[copy1])
    assertNotExists(app.menuItems[copy2])
  }

  func testPin() {
    popUpWithMouse()
    pin(copy2)
    XCTAssertEqual(visibleMenuItemTitles[1...2], [copy2, copy1])
    assertSelected(app.menuItems[copy2].firstMatch)

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    XCTAssertEqual(visibleMenuItemTitles[1...2], [copy2, copy1])
    assertSelected(app.menuItems[copy1].firstMatch)
  }

  func testPinDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.typeKey("p", modifierFlags: [.option])
    assertSearchFieldValue("")
    XCTAssertEqual(visibleMenuItemTitles[1...2], [copy2, copy1])
    assertSelected(app.menuItems[copy2].firstMatch)
  }

  func testUnpin() {
    popUpWithMouse()
    pin(copy2)
    app.typeKey("p", modifierFlags: [.option]) // unpin
    assertSelected(app.menuItems[copy2].firstMatch)
    XCTAssertEqual(visibleMenuItemTitles[1...2], [copy1, copy2])
  }

  func testClearSearchWithCommandDelete() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey(.delete, modifierFlags: [.command])
    assertSearchFieldValue("")
  }

  func testRemoveLastWordFromSearchWithControlW() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey("w", modifierFlags: [.control])
    assertSearchFieldValue("foo ")
  }

  func testAllowsToFocusSearchField() {
    popUpWithMouse()
    // The first click succeeds because application is frontmost.
    app.searchFields.firstMatch.click()
    search("foo")
    assertSearchFieldValue("foo")
    // Now close the window AND focus another application
    // by clicking outside of menu.
    let textFieldCoordinates = app.searchFields.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
    let outsideCoordinates = textFieldCoordinates.withOffset(CGVector(dx: 0, dy: -20))
    outsideCoordinates.click()
    // Open again and try to click and focus search field again.
    popUpWithMouse()
    app.searchFields.firstMatch.click()
    search("foo")
    assertSearchFieldValue("foo")
  }

  func testPasteToSearchWithFieldUnfocused() {
    popUpWithMouse()
    app.typeKey("v", modifierFlags: [.command])
    waitForSearch()
    assertSearchFieldValue(copy1)
    assertExists(app.menuItems[copy1])
    assertSelected(app.menuItems[copy1].firstMatch)
    assertNotExists(app.menuItems[copy2])
  }

  func testPasteToSearchWithFieldFocused() {
    popUpWithMouse()
    app.searchFields.firstMatch.click()
    app.typeKey("v", modifierFlags: [.command])
    waitForSearch()
    assertSearchFieldValue(copy1)
    assertExists(app.menuItems[copy1])
    assertSelected(app.menuItems[copy1].firstMatch)
    assertNotExists(app.menuItems[copy2])
  }

  func testDisablesOnOptionClickingMenubarIcon() {
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }

    let copy3 = UUID().uuidString
    let copy4 = UUID().uuidString
    copyToClipboard(copy3)
    copyToClipboard(copy4)

    popUpWithMouse()
    assertNotExists(app.menuItems[copy3])
    assertNotExists(app.menuItems[copy4])

    app.typeKey(.escape, modifierFlags: [])
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }
  }

  func testDisablesOnlyForNextCopyOnOptionShiftClickingMenubarIcon() {
    XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
      app.statusItems.firstMatch.click()
    }

    let copy3 = UUID().uuidString
    let copy4 = UUID().uuidString
    copyToClipboard(copy3)
    copyToClipboard(copy4)

    popUpWithMouse()
    assertNotExists(app.menuItems[copy3])
    assertExists(app.menuItems[copy4])
  }

  func testCreatesNewCopyOnEnterWhenSearchResultsAreEmpty() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), "foo bar")
    popUpWithMouse()
    assertExists(app.menuItems["foo bar"])
  }

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

  private func copyToClipboard(_ content: Data?, _ type: NSPasteboard.PasteboardType) {
    pasteboard.clearContents()
    pasteboard.setData(content, forType: type)
    waitTillClipboardCheck()
  }

  // Default interval for Maccy to check clipboard is 1 second
  private func waitTillClipboardCheck() {
    usleep(1500000)
  }

  private func pin(_ title: String) {
    hover(app.menuItems[title].firstMatch)
    app.typeKey("p", modifierFlags: [.option])
  }

  private func hover(_ element: XCUIElement) {
    element.hover()
    usleep(20000)
  }

  private func search(_ string: String) {
    // NOTE: app.typeText is broken in Sonoma and causes some
    //       Chars to be submitted with a .command mask (e.g. 'p', 'k' or 'j')
    string.forEach { ch in
      app.typeKey("\(ch)", modifierFlags: [])
    }
    waitForSearch()
  }

  private func waitForSearch() {
    // FIXME: This is a hack and is flaky. Ideally we should wait for a proper condition to detect that search has settled down.
    usleep(500000) // wait for search throttle
  }

  private func assertExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 1"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertNotExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 0"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertNotVisible(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "(exists = 0) || (isHittable = 0)"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertSelected(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "isSelected = 1"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertSearchFieldValue(_ string: String) {
    XCTAssertEqual(app.searchFields.firstMatch.value as? String, string)
  }

  private func confirmClear() {
    let button = app.dialogs.firstMatch.buttons["Clear"].firstMatch
    expectation(for: NSPredicate(format: "isHittable = 1"), evaluatedWith: button)
    waitForExpectations(timeout: 3)
    button.click()
  }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length

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

  let imageType = NSPredicate(
    format: "elementType == %lu",
    argumentArray: [XCUIElement.ElementType.image.rawValue]
  )

  var items: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "copy-history-item")
  }

  var itemTitles: [String] {
    items.allElementsBoundByIndex
      .sorted(by: { $0.frame.origin.y < $1.frame.origin.y })
      .compactMap { $0.value as? String }
  }

  override func setUp() {
    super.setUp()
    app.launchArguments.append("enable-testing")
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
    assertExists(items[copy1])
    assertExists(items[copy2])
  }

  func testCloseWithHotkey() throws {
    popUpWithMouse()
    assertExists(items[copy1])
    simulatePopupHotkey()
    assertNotExists(items[copy1])
  }

  func testPopupWithMenubar() {
    popUpWithMouse()
    assertExists(items[copy1])
    assertExists(items[copy2])
  }

  func testNewCopyIsAdded() {
    popUpWithMouse()
    let copy3 = UUID().uuidString
    copyToClipboard(copy3)
    assertExists(items[copy3])
    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertExists(items[copy2])
  }

  func testSearch() {
    popUpWithMouse()
    search(copy2)
    assertSearchFieldValue(copy2)
    assertExists(app.staticTexts[copy2])
    assertNotExists(items[copy1])
  }

  func testSearchFiles() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()
    search(file2.lastPathComponent)
    assertExists(items[file2.absoluteString])
    assertNotExists(items[file1.absoluteString])
  }

  func testCopyWithClick() {
    popUpWithMouse()
    items[copy2].firstMatch.click()
    assertPasteboardStringEquals(copy2)
  }

  func testCopyWithEnter() {
    popUpWithMouse()
    hover(items[copy2].firstMatch)
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testCopyWithCommandShortcut() {
    popUpWithMouse()
    app.typeKey("2", modifierFlags: [.command])
    assertPasteboardStringEquals(copy2)
  }

  func testSearchAndCopyWithCommandShortcut() {
    popUpWithMouse()
    search(copy2)
    app.typeKey("1", modifierFlags: [.command])
    assertPasteboardStringEquals(copy2)
  }

  func testCopyImage() {
    copyToClipboard(image2)
    copyToClipboard(image1)
    popUpWithMouse()
    items.matching(imageType).allElementsBoundByIndex[1].click()
    assertPasteboardDataCountEquals(image2.tiffRepresentation!.count, forType: .tiff)
  }

  func testCopyFile() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()

    XCTAssertEqual(itemTitles[0...1], [file1.absoluteString, file2.absoluteString])

    items[file2.absoluteString].firstMatch.click()
    assertPasteboardStringEquals(file2.absoluteString, forType: .fileURL)
  }

  // This test does not work because NSPasteboardItem somehow becomes "empty".
  //
  // func testCopyRTF() {
  //   copyToClipboard(rtf2, .rtf)
  //   copyToClipboard(rtf1, .rtf)
  //   popUpWithHotkey()
  //   XCTAssertEqual(visibleMenuItemTitles()[1...2], ["foo", "bar"])
  //
  //   app.staticTexts["bar"].firstMatch.click()
  //   XCTAssertEqual(pasteboard.data(forType: .rtf), rtf2)
  // }

  func testCopyHTML() {
    copyToClipboard(html2, .html)
    copyToClipboard(html1, .html)
    popUpWithMouse()
    XCTAssertEqual(itemTitles[0...1], ["foo", "bar"])

    items["bar"].firstMatch.click()
    assertPasteboardDataEquals(html2, forType: .html)
  }

  func testDownArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testUpArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.upArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  func testControlJ() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testControlK() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey("k", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  func testDeleteEntry() {
    popUpWithMouse()
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy1])
  }

  func testDeleteEntryDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy2])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy2])
  }

  func testClear() {
    popUpWithMouse()
    pin(copy2)
    app.staticTexts["Clear"].click()
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertExists(items[copy2])
  }

  func testClearDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.staticTexts["Clear"].click()
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testClearAll() {
    popUpWithMouse()
    pin(copy2)
    XCUIElement.perform(withKeyModifiers: [.shift]) {
      app.staticTexts["Clear all"].click()
    }
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testPin() {
    popUpWithMouse()
    pin(copy2)
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])
  }

  func testPinDuringSearch() {
    popUpWithMouse()
    search(copy2)
    pin(copy2)
    assertSearchFieldValue("")
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])
  }

  func testUnpin() {
    popUpWithMouse()
    pin(copy2)
    pin(copy2)
    XCTAssertEqual(itemTitles[0...1], [copy1, copy2])
  }

  func testRemoveLastWordFromSearchWithControlW() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey("w", modifierFlags: [.control])
    assertSearchFieldValue("foo ")
  }

  func testPasteToSearch() {
    popUpWithMouse()
    app.typeKey("v", modifierFlags: [.command])
    waitForSearch()
    assertSearchFieldValue(copy1)
    assertExists(items[copy1])
    assertNotExists(items[copy2])
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
    assertNotExists(items[copy3])
    assertNotExists(items[copy4])

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
    assertNotExists(items[copy3])
    assertExists(items[copy4])
  }

  func testCreatesNewCopyOnEnterWhenSearchResultsAreEmpty() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), "foo bar")
    assertExists(items["foo bar"])
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
    let commandDown = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)!
    let commandUp = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    let shiftDown = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)!
    let shiftUp = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
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
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 3) {
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
    usleep(1_500_000)
  }

  private func pin(_ title: String) {
    hover(items[title].firstMatch)
    app.typeKey("p", modifierFlags: [.option])
    usleep(1_500_000)
  }

  private func hover(_ element: XCUIElement) {
    element.hover()
    usleep(20000)
  }

  private func search(_ string: String) {
    // NOTE: app.typeText is broken in Sonoma and causes some
    //       Chars to be submitted with a .command mask (e.g. 'p', 'k' or 'j')
    string.forEach {
      app.typeKey("\($0)", modifierFlags: [])
    }
    waitForSearch()
  }

  private func waitForSearch() {
    // NOTE: This is a hack and is flaky.
    // Ideally we should wait for a proper condition to detect that search has settled down.
    usleep(500000)  // wait for search throttle
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
    expectation(
      for: NSPredicate(format: "(exists = 0) || (isHittable = 0)"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardDataEquals(
    _ expected: Data?, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let copy = object as? Data else {
        return false
      }

      return self.pasteboard.data(forType: forType) == copy
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardDataCountEquals(
    _ expected: Int, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let count = object as? Int else {
        return false
      }

      return self.pasteboard.data(forType: forType)!.count == count
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardStringEquals(
    _ expected: String?, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let copy = object as? String else {
        return false
      }

      return self.pasteboard.string(forType: forType) == copy
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertSearchFieldValue(_ string: String) {
    XCTAssertEqual(app.textFields.firstMatch.value as? String, string)
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

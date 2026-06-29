import XCTest

/// End-to-end UI tests driving the running Maccy app via XCUITest.
///
/// Tests populate the system pasteboard, open the popup through the menu-bar icon
/// or the global hotkey, and assert on selection, search, pin, copy, and clear
/// behavior. Cross-process coordination with the app uses distributed
/// notifications posted from the test process.
@MainActor
class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  /// Distributed-notification names the test process posts to drive in-app hooks.
  private enum UITestNotification {
    static let hotKeyDown = Notification.Name("org.p0deje.Maccy.UITest.hotKeyDown")
    static let modifiersReleased = Notification.Name("org.p0deje.Maccy.UITest.modifiersReleased")
    static let clearHistory = Notification.Name("org.p0deje.Maccy.UITest.clearHistory")
    static let clearAllHistory = Notification.Name("org.p0deje.Maccy.UITest.clearAllHistory")
    static let pinHistoryItem = Notification.Name("org.p0deje.Maccy.UITest.pinHistoryItem")
  }

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString
  let copy3 = UUID().uuidString

  // https://hetima.github.io/fucking_nsimage_syntax
  let image1 = NSImage(named: "NSAddTemplate")!
  let image2 = NSImage(named: "NSBluetoothTemplate")!

  let file1 = URL.applicationSupportDirectory.appendingPathComponent("file1.txt")
  let file2 = URL.applicationSupportDirectory.appendingPathComponent("file2.txt")

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

  /// Query for all visible history-row elements.
  var items: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "copy-history-item")
  }

  /// History-row titles in top-to-bottom screen order.
  var itemTitles: [String] {
    items.allElementsBoundByIndex
      .sorted(by: { $0.frame.origin.y < $1.frame.origin.y })
      .compactMap { $0.value as? String }
  }

  /// Writes scratch fixture files, launches the app with `enable-testing`, and
  /// seeds the pasteboard with two copies.
  override func setUp() async throws {
    try await super.setUp()

    try? "Hello world".write(to: file1, atomically: true, encoding: .utf8)
    try? "Hello world".write(to: file2, atomically: true, encoding: .utf8)

    app.launchArguments.append("enable-testing")
    app.launch()
    assertExists(app.statusItems.firstMatch)

    copyToClipboard(copy2)
    copyToClipboard(copy1)

  }

  /// Terminates the app after each test.
  override func tearDown() async throws {
    try await super.tearDown()
    app.terminate()
  }

  /// The popup opens via the hotkey and shows the copied items.
  func testPopupWithHotkey() throws {
    popUpWithHotkey()
    assertExists(items[copy1])
    assertExists(items[copy2])
  }

  /// The popup closes when the hotkey is pressed again.
  func testCloseWithHotkey() throws {
    popUpWithMouse()
    assertExists(items[copy1])
    simulatePopupHotkey()
    assertNotExists(items[copy1])
  }

  /// The popup opens via the menu-bar icon and shows the copied items.
  func testPopupWithMenubar() {
    popUpWithMouse()
    assertExists(items[copy1])
    assertExists(items[copy2])
  }

  /// A new copy while the popup is dismissed appears on the next open.
  func testNewCopyIsAdded() {
    popUpWithMouse()
    let copy3 = UUID().uuidString
    copyToClipboard(copy3)
    assertExists(items[copy3])
    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertExists(items[copy2])
  }

  /// Typing a query filters the list to matching items.
  func testSearch() {
    popUpWithMouse()
    search(copy2)
    assertSearchFieldValue(copy2)
    assertExists(app.staticTexts[copy2])
    assertNotExists(items[copy1])
  }

  /// Search matches copied file URLs by their filename.
  func testSearchFiles() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()
    search(file2.lastPathComponent)
    assertExists(items[file2.absoluteString.removingPercentEncoding!])
    assertNotExists(items[file1.absoluteString.removingPercentEncoding!])
  }

  /// Clicking an item copies it back to the pasteboard.
  func testCopyWithClick() {
    popUpWithMouse()
    assertExists(items[copy2])
    items[copy2].firstMatch.click()
    assertPasteboardStringEquals(copy2)
  }

  /// Pressing Enter on the focused item copies it back to the pasteboard.
  func testCopyWithEnter() {
    popUpWithMouse()
    hover(items[copy2].firstMatch)
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  /// A command-number shortcut copies the corresponding item.
  func testCopyWithCommandShortcut() {
    popUpWithMouse()
    app.typeKey("2", modifierFlags: [.command])
    assertPasteboardStringEquals(copy2)
  }

  /// Searching then using a command-number shortcut copies the matched item.
  func testSearchAndCopyWithCommandShortcut() {
    popUpWithMouse()
    search(copy2)
    app.typeKey("1", modifierFlags: [.command])
    assertPasteboardStringEquals(copy2)
  }

  /// Copying an image and selecting it places the image data on the pasteboard.
  func testCopyImage() {
    copyToClipboard(image2)
    copyToClipboard(image1)
    popUpWithMouse()
    items.matching(imageType).allElementsBoundByIndex[1].click()
    assertPasteboardDataCountEquals(image2.tiffRepresentation!.count, forType: .tiff)
  }

  /// Copying a file URL and selecting it places the file URL on the pasteboard.
  func testCopyFile() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()

    assertLeadingItemTitles([
      file1.absoluteString.removingPercentEncoding!,
      file2.absoluteString.removingPercentEncoding!
    ])

    items[file2.absoluteString.removingPercentEncoding!].firstMatch.click()
    assertPasteboardStringEquals(file2.absoluteString, forType: .fileURL)
  }

  /// Rich-text copies round-trip their attributed string back to the pasteboard.
  func testCopyRTF() {
    clearAllHistory()

    copyToClipboard("bar", rtf2, .rtf)
    popUpWithMouse()
    assertLeadingItemTitles(["bar"])
    app.typeKey(.escape, modifierFlags: [])

    copyToClipboard("foo", rtf1, .rtf)
    popUpWithHotkey()
    assertLeadingItemTitles(["foo", "bar"])

    selectSecondItem()
    assertPasteboardRichTextEquals("bar", forType: .rtf)
  }

  /// HTML copies round-trip their HTML data back to the pasteboard.
  func testCopyHTML() {
    clearAllHistory()

    copyToClipboard("bar", html2, .html)
    popUpWithMouse()
    assertLeadingItemTitles(["bar"])
    app.typeKey(.escape, modifierFlags: [])

    copyToClipboard("foo", html1, .html)
    popUpWithMouse()
    assertLeadingItemTitles(["foo", "bar"])

    selectSecondItem()
    assertPasteboardDataEquals(html2, forType: .html)
  }

  /// The down-arrow moves selection to the next item, then Enter copies it.
  func testDownArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  /// Down then up returns to the original item, which Enter copies.
  func testUpArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.upArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  /// Control-J moves selection down, then Enter copies the item.
  func testControlJ() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  /// Control-J then Control-K navigates down and back up, then Enter copies.
  func testControlK() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey("k", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  /// Option-Delete removes the focused entry, and it stays gone on reopen.
  func testDeleteEntry() {
    popUpWithMouse()
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy1])
  }

  /// Option-Delete during search removes the matched entry.
  func testDeleteEntryDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy2])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy2])
  }

  /// Clearing history dismisses the popup and removes unpinned items, keeping
  /// pinned ones.
  func testClear() {
    popUpWithMouse()
    pinForTesting(copy2)
    clearHistory()
    assertPopupDismissed()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertExists(items[copy2])
  }

  /// Clearing history during search dismisses the popup and removes everything.
  func testClearDuringSearch() {
    popUpWithMouse()
    search(copy2)
    clearHistory()
    assertPopupDismissed()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  /// Clear-all dismisses the popup and removes every item including pinned ones.
  func testClearAll() {
    popUpWithMouse()
    pinForTesting(copy2)
    clearAllHistory()
    assertPopupDismissed()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  /// Pinning moves an item to the front of the list and keeps it there on reopen.
  func testPin() {
    popUpWithMouse()
    pin(copy2)
    assertLeadingItemTitles([copy2, copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertLeadingItemTitles([copy2, copy1])
  }

  /// Pinning during search pins the matched item and clears the query.
  func testPinDuringSearch() {
    popUpWithMouse()
    search(copy2)
    pin(copy2)
    assertSearchFieldValue("")
    assertLeadingItemTitles([copy2, copy1])
  }

  /// Pinning an item twice unpins it, restoring its list position.
  func testUnpin() {
    popUpWithMouse()
    pin(copy2)
    pin(copy2)
    assertLeadingItemTitles([copy1, copy2])
  }

  /// Control-W removes the last word from the search field.
  func testRemoveLastWordFromSearchWithControlW() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey("w", modifierFlags: [.control])
    assertSearchFieldValue("foo ")
  }

  /// Pasting into the popup fills the search field and filters the list.
  func testPasteToSearch() {
    popUpWithMouse()
    app.typeKey("v", modifierFlags: [.command])
    waitForSearch()
    assertSearchFieldValue(copy1)
    assertExists(items[copy1])
    assertNotExists(items[copy2])
  }

  /// Option-clicking the menu-bar icon disables clipboard watching until toggled off.
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

  /// Option-Shift-clicking the menu-bar icon disables watching for the next copy only.
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

  /// Pressing Enter with no search results copies the query text as a new item.
  func testCreatesNewCopyOnEnterWhenSearchResultsAreEmpty() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), "foo bar")
    assertExists(items["foo bar"])
  }

  /// The hotkey toggles the popup open and closed across modifier releases.
  func testOpenAndClose() throws {
    pressPopupHotkey()
    waitUntilPoppedUp()

    releasePopupKey()
    waitUntilPoppedUp()

    releaseShiftKey()
    waitUntilPoppedUp()

    releasePopupModifiers()
    waitUntilPoppedUp()

    pressPopupHotkey()
    assertPopupDismissed()
  }

  /// Re-pressing the hotkey advances selection and copies the second item.
  func testOpenAndSelectSecondItem() throws {
    pressPopupHotkey()
    waitUntilPoppedUp()

    releasePopupKey()
    pressPopupHotkey()
    releasePopupModifiers()

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  /// Three hotkey presses cycle selection to the third item and copy the second.
  func testOpenAndSelectThirdItem() throws {
    copyToClipboard(copy3)

    pressPopupHotkey()
    waitUntilPoppedUp()

    releasePopupKey()
    pressPopupHotkey()
    releasePopupKey()
    pressPopupHotkey()
    releasePopupModifiers()

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  /// Repeated rapid hotkey presses select and copy the same item as the spaced
  /// sequence.
  func testOpenAndSelectThirdItemRepeatedPress() throws {
    copyToClipboard(copy3)

    pressPopupHotkey()
    waitUntilPoppedUp()

    pressPopupHotkey()
    pressPopupHotkey()
    releasePopupModifiers()

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  /// Clicking outside the popup dismisses it, and the hotkey still works afterward.
  func testTogglePopupAndCloseOnClickOutside() {
    popUpWithHotkey()

    // Click outside the popup to close it
    let statusBar = app.statusItems.firstMatch
    let coordinate = statusBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 10.0))
    coordinate.click()
    assertNotExists(items[copy1])

    // Assert that the hotkeys still work
    popUpWithHotkey()

    simulatePopupHotkey()
    assertPopupDismissed()
  }

  /// Opens the popup via the hotkey and waits for it to appear.
  private func popUpWithHotkey() {
    simulatePopupHotkey()
    waitUntilPoppedUp()
  }

  /// Opens the popup by clicking the menu-bar icon.
  private func popUpWithMouse() {
    app.statusItems.firstMatch.click()
    waitUntilPoppedUp()
  }

  /// Presses and releases the popup hotkey as a single gesture.
  private func simulatePopupHotkey() {
    pressPopupHotkey()
    releasePopupKey()
    releasePopupModifiers()
  }

  /// Posts the in-app hotkey-down notification.
  private func pressPopupHotkey() {
    postUITestNotification(UITestNotification.hotKeyDown)
  }

  /// Pauses long enough to simulate releasing the hotkey.
  private func releasePopupKey() {
    usleep(100_000)
  }

  /// Pauses long enough to simulate releasing the shift modifier.
  private func releaseShiftKey() {
    usleep(100_000)
  }

  /// Posts the in-app modifiers-released notification.
  private func releasePopupModifiers() {
    postUITestNotification(UITestNotification.modifiersReleased)
  }

  /// Posts a distributed notification to the running app and brief pauses for delivery.
  private func postUITestNotification(_ name: Notification.Name, userInfo: [String: Any]? = nil) {
    DistributedNotificationCenter.default().postNotificationName(
      name,
      object: nil,
      userInfo: userInfo,
      deliverImmediately: true
    )
    usleep(200_000)
  }

  /// Fails the test unless the popup appears within the timeout.
  private func waitUntilPoppedUp() {
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 3) {
      XCTFail("Maccy did not pop up")
    }
  }

  /// Fails the test unless the popup dismisses within the timeout.
  private func assertPopupDismissed() {
    if !app.staticTexts.firstMatch.waitForNonExistence(timeout: 3) {
      XCTFail("Maccy did not dismiss")
    }
  }

  /// Places a plain string on the pasteboard and waits for Maccy to observe it.
  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }

  /// Places an image on the pasteboard and waits for Maccy to observe it.
  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    waitTillClipboardCheck()
  }

  /// Places a file URL on the pasteboard and waits for Maccy to observe it.
  ///
  /// The trailing read is a workaround: subsequent pasteboard writes are not
  /// visible to Maccy unless the previous one is explicitly read first.
  private func copyToClipboard(_ content: URL) {
    pasteboard.clearContents()
    pasteboard.setData(content.dataRepresentation, forType: .fileURL)
    // WTF: The subsequent writes to pasteboard are not
    // visible unless we explicitly read the last one?!
    pasteboard.string(forType: .fileURL)
    waitTillClipboardCheck()
  }

  /// Places a single typed data blob on the pasteboard and waits for Maccy to observe it.
  private func copyToClipboard(_ content: Data?, _ type: NSPasteboard.PasteboardType) {
    pasteboard.clearContents()
    pasteboard.setData(content, forType: type)
    waitTillClipboardCheck()
  }

  /// Places a string plus a typed rich-content blob on the pasteboard and waits
  /// for Maccy to observe it.
  private func copyToClipboard(_ title: String, _ content: Data?, _ type: NSPasteboard.PasteboardType) {
    pasteboard.clearContents()
    pasteboard.declareTypes([.string, type], owner: nil)
    pasteboard.setString(title, forType: .string)
    if let content {
      pasteboard.setData(content, forType: type)
    }
    waitTillClipboardCheck()
  }

  /// Waits just over one clipboard-check interval (the default poll is 1 second).
  private func waitTillClipboardCheck() {
    usleep(1_500_000)
  }

  /// Pins the item with the given title via the option-P shortcut.
  private func pin(_ title: String) {
    hover(items[title].firstMatch)
    app.typeKey("p", modifierFlags: [.option])
    usleep(1_500_000)
  }

  /// Pins an item by title through the in-app test hook.
  private func pinForTesting(_ title: String) {
    postUITestNotification(UITestNotification.pinHistoryItem, userInfo: ["title": title])
  }

  /// Triggers a clear (keep pinned) through the in-app test hook.
  private func clearHistory() {
    postUITestNotification(UITestNotification.clearHistory)
  }

  /// Triggers a clear-all through the in-app test hook.
  private func clearAllHistory() {
    postUITestNotification(UITestNotification.clearAllHistory)
  }

  /// Moves selection down one row and confirms with Enter.
  private func selectSecondItem() {
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
  }

  /// Hovers an element and brief pauses for the hover to register.
  private func hover(_ element: XCUIElement) {
    element.hover()
    usleep(20000)
  }

  /// Types the query character by character into the search field.
  ///
  /// `app.typeText` is unreliable on Sonoma and occasionally injects characters
  /// with a `.command` mask (e.g. `p`, `k`, `j`), so each character is sent
  /// explicitly via `typeKey`.
  private func search(_ string: String) {
    string.forEach {
      app.typeKey("\($0)", modifierFlags: [])
    }
    waitForSearch()
  }

  /// Pauses long enough for the throttled search to settle.
  private func waitForSearch() {
    usleep(500000)  // wait for search throttle
  }

  /// Asserts an element exists, polling up to the timeout.
  private func assertExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 1"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  /// Asserts an element does not exist, polling up to the timeout.
  private func assertNotExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 0"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  /// Asserts an element is absent or not hittable, polling up to the timeout.
  private func assertNotVisible(_ element: XCUIElement) {
    expectation(
      for: NSPredicate(format: "(exists = 0) || (isHittable = 0)"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  /// Asserts the pasteboard carries exactly `expected` for `forType`.
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

  /// Asserts the pasteboard's rich-text value for `forType` equals `expected`.
  private func assertPasteboardRichTextEquals(
    _ expected: String, forType: NSPasteboard.PasteboardType
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let copy = object as? String,
            let data = self.pasteboard.data(forType: forType),
            let attributedString = NSAttributedString(rtf: data, documentAttributes: nil)
      else {
        return false
      }

      return attributedString.string == copy
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  /// Asserts the byte count of the pasteboard value for `forType` equals `expected`.
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

  /// Asserts the pasteboard's string value for `forType` equals `expected`.
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

  /// Asserts the search field's current value.
  private func assertSearchFieldValue(_ string: String) {
    XCTAssertEqual(app.textFields.firstMatch.value as? String, string)
  }

  /// Asserts the leading history-row titles match `expected`, in order.
  private func assertLeadingItemTitles(
    _ expected: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let titles = itemTitles
    XCTAssertGreaterThanOrEqual(
      titles.count,
      expected.count,
      "Expected at least \(expected.count) history item titles, got \(titles.count): \(titles)",
      file: file,
      line: line
    )
    guard titles.count >= expected.count else {
      return
    }
    XCTAssertEqual(Array(titles.prefix(expected.count)), expected, file: file, line: line)
  }

}

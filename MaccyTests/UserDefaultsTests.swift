import XCTest
@testable import Maccy

class UserDefaultsTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.fuzzySearch
  let savedIgnoreEvents = UserDefaults.standard.ignoreEvents
  let savedIgnoredPasteboardTypes = UserDefaults.standard.ignoredPasteboardTypes
  let savedPasteByDefault = UserDefaults.standard.pasteByDefault
  let savedPinTo = UserDefaults.standard.pinTo
  let savedPlaySounds = UserDefaults.standard.playSounds
  let savedPopupPosition = UserDefaults.standard.popupPosition
  let savedRemoveFormattingByDefault = UserDefaults.standard.removeFormattingByDefault
  let savedSaratovSeparator = UserDefaults.standard.saratovSeparator
  let savedShowInStatusBar = UserDefaults.standard.showInStatusBar
  let savedSize = UserDefaults.standard.size

  override func setUp() {
    super.setUp()

    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.fuzzySearch)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.ignoreEvents)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.ignoredPasteboardTypes)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.pasteByDefault)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.pinTo)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.playSounds)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.popupPosition)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.removeFormattingByDefault)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.saratovSeparator)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.showInStatusBar)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.size)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.storage)
  }

  override func tearDown() {
    super.tearDown()

    UserDefaults.standard.fuzzySearch = savedFuzzySearch
    UserDefaults.standard.ignoreEvents = savedIgnoreEvents
    UserDefaults.standard.ignoredPasteboardTypes = savedIgnoredPasteboardTypes
    UserDefaults.standard.pasteByDefault = savedPasteByDefault
    UserDefaults.standard.pinTo = savedPinTo
    UserDefaults.standard.playSounds = savedPlaySounds
    UserDefaults.standard.popupPosition = savedPopupPosition
    UserDefaults.standard.removeFormattingByDefault = savedRemoveFormattingByDefault
    UserDefaults.standard.saratovSeparator = savedSaratovSeparator
    UserDefaults.standard.showInStatusBar = savedShowInStatusBar
    UserDefaults.standard.size = savedSize
  }

  func testDefaultValues() {
    XCTAssertEqual(UserDefaults.standard.fuzzySearch, false)
    XCTAssertEqual(UserDefaults.standard.ignoreEvents, false)
    XCTAssertEqual(UserDefaults.standard.ignoredPasteboardTypes, Set())
    XCTAssertEqual(UserDefaults.standard.pasteByDefault, false)
    XCTAssertEqual(UserDefaults.standard.pinTo, "top")
    XCTAssertEqual(UserDefaults.standard.playSounds, false)
    XCTAssertEqual(UserDefaults.standard.popupPosition, "cursor")
    XCTAssertEqual(UserDefaults.standard.removeFormattingByDefault, false)
    XCTAssertEqual(UserDefaults.standard.saratovSeparator, false)
    XCTAssertEqual(UserDefaults.standard.showInStatusBar, true)
    XCTAssertEqual(UserDefaults.standard.size, 200)
  }

  func testChanging() {
    UserDefaults.standard.fuzzySearch = true
    UserDefaults.standard.ignoreEvents = true
    UserDefaults.standard.ignoredPasteboardTypes = ["foo", "bar"]
    UserDefaults.standard.pasteByDefault = true
    UserDefaults.standard.pinTo = "bottom"
    UserDefaults.standard.playSounds = true
    UserDefaults.standard.popupPosition = "center"
    UserDefaults.standard.removeFormattingByDefault = true
    UserDefaults.standard.saratovSeparator = true
    UserDefaults.standard.showInStatusBar = false
    UserDefaults.standard.size = 100

    XCTAssertEqual(UserDefaults.standard.fuzzySearch, true)
    XCTAssertEqual(UserDefaults.standard.ignoreEvents, true)
    XCTAssertEqual(UserDefaults.standard.ignoredPasteboardTypes, Set(["foo", "bar"]))
    XCTAssertEqual(UserDefaults.standard.pasteByDefault, true)
    XCTAssertEqual(UserDefaults.standard.pinTo, "bottom")
    XCTAssertEqual(UserDefaults.standard.playSounds, true)
    XCTAssertEqual(UserDefaults.standard.popupPosition, "center")
    XCTAssertEqual(UserDefaults.standard.removeFormattingByDefault, true)
    XCTAssertEqual(UserDefaults.standard.saratovSeparator, true)
    XCTAssertEqual(UserDefaults.standard.showInStatusBar, false)
    XCTAssertEqual(UserDefaults.standard.size, 100)
  }
}

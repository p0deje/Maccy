import XCTest
@testable import Maccy

class UserDefaultsTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.fuzzySearch
  let savedHotKey = UserDefaults.standard.hotKey
  let savedIgnoreEvents = UserDefaults.standard.ignoreEvents
  let savedPasteByDefault = UserDefaults.standard.pasteByDefault
  let savedSaratovSeparator = UserDefaults.standard.saratovSeparator
  let savedShowInStatusBar = UserDefaults.standard.showInStatusBar
  let savedSize = UserDefaults.standard.size
  let savedStorage = UserDefaults.standard.storage
  let savedShowSearch = UserDefaults.standard.showSearch

  override func setUp() {
    super.setUp()

    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.fuzzySearch)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.hotKey)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.ignoreEvents)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.pasteByDefault)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.saratovSeparator)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.showInStatusBar)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.size)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.storage)
    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.showSearch)
  }

  override func tearDown() {
    super.tearDown()

    UserDefaults.standard.set(savedFuzzySearch, forKey: UserDefaults.Keys.fuzzySearch)
    UserDefaults.standard.set(savedHotKey, forKey: UserDefaults.Keys.hotKey)
    UserDefaults.standard.set(savedIgnoreEvents, forKey: UserDefaults.Keys.ignoreEvents)
    UserDefaults.standard.set(savedPasteByDefault, forKey: UserDefaults.Keys.pasteByDefault)
    UserDefaults.standard.set(savedSaratovSeparator, forKey: UserDefaults.Keys.saratovSeparator)
    UserDefaults.standard.set(savedShowInStatusBar, forKey: UserDefaults.Keys.showInStatusBar)
    UserDefaults.standard.set(savedSize, forKey: UserDefaults.Keys.size)
    UserDefaults.standard.set(savedStorage, forKey: UserDefaults.Keys.storage)
    UserDefaults.standard.set(savedShowSearch, forKey: UserDefaults.Keys.showSearch)
  }

  func testDefaultValues() {
    XCTAssertEqual(UserDefaults.standard.fuzzySearch, false)
    XCTAssertEqual(UserDefaults.standard.hotKey, "command+shift+c")
    XCTAssertEqual(UserDefaults.standard.ignoreEvents, false)
    XCTAssertEqual(UserDefaults.standard.pasteByDefault, false)
    XCTAssertEqual(UserDefaults.standard.saratovSeparator, false)
    XCTAssertEqual(UserDefaults.standard.showInStatusBar, true)
    XCTAssertEqual(UserDefaults.standard.size, 200)
    XCTAssertEqual(UserDefaults.standard.storage, [])
    XCTAssertEqual(UserDefaults.standard.showSearch, true)
  }

  func testChanging() {
    UserDefaults.standard.fuzzySearch = true
    UserDefaults.standard.hotKey = "command+shift+a"
    UserDefaults.standard.ignoreEvents = true
    UserDefaults.standard.pasteByDefault = true
    UserDefaults.standard.saratovSeparator = true
    UserDefaults.standard.showInStatusBar = false
    UserDefaults.standard.size = 100
    UserDefaults.standard.storage = ["foo"]
    UserDefaults.standard.showSearch = true

    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Keys.fuzzySearch), true)
    XCTAssertEqual(UserDefaults.standard.string(forKey: UserDefaults.Keys.hotKey), "command+shift+a")
    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Keys.ignoreEvents), true)
    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Keys.pasteByDefault), true)
    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Keys.saratovSeparator), true)
    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Keys.showInStatusBar), false)
    XCTAssertEqual(UserDefaults.standard.integer(forKey: UserDefaults.Keys.size), 100)
    XCTAssertEqual(UserDefaults.standard.array(forKey: UserDefaults.Keys.storage) as? [String], ["foo"])
    XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Keys.showSearch), true)
  }
}

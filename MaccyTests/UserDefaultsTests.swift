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
  }

  override func tearDown() {
    super.tearDown()

    UserDefaults.standard.fuzzySearch = savedFuzzySearch
    UserDefaults.standard.hotKey = savedHotKey
    UserDefaults.standard.ignoreEvents = savedIgnoreEvents
    UserDefaults.standard.pasteByDefault = savedPasteByDefault
    UserDefaults.standard.saratovSeparator = savedSaratovSeparator
    UserDefaults.standard.showInStatusBar = savedShowInStatusBar
    UserDefaults.standard.size = savedSize
    UserDefaults.standard.storage = savedStorage
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
  }

  func testChanging() {
    let item = HistoryItem(typesWithData: [.string: "foo".data(using: .utf8)!])

    UserDefaults.standard.fuzzySearch = true
    UserDefaults.standard.hotKey = "command+shift+a"
    UserDefaults.standard.ignoreEvents = true
    UserDefaults.standard.pasteByDefault = true
    UserDefaults.standard.saratovSeparator = true
    UserDefaults.standard.showInStatusBar = false
    UserDefaults.standard.size = 100
    UserDefaults.standard.storage = [item]

    XCTAssertEqual(UserDefaults.standard.fuzzySearch, true)
    XCTAssertEqual(UserDefaults.standard.hotKey, "command+shift+a")
    XCTAssertEqual(UserDefaults.standard.ignoreEvents, true)
    XCTAssertEqual(UserDefaults.standard.pasteByDefault, true)
    XCTAssertEqual(UserDefaults.standard.saratovSeparator, true)
    XCTAssertEqual(UserDefaults.standard.showInStatusBar, false)
    XCTAssertEqual(UserDefaults.standard.size, 100)
    XCTAssertEqual(UserDefaults.standard.storage, [item])
  }
}

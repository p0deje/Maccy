import XCTest
@testable import Maccy

// swiftlint:disable force_cast
class MenuFooterTests: XCTestCase {
  let savedHideFooter = UserDefaults.standard.hideFooter

  let expected: KeyValuePairs<String, [String: Any]> = [
    "separator": [
      "isAlternate": false,
      "keyEquivalent": "",
      "keyEquivalentModifierMask": NSEvent.ModifierFlags([]),
      "tag": 100,
      "title": "",
      "tooltip": ""
    ],
    "clear": [
      "isAlternate": false,
      "keyEquivalent": "⌫",
      "keyEquivalentModifierMask": NSEvent.ModifierFlags([.command, .option]),
      "tag": 101,
      "title": "Clear",
      "tooltip": "Clear unpinned items.\nSelect with ⇧ to clear all."
    ],
    "clear_all": [
      "isAlternate": true,
      "keyEquivalent": "⌫",
      "keyEquivalentModifierMask": NSEvent.ModifierFlags([.command, .option, .shift]),
      "tag": 106,
      "title": "Clear all",
      "tooltip": "Clear all items."
    ],
    "preferences": [
      "isAlternate": false,
      "keyEquivalent": ",",
      "keyEquivalentModifierMask": NSEvent.ModifierFlags([.command]),
      "tag": 107,
      "title": "Preferences…",
      "tooltip": ""
    ],
    "about": [
      "isAlternate": false,
      "keyEquivalent": "",
      "keyEquivalentModifierMask": NSEvent.ModifierFlags([]),
      "tag": 103,
      "title": "About",
      "tooltip": "Read more about application."
    ],
    "quit": [
      "isAlternate": false,
      "keyEquivalent": "q",
      "keyEquivalentModifierMask": NSEvent.ModifierFlags([.command]),
      "tag": 104,
      "title": "Quit",
      "tooltip": "Quit application."
    ]
  ]

  var actual: [NSMenuItem] { MenuFooter.allCases.map({ $0.menuItem }) }

  override func setUp() {
    super.setUp()
    UserDefaults.standard.hideFooter = false
  }

  override func tearDown() {
    super.tearDown()
    UserDefaults.standard.hideFooter = savedHideFooter
  }

  func testIsAlternate() {
    XCTAssertEqual(actual.map({ $0.isAlternate }), expected.map({ $1["isAlternate"] as! Bool }))
  }

  func testKeyEquivalent() {
    XCTAssertEqual(actual.map({ $0.keyEquivalent }), expected.map({ $1["keyEquivalent"] as! String }))
  }

  func testKeyEquivalentModifierMask() {
    XCTAssertEqual(actual.map({ $0.keyEquivalentModifierMask }),
                   expected.map({ $1["keyEquivalentModifierMask"] as! NSEvent.ModifierFlags }))
  }

  func testTag() {
    XCTAssertEqual(actual.map({ $0.tag }), expected.map({ $1["tag"] as! Int }))
  }

  func testTitle() {
    XCTAssertEqual(actual.map({ $0.title }), expected.map({ $1["title"] as! String }))
  }

  func testTooltip() {
    XCTAssertEqual(actual.map({ $0.toolTip }), expected.map({ $1["tooltip"] as! String }))
  }

  func testHiddenFooter() {
    UserDefaults.standard.hideFooter = true
    XCTAssertEqual(Set(actual.map({ $0.isAlternate })), [false])
    XCTAssertEqual(Set(actual.map({ $0.isHidden })), [true])
  }
}
// swiftlint:enable force_cast

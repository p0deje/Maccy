import XCTest
import Defaults
@testable import Maccy

@MainActor
class KeyChordTests: XCTestCase {
  let savedMultiSelectionEnabled = Defaults[.multiSelectionEnabled]

  override func tearDown() {
    super.tearDown()
    Defaults[.multiSelectionEnabled] = savedMultiSelectionEnabled
  }

  func testShiftArrowsMoveWhenMultiSelectionIsDisabled() {
    Defaults[.multiSelectionEnabled] = false
    XCTAssertEqual(KeyChord(.downArrow, [.shift]), .moveToNext)
    XCTAssertEqual(KeyChord(.upArrow, [.shift]), .moveToPrevious)
    XCTAssertEqual(KeyChord(.downArrow, [.command, .shift]), .moveToLast)
    XCTAssertEqual(KeyChord(.upArrow, [.command, .shift]), .moveToFirst)
  }

  func testShiftArrowsExtendSelectionWhenMultiSelectionIsEnabled() {
    Defaults[.multiSelectionEnabled] = true
    XCTAssertEqual(KeyChord(.downArrow, [.shift]), .extendToNext)
    XCTAssertEqual(KeyChord(.upArrow, [.shift]), .extendToPrevious)
    XCTAssertEqual(KeyChord(.downArrow, [.command, .shift]), .extendToLast)
    XCTAssertEqual(KeyChord(.upArrow, [.command, .shift]), .extendToFirst)
  }
}

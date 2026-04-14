import XCTest
import SwiftUI
@testable import Maccy

class TagColorTests: XCTestCase {
  func testAllCasesCount() {
    // 7 Finder colors + none
    XCTAssertEqual(TagColor.allCases.count, 8)
  }

  func testRawValues() {
    XCTAssertEqual(TagColor.none.rawValue, "none")
    XCTAssertEqual(TagColor.red.rawValue, "red")
    XCTAssertEqual(TagColor.orange.rawValue, "orange")
    XCTAssertEqual(TagColor.yellow.rawValue, "yellow")
    XCTAssertEqual(TagColor.green.rawValue, "green")
    XCTAssertEqual(TagColor.blue.rawValue, "blue")
    XCTAssertEqual(TagColor.purple.rawValue, "purple")
    XCTAssertEqual(TagColor.gray.rawValue, "gray")
  }

  func testNoneColorIsClear() {
    XCTAssertEqual(TagColor.none.color, .clear)
  }

  func testIdentifiable() {
    XCTAssertEqual(TagColor.red.id, "red")
    XCTAssertEqual(TagColor.blue.id, "blue")
  }

  func testCodable() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let original: TagColor = .purple
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(TagColor.self, from: data)
    XCTAssertEqual(decoded, original)
  }

  func testCodableDictionary() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let dict: [String: TagColor] = ["work": .blue, "personal": .green]
    let data = try encoder.encode(dict)
    let decoded = try decoder.decode([String: TagColor].self, from: data)
    XCTAssertEqual(decoded, dict)
  }
}

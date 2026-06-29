import XCTest
@testable import Maccy

/// Tests that DTO projection functions faithfully round-trip `HistoryItem` fields.
@MainActor
class DtoRoundTripTests: XCTestCase {
  /// `snapshot(of:)` projects the lightweight scalar fields of a `HistoryItem`.
  func testSnapshotProjectsLightweightHistoryItemFields() {
    let copiedAt = Date(timeIntervalSince1970: 1_717_171_717)
    let item = HistoryBuilder()
      .withContent(type: "public.utf8-plain-text", value: Data("hello".utf8))
      .withApplication("org.example.App")
      .withCopiedAt(copiedAt)
      .withNumberOfCopies(3)
      .withPin("a")
      .withTitle("hello")
      .build()

    let dto = snapshot(of: item)

    XCTAssertEqual(dto.title, "hello")
    XCTAssertEqual(dto.firstCopiedAt, copiedAt)
    XCTAssertEqual(dto.lastCopiedAt, copiedAt)
    XCTAssertEqual(dto.numberOfCopies, 3)
    XCTAssertEqual(dto.pin, "a")
    XCTAssertEqual(dto.application, "org.example.App")
    XCTAssertEqual(dto.textPreview, "hello")
    XCTAssertNil(dto.imageFingerprint)
  }

  /// `contentDTOs(of:)` preserves each content entry's type, value, and size.
  func testContentProjectionPreservesContentShape() {
    let text = Data("hello".utf8)
    let item = HistoryBuilder()
      .withContent(type: "public.utf8-plain-text", value: text)
      .withContent(type: "public.png", value: nil)
      .build()

    let dtos = contentDTOs(of: item)

    XCTAssertEqual(dtos, [
      ContentDTO(type: "public.utf8-plain-text", value: text, fingerprint: nil, size: 5),
      ContentDTO(type: "public.png", value: nil, fingerprint: nil, size: 0)
    ])
  }

  /// Projecting the same model twice yields a stable DTO id.
  func testProjectedItemIDIsStableForSameModelIdentifier() {
    let item = HistoryBuilder()
      .withContent(type: "public.utf8-plain-text", value: Data("hello".utf8))
      .build()

    XCTAssertEqual(snapshot(of: item).id, snapshot(of: item).id)
  }
}

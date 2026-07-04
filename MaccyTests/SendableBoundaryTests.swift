import XCTest
@testable import Maccy

/// Locks the cross-actor `Sendable` boundary — the invariant that every type
/// crossing from the off-main ingest actor to the main observer is `Sendable`.
///
/// Placing each payload's metatype into an `[any Sendable.Type]` array is a
/// compile-time assertion: a type that is not `Sendable` fails to convert to
/// `any Sendable.Type`, so this file (and therefore CI) fails to compile if
/// any payload type loses its conformance.
final class SendableBoundaryTests: XCTestCase {
  func testCrossActorPayloadsAreSendable() {
    let sendableTypes: [any Sendable.Type] = [
      ItemSnapshotDTO.self,
      ContentDTO.self,
      ClipboardItemDTO.self,
      SignatureDTO.self,
      ContentSignatureEntry.self,
      MaccyFingerprint.self,
      StoreEvent.self,
      IngestRequest.self,
      IngestResult.self,
      IngestMetrics.self,
      CopyOrigin.self
    ]

    XCTAssertEqual(sendableTypes.count, 11)
  }
}

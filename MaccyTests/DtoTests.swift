import XCTest
@testable import Maccy

class DtoTests: XCTestCase {
  func testDtoTypesAreSendable() {
    requireSendable(ContentDTO.self)
    requireSendable(ClipboardItemDTO.self)
    requireSendable(CopyOrigin.self)
    requireSendable(SignatureDTO.self)
    requireSendable(ContentSignatureEntry.self)
    requireSendable(MaccyFingerprint.self)
    requireSendable(ItemSnapshotDTO.self)
    requireSendable(StoreEvent.self)
    requireSendable(IngestRequest.self)
    requireSendable(IngestPlan.self)
    requireSendable(IngestResult.self)
    requireSendable(IngestMetrics.self)
  }

  func testSignatureDtoUsesContentShapeForEquality() {
    let entry = ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 42, size: 12)
    let signature = SignatureDTO(entries: [entry])

    XCTAssertEqual(signature, SignatureDTO(entries: [entry]))
    XCTAssertNotEqual(
      signature,
      SignatureDTO(entries: [
        ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 43, size: 12)
      ])
    )
  }

  func testIngestResultCarriesEventAndMetrics() {
    let itemID = UUID()
    let copiedAt = Date(timeIntervalSince1970: 1_717_171_717)
    let signature = SignatureDTO(entries: [
      ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 42, size: 10)
    ])
    let snapshot = ItemSnapshotDTO(
      id: itemID,
      title: "Copied text",
      firstCopiedAt: copiedAt,
      lastCopiedAt: copiedAt,
      numberOfCopies: 1,
      pin: nil,
      application: "org.example.App",
      textPreview: "Copied text",
      imageFingerprint: nil,
      signature: signature
    )

    let result = IngestResult(
      event: .added(snapshot),
      metrics: IngestMetrics(dedupHits: 1, bytesHashed: 64, parseMs: 0.25)
    )

    XCTAssertEqual(result.event, .added(snapshot))
    XCTAssertEqual(result.metrics.dedupHits, 1)
    XCTAssertEqual(result.metrics.bytesHashed, 64)
    XCTAssertEqual(result.metrics.parseMs, 0.25)
  }

  private func requireSendable<T: Sendable>(_ type: T.Type) {}
}

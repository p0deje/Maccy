import XCTest
@testable import Maccy

class SignatureIndexTests: XCTestCase {
  func testLookupReturnsRegisteredID() {
    let itemID = UUID()
    var index = SignatureIndex()

    index.register(textSignature, id: itemID)

    XCTAssertEqual(index.lookup(textSignature), itemID)
  }

  func testSignatureEntriesAreOrderIndependent() {
    let itemID = UUID()
    var index = SignatureIndex()

    index.register(mixedSignature, id: itemID)

    XCTAssertEqual(index.lookup(reorderedMixedSignature), itemID)
  }

  func testRemoveDeletesAllSignaturesForID() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.bulkRegister([
      (textSignature, itemID),
      (imageSignature, itemID)
    ])

    index.remove(id: itemID)

    XCTAssertNil(index.lookup(textSignature))
    XCTAssertNil(index.lookup(imageSignature))
  }

  func testBulkRegisterBuildsIndex() {
    let textID = UUID()
    let imageID = UUID()

    let index = SignatureIndex([
      (textSignature, textID),
      (imageSignature, imageID)
    ])

    XCTAssertEqual(index.lookup(textSignature), textID)
    XCTAssertEqual(index.lookup(imageSignature), imageID)
  }

  func testRegisterMovesSignatureToNewID() {
    let oldID = UUID()
    let newID = UUID()
    var index = SignatureIndex()

    index.register(textSignature, id: oldID)
    index.register(textSignature, id: newID)
    index.remove(id: oldID)

    XCTAssertEqual(index.lookup(textSignature), newID)
  }

  func testInitFromSnapshotsRebuildsIndex() {
    let snapshot = makeSnapshot(id: UUID(), signature: textSignature)

    let index = SignatureIndex(from: [snapshot])

    XCTAssertEqual(index.lookup(textSignature), snapshot.id)
  }

  func testMergeAddedRegistersSignature() {
    let snapshot = makeSnapshot(id: UUID(), signature: textSignature)
    var index = SignatureIndex()

    index.merge(.added(snapshot))

    XCTAssertEqual(index.lookup(textSignature), snapshot.id)
  }

  func testMergeMergedRegistersSignature() {
    let snapshot = makeSnapshot(id: UUID(), signature: textSignature)
    var index = SignatureIndex()

    index.merge(.merged(snapshot))

    XCTAssertEqual(index.lookup(textSignature), snapshot.id)
  }

  func testMergeRemovedUnregisters() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)

    index.merge(.removed(itemID))

    XCTAssertNil(index.lookup(textSignature))
  }

  func testMergeClearedResets() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)

    index.merge(.cleared)

    XCTAssertNil(index.lookup(textSignature))
  }

  func testCandidatesReturnsIDForExactMatch() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)

    let request = IngestRequest(
      source: CopyOrigin(changeCount: 1),
      contents: [
        ContentDTO(
          type: "public.utf8-plain-text",
          value: nil,
          fingerprint: 100,
          size: 12
        )
      ],
      application: nil,
      now: Date(timeIntervalSince1970: 0)
    )

    XCTAssertEqual(index.candidates(for: request), [itemID])
  }

  func testCandidatesReturnsEmptyForNoMatch() {
    var index = SignatureIndex()
    index.register(textSignature, id: UUID())

    let request = IngestRequest(
      source: CopyOrigin(changeCount: 1),
      contents: [
        ContentDTO(
          type: "public.png",
          value: nil,
          fingerprint: 999,
          size: 64
        )
      ],
      application: nil,
      now: Date(timeIntervalSince1970: 0)
    )

    XCTAssertEqual(index.candidates(for: request), [])
  }

  // MARK: - Per-entry containment candidates (BS-4.2)

  private var textEntry: ContentSignatureEntry {
    ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 100, size: 12)
  }

  private var imageEntry: ContentSignatureEntry {
    ContentSignatureEntry(type: "public.png", fingerprint: 200, size: 64)
  }

  /// A superset item (string + image) must surface when only its string entry is
  /// queried — this is the containment case the old exact-match index missed and the
  /// reason a per-entry index is required (otherwise re-copying plain text after a
  /// rich copy of the same text would create a duplicate instead of merging).
  func testCandidatesForEntriesReturnsSupersetItem() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(mixedSignature, id: itemID)

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [itemID])
  }

  func testCandidatesForEntriesReturnsExactItem() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [itemID])
  }

  /// Genuinely-new content (no shared entry) yields no candidates — the O(1) fast
  /// path that lets the actor skip the full-table scan for the common case.
  func testCandidatesForEntriesEmptyForNovelContent() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(imageSignature, id: itemID)

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [])
  }

  /// An item matching on several entries is returned once, not once per entry.
  func testCandidatesForEntriesDedupesOverlap() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(mixedSignature, id: itemID)

    XCTAssertEqual(index.candidates(forEntries: [textEntry, imageEntry]), [itemID])
  }

  /// Multiple items sharing an entry all surface as candidates (confirm narrows them).
  func testCandidatesForEntriesReturnsAllSharingItems() {
    let idA = UUID()
    let idB = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: idA)
    index.register(textSignature, id: idB)

    XCTAssertEqual(Set(index.candidates(forEntries: [textEntry])), Set([idA, idB]))
  }

  func testRemoveClearsEntryCandidates() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)
    index.remove(id: itemID)

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [])
  }

  /// After a full signature moves to a new id, the old id's per-entry membership is
  /// gone too (no stale candidates).
  func testRegisterMoveThenRemoveOldIDClearsEntryCandidates() {
    let oldID = UUID()
    let newID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: oldID)
    index.register(textSignature, id: newID)
    index.remove(id: oldID)

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [newID])
  }

  func testInitFromSnapshotsBuildsEntryIndex() {
    let snapshot = makeSnapshot(id: UUID(), signature: textSignature)
    let index = SignatureIndex(from: [snapshot])

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [snapshot.id])
  }

  func testMergeAddedRegistersEntryCandidates() {
    let snapshot = makeSnapshot(id: UUID(), signature: textSignature)
    var index = SignatureIndex()
    index.merge(.added(snapshot))

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [snapshot.id])
  }

  func testMergeRemovedClearsEntryCandidates() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)
    index.merge(.removed(itemID))

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [])
  }

  func testMergeClearedClearsEntryCandidates() {
    let itemID = UUID()
    var index = SignatureIndex()
    index.register(textSignature, id: itemID)
    index.merge(.cleared)

    XCTAssertEqual(index.candidates(forEntries: [textEntry]), [])
  }

  private var textSignature: SignatureDTO {
    SignatureDTO(entries: [
      ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 100, size: 12)
    ])
  }

  private var imageSignature: SignatureDTO {
    SignatureDTO(entries: [
      ContentSignatureEntry(type: "public.png", fingerprint: 200, size: 64)
    ])
  }

  private var mixedSignature: SignatureDTO {
    SignatureDTO(entries: [
      ContentSignatureEntry(type: "public.png", fingerprint: 200, size: 64),
      ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 100, size: 12)
    ])
  }

  private var reorderedMixedSignature: SignatureDTO {
    SignatureDTO(entries: [
      ContentSignatureEntry(type: "public.utf8-plain-text", fingerprint: 100, size: 12),
      ContentSignatureEntry(type: "public.png", fingerprint: 200, size: 64)
    ])
  }

  private func makeSnapshot(id: ItemID, signature: SignatureDTO) -> ItemSnapshotDTO {
    let timestamp = Date(timeIntervalSince1970: 1_717_171_717)
    return ItemSnapshotDTO(
      id: id,
      persistentID: nil,
      title: "Sample",
      firstCopiedAt: timestamp,
      lastCopiedAt: timestamp,
      numberOfCopies: 1,
      pin: nil,
      application: nil,
      textPreview: "Sample",
      imageFingerprint: nil,
      signature: signature
    )
  }
}

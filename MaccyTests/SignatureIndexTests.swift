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
}

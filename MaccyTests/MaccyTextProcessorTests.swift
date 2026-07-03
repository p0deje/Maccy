import XCTest
@testable import Maccy

/// Bridge-level tests for `MaccyTextProcessor` — the ObjC++ facade over the
/// C++ UTF-8 prefix and xxh3 fingerprint processors.
///
/// These pin the UTF-8 state machine's boundary behavior (so defensive
/// rewrites inside the C++ layer cannot silently regress it) and the
/// empty-input stability of the fingerprint (the contract that makes the
/// persisted fingerprint column well-defined for any payload size).
final class MaccyTextProcessorTests: XCTestCase {

  // MARK: UTF-8 prefix boundary

  /// Empty input yields a zero-length prefix.
  func testValidUTF8PrefixOfEmptyDataIsZero() {
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: Data(), maxBytes: 16), 0)
  }

  /// A zero `maxBytes` cap yields a zero-length prefix regardless of input.
  func testValidUTF8PrefixWithZeroMaxBytesIsZero() {
    let payload = Data("hello".utf8)
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: payload, maxBytes: 0), 0)
  }

  /// An overlong encoding (`0xC0 0x80`, which encodes U+0000 in more than the
  /// minimal one byte) is rejected — the prefix stops before it.
  func testValidUTF8PrefixRejectsOverlongEncoding() {
    let overlong = Data([0xC0, 0x80])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: overlong, maxBytes: 2), 0)
  }

  /// An encoding of a UTF-16 surrogate (`0xED 0xA0 0x80` = U+D800) is rejected.
  func testValidUTF8PrefixRejectsSurrogate() {
    let surrogate = Data([0xED, 0xA0, 0x80])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: surrogate, maxBytes: 3), 0)
  }

  /// An encoding above U+10FFFF (`0xF4 0x90 0x80 0x80` = U+110000) is rejected.
  func testValidUTF8PrefixRejectsCodePointAboveUnicodeRange() {
    let outOfRange = Data([0xF4, 0x90, 0x80, 0x80])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: outOfRange, maxBytes: 4), 0)
  }

  /// A valid two-byte sequence ("é", U+00E9) counts fully within `maxBytes`.
  func testValidUTF8PrefixAcceptsValidTwoByteSequence() {
    let accentedE = Data([0xC3, 0xA9])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: accentedE, maxBytes: 2), 2)
  }

  /// A multi-byte sequence truncated below `maxBytes` contributes nothing — the
  /// prefix stops at the last complete character.
  func testValidUTF8PrefixStopsAtTruncatedMultiByte() {
    let truncated = Data([0xC3])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: truncated, maxBytes: 2), 0)
  }

  /// A leading continuation byte is not a valid sequence start.
  func testValidUTF8PrefixRejectsLeadingContinuationByte() {
    let continuation = Data([0x80])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: continuation, maxBytes: 1), 0)
  }

  /// `maxBytes` truncates between complete characters: "a" followed by the
  /// start of "é", capped at one byte, yields just "a".
  func testValidUTF8PrefixHonorsMaxBytesBetweenCharacters() {
    let mixed = Data([0x61, 0xC3, 0xA9])
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: mixed, maxBytes: 1), 1)
    XCTAssertEqual(MaccyTextProcessor.validUTF8PrefixLength(in: mixed, maxBytes: 3), 3)
  }

  // MARK: Fingerprint empty-input stability

  /// The fingerprint of empty input is well-defined and stable across calls —
  /// the contract that makes the persisted column consistent for any size.
  func testFingerprintForEmptyDataIsStableAcrossCalls() {
    let first = MaccyTextProcessor.fingerprint(for: Data())
    let second = MaccyTextProcessor.fingerprint(for: Data())
    XCTAssertEqual(first, second)
  }
}

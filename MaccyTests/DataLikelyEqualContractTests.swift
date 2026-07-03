import XCTest
@testable import Maccy

/// Contract tests for the dedup fingerprint comparison in
/// `ClipboardDataProcessor`: `dataLikelyEqual` and `fingerprintIfLarge`.
///
/// These tests pin the comparison's behavior across each of its decision
/// points — the byte-length gate, the 16 KiB fingerprint threshold, the
/// nil-fingerprint fallback to a full equality check, and the collision-safe
/// confirmation that runs a full `==` even when both fingerprints match. They
/// also verify that the fingerprint is stable across calls, which is what
/// makes a value stored in the persisted fingerprint column valid from one
/// process launch to the next.
final class DataLikelyEqualContractTests: XCTestCase {
  /// One byte below the 16 KiB fingerprint threshold (compared by full equality).
  private let subThresholdSize = 16 * 1_024 - 1
  /// Exactly at the threshold (compared via fingerprint).
  private let thresholdSize = 16 * 1_024

  // MARK: Byte-length gate

  /// Payloads of different byte lengths are never equal, regardless of
  /// fingerprints.
  func testMismatchedSizesAreRejectedEvenWithMatchingFingerprints() {
    let lhs = Data(count: thresholdSize)
    let rhs = Data(count: thresholdSize + 1)

    XCTAssertFalse(ClipboardDataProcessor.dataLikelyEqual(lhs, 1, rhs, 1))
  }

  // MARK: Fingerprint threshold boundary

  /// Content below the 16 KiB threshold ignores fingerprints and compares by
  /// full equality.
  func testSubThresholdContentIgnoresFingerprints() {
    let lhs = Data(repeating: 0x41, count: subThresholdSize)
    let rhs = Data(repeating: 0x42, count: subThresholdSize)

    // Same bytes are equal even with nil or mismatched fingerprints.
    XCTAssertTrue(ClipboardDataProcessor.dataLikelyEqual(lhs, nil, lhs, nil))
    XCTAssertTrue(ClipboardDataProcessor.dataLikelyEqual(lhs, 1, lhs, 2))
    // Different bytes are not equal.
    XCTAssertFalse(ClipboardDataProcessor.dataLikelyEqual(lhs, nil, rhs, nil))
  }

  /// Content at exactly the 16 KiB threshold takes the fingerprint path:
  /// mismatched fingerprints reject even identical bytes.
  func testAtThresholdContentUsesFingerprintPath() {
    let lhs = Data(repeating: 0x41, count: thresholdSize)

    XCTAssertFalse(ClipboardDataProcessor.dataLikelyEqual(lhs, 1, lhs, 2))
    XCTAssertTrue(ClipboardDataProcessor.dataLikelyEqual(lhs, 1, lhs, 1))
  }

  // MARK: Nil-fingerprint fallback

  /// A nil fingerprint on either side at or above the threshold falls back to a
  /// full equality check. This covers small content (which never stores a
  /// fingerprint) and any large row whose persisted column has not yet been
  /// populated.
  func testNilFingerprintOnEitherSideFallsBackToFullEquality() {
    let lhs = Data(repeating: 0x41, count: thresholdSize)
    let rhs = Data(repeating: 0x42, count: thresholdSize)

    XCTAssertTrue(ClipboardDataProcessor.dataLikelyEqual(lhs, nil, lhs, 1))
    XCTAssertTrue(ClipboardDataProcessor.dataLikelyEqual(lhs, 1, lhs, nil))
    XCTAssertFalse(ClipboardDataProcessor.dataLikelyEqual(lhs, nil, rhs, 1))
  }

  // MARK: Collision safety

  /// Forged matching fingerprints with different bytes return false: a hash
  /// match never short-circuits — the final full equality check catches the
  /// difference.
  func testForgedMatchingFingerprintWithDifferentDataReturnsFalse() {
    let lhs = Data(repeating: 0x41, count: thresholdSize)
    let rhs = Data(repeating: 0x42, count: thresholdSize)

    XCTAssertFalse(ClipboardDataProcessor.dataLikelyEqual(lhs, 0xDEAD_BEEF, rhs, 0xDEAD_BEEF))
  }

  /// Forged matching fingerprints with identical bytes return true.
  func testForgedMatchingFingerprintWithSameDataReturnsTrue() {
    let lhs = Data(repeating: 0x41, count: thresholdSize)

    XCTAssertTrue(ClipboardDataProcessor.dataLikelyEqual(lhs, 0xDEAD_BEEF, lhs, 0xDEAD_BEEF))
  }

  /// Distinct fingerprints reject without a full byte compare.
  func testDistinctFingerprintsRejectEvenForEqualData() {
    let lhs = Data(repeating: 0x41, count: thresholdSize)

    XCTAssertFalse(ClipboardDataProcessor.dataLikelyEqual(lhs, 1, lhs, 2))
  }

  // MARK: fingerprintIfLarge helper and determinism

  /// `fingerprintIfLarge` returns nil below the threshold and a value at or
  /// above it.
  func testFingerprintIfLargeThresholdBoundary() {
    XCTAssertNil(ClipboardDataProcessor.fingerprintIfLarge(Data(count: subThresholdSize)))
    XCTAssertNotNil(ClipboardDataProcessor.fingerprintIfLarge(Data(count: thresholdSize)))
  }

  /// Identical bytes produce identical fingerprints across calls. The
  /// fingerprint seed is a fixed compile-time constant, so a value stored in
  /// the persisted column stays valid across process launches; a per-process
  /// random seed would invalidate every stored fingerprint on restart.
  func testFingerprintIsDeterministicAcrossCalls() {
    let payload = Data(repeating: 0x41, count: thresholdSize)

    let firstFp = ClipboardDataProcessor.fingerprintIfLarge(payload)
    let secondFp = ClipboardDataProcessor.fingerprintIfLarge(payload)

    XCTAssertNotNil(firstFp)
    XCTAssertEqual(firstFp, secondFp)
  }

  /// Different large content produces different fingerprints.
  func testFingerprintsDifferForDifferentLargeContent() {
    let lhs = Data(repeating: 0x41, count: thresholdSize)
    let rhs = Data(repeating: 0x42, count: thresholdSize)

    let firstFp = ClipboardDataProcessor.fingerprintIfLarge(lhs)
    let secondFp = ClipboardDataProcessor.fingerprintIfLarge(rhs)

    XCTAssertNotEqual(firstFp, secondFp)
  }
}

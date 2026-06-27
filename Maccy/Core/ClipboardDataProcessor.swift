import Foundation

enum ClipboardDataProcessor {
  private static let largeContentFingerprintThreshold = 16 * 1_024

  static func stringPrefix(_ data: Data, maxBytes: Int, encoding: String.Encoding = .utf8) -> String? {
    guard maxBytes > 0 else {
      return ""
    }

    let prefixLength = Int(MaccyTextProcessor.validUTF8PrefixLength(
      in: data,
      maxBytes: UInt(maxBytes)
    ))

    guard prefixLength > 0 || data.isEmpty else {
      return nil
    }

    guard prefixLength < data.count else {
      return String(data: data, encoding: encoding)
    }

    return String(data: data.prefix(prefixLength), encoding: encoding)
  }

  /// BS-8 (08-F-009/08-F-001): symmetric — BOTH fingerprints are required (no
  /// default params), so `dataLikelyEqual` never re-hashes. Callers read the lhs
  /// fingerprint from the persisted `HistoryItemContent.fingerprint` column (or
  /// compute the rhs once). `nil` = small content (< threshold, no fingerprint)
  /// or a pre-migration row; large content with a nil fingerprint falls back to
  /// a full `==` compare (correct, just slower for old rows).
  static func dataLikelyEqual(
    _ lhs: Data,
    _ lhsFingerprint: UInt64?,
    _ rhs: Data,
    _ rhsFingerprint: UInt64?
  ) -> Bool {
    guard lhs.count == rhs.count else {
      return false
    }

    guard lhs.count >= largeContentFingerprintThreshold else {
      return lhs == rhs
    }

    guard let lhsFingerprint, let rhsFingerprint else {
      return lhs == rhs
    }

    guard lhsFingerprint == rhsFingerprint else {
      return false
    }

    return lhs == rhs
  }

  static func fingerprintIfLarge(_ data: Data) -> UInt64? {
    guard data.count >= largeContentFingerprintThreshold else {
      return nil
    }

    return MaccyTextProcessor.fingerprint(for: data)
  }
}

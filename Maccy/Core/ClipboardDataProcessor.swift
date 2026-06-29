import Foundation

/// Pure helpers for clipboard text/image bytes: UTF-8-safe prefixing and the
/// dedup fingerprint comparison.
enum ClipboardDataProcessor {
  /// Content at or above this byte length is given a persisted fingerprint;
  /// below it, dedup compares by full `==`.
  private static let largeContentFingerprintThreshold = 16 * 1_024

  /// Returns a UTF-8-safe prefix of `data` no longer than `maxBytes` bytes.
  ///
  /// Cuts on a UTF-8 boundary via `MaccyTextProcessor.validUTF8PrefixLength`
  /// so the result never contains a partial code unit. Returns nil for non-UTF-8
  /// data (when the prefix length is 0 but the data is non-empty).
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

  /// Compares two payloads for dedup-equality, using fingerprints to avoid a
  /// full byte compare on large content.
  ///
  /// Both fingerprints are required (no default params), so this function never
  /// re-hashes: callers read the lhs fingerprint from the persisted
  /// `HistoryItemContent.fingerprint` column and compute the rhs once. A `nil`
  /// fingerprint means small content (below the threshold, so no fingerprint is
  /// stored) or a pre-migration row whose column was never populated — in either
  /// case the function falls back to a full `==` compare. Correctness is
  /// unaffected; the cost is that pre-migration large rows are re-hashed on
  /// every dedup-index build because no write-back backfill ever populated their
  /// column (that step was not implemented).
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

  /// Returns the dedup fingerprint for `data` when it is large enough to warrant
  /// one, otherwise nil.
  static func fingerprintIfLarge(_ data: Data) -> UInt64? {
    guard data.count >= largeContentFingerprintThreshold else {
      return nil
    }

    return MaccyTextProcessor.fingerprint(for: data)
  }
}

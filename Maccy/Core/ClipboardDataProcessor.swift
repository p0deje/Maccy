import Foundation

enum ClipboardDataProcessor {
  private static let largeContentFingerprintThreshold = 16 * 1_024

  static func stringPrefix(_ data: Data, maxBytes: Int, encoding: String.Encoding = .utf8) -> String? {
    guard maxBytes > 0 else {
      return ""
    }

    guard encoding == .utf8 else {
      return legacyStringPrefix(data, maxBytes: maxBytes, encoding: encoding)
    }

    let prefixLength = MaccyTextProcessor.validUTF8PrefixLength(
      in: data,
      maxBytes: maxBytes
    )

    guard prefixLength > 0 || data.isEmpty else {
      return nil
    }

    guard prefixLength < data.count else {
      return String(data: data, encoding: encoding)
    }

    return String(data: data.prefix(prefixLength), encoding: encoding)
  }

  static func dataLikelyEqual(_ lhs: Data?, _ rhs: Data?) -> Bool {
    guard let lhs, let rhs else {
      return lhs == nil && rhs == nil
    }

    guard lhs.count == rhs.count else {
      return false
    }

    guard lhs.count >= largeContentFingerprintThreshold else {
      return lhs == rhs
    }

    let lhsFingerprint = MaccyTextProcessor.fingerprint(for: lhs)
    let rhsFingerprint = MaccyTextProcessor.fingerprint(for: rhs)
    guard lhsFingerprint == rhsFingerprint else {
      return false
    }

    return lhs == rhs
  }

  private static func legacyStringPrefix(
    _ data: Data,
    maxBytes: Int,
    encoding: String.Encoding
  ) -> String? {
    guard data.count > maxBytes else {
      return String(data: data, encoding: encoding)
    }

    var endIndex = Swift.min(maxBytes, data.count)
    while endIndex > 0 {
      if let string = String(data: data.prefix(endIndex), encoding: encoding) {
        return string
      }
      endIndex -= 1
    }

    return nil
  }
}

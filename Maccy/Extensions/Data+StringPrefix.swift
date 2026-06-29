import Foundation

extension Data {
  /// Returns a string built from the leading bytes (up to `maxBytes`) of this data, decoding with `encoding`.
  func stringPrefix(maxBytes: Int, encoding: String.Encoding = .utf8) -> String? {
    ClipboardDataProcessor.stringPrefix(self, maxBytes: maxBytes, encoding: encoding)
  }
}

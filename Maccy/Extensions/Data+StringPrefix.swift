import Foundation

extension Data {
  func stringPrefix(maxBytes: Int, encoding: String.Encoding = .utf8) -> String? {
    ClipboardDataProcessor.stringPrefix(self, maxBytes: maxBytes, encoding: encoding)
  }
}

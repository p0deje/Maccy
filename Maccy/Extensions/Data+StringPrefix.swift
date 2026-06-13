import Foundation

extension Data {
  func stringPrefix(maxBytes: Int, encoding: String.Encoding = .utf8) -> String? {
    guard maxBytes > 0 else {
      return ""
    }

    guard count > maxBytes else {
      return String(data: self, encoding: encoding)
    }

    var endIndex = Swift.min(maxBytes, count)
    while endIndex > 0 {
      if let string = String(data: Data(prefix(endIndex)), encoding: encoding) {
        return string
      }
      endIndex -= 1
    }

    return nil
  }
}

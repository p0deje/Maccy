import Foundation

nonisolated struct SizedString: Sendable {
  let string: String
  let byteCount: Int
  let isTruncated: Bool

  init(_ string: String, maxParagraphBytes: Int = .max) {
    let bytes = string.utf8
    let shortenedBytes = bytes.shortened(maxParagraphBytes: maxParagraphBytes)
    self.isTruncated = shortenedBytes.endIndex != bytes.endIndex
    self.byteCount = shortenedBytes.count

    if isTruncated {
      self.string = String(bytes: shortenedBytes, encoding: .utf8) ?? ""
    } else {
      self.string = string
    }
  }
}

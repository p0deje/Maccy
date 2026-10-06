extension String {
  func shortened(to maxLength: Int) -> String {
    guard let end = index(startIndex, offsetBy: maxLength, limitedBy: endIndex), end != endIndex else {
      return self
    }

    return String(self[startIndex..<end])
  }
}

extension String.UTF8View {
  nonisolated func shortened(maxParagraphBytes: Int) -> SubSequence {
    let limit = Swift.max(0, maxParagraphBytes)
    var cursor = startIndex
    var paragraphBytes = 0

    while cursor != endIndex {
      if let lineBreakEnd = indexAfterLineBreak(at: cursor) {
        cursor = lineBreakEnd
        paragraphBytes = 0
      } else {
        if paragraphBytes == limit {
          var end = cursor
          // Avoid splitting a Unicode scalar by stepping back over continuation bytes.
          while self[end] & 0xC0 == 0x80 {
            end = index(before: end)
          }
          return self[startIndex..<end]
        }
        paragraphBytes += 1
        formIndex(after: &cursor)
      }
    }

    return self[startIndex..<endIndex]
  }

  private nonisolated func indexAfterLineBreak(at start: Index) -> Index? {
    let next = index(after: start)
    switch self[start] {
    case 0x0A, 0x0B, 0x0C: // LF, vertical tab, form feed
      return next
    case 0x0D: // CR, including CRLF as one line break
      return next != endIndex && self[next] == 0x0A ? index(after: next) : next
    case 0xC2: // U+0085 NEXT LINE
      guard next != endIndex, self[next] == 0x85 else { return nil }
      return index(after: next)
    case 0xE2: // U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR
      guard next != endIndex, self[next] == 0x80 else { return nil }
      let last = index(after: next)
      guard last != endIndex, self[last] == 0xA8 || self[last] == 0xA9 else { return nil }
      return index(after: last)
    default:
      return nil
    }
  }
}

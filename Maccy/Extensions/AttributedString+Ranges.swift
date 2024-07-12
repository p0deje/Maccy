import Foundation

extension AttributedString {
  func ranges(
    of substring: String, 
    options: String.CompareOptions = []
  ) -> [Range<AttributedString.Index>] {
    var ranges: [Range<AttributedString.Index>] = []
    var searchStartIndex = startIndex

    while let range = self[searchStartIndex...].range(of: substring, options: options) {
      ranges.append(range)
      searchStartIndex = range.upperBound
    }

    return ranges
  }
}

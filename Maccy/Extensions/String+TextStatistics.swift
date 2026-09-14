import Foundation

nonisolated struct TextStatistics: Equatable {
  let characters: Int
  let words: Int
  let lines: Int
}

extension String {
  // Words and lines use Foundation's text segmentation rather than splitting
  // on whitespace, so languages written without spaces (e.g. Chinese or
  // Japanese) are counted correctly. This is linear in the text length and
  // takes noticeable time for multi-megabyte strings.
  nonisolated var textStatistics: TextStatistics {
    var words = 0
    var lines = 0
    enumerateSubstrings(in: startIndex..<endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
      words += 1
    }
    enumerateSubstrings(in: startIndex..<endIndex, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
      lines += 1
    }

    return TextStatistics(characters: count, words: words, lines: lines)
  }
}

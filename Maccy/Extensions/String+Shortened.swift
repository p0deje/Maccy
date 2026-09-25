extension String {
  func shortened(to maxLength: Int) -> String {
    // Avoid `count`, which walks the whole string and is slow for very long text.
    guard let end = index(startIndex, offsetBy: maxLength, limitedBy: endIndex),
          end < endIndex else {
      return self
    }

    return String(self[startIndex..<end])
  }
}

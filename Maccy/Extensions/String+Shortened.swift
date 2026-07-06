extension String {
  /// Returns the receiver truncated to at most `maxLength` characters.
  ///
  /// A negative `maxLength` is treated as no truncation. Strings already at or
  /// below the limit are returned unchanged. The length check advances at most
  /// `maxLength` graphemes via `index(_:offsetBy:limitedBy:)` rather than
  /// scanning the whole string with `count`, so truncating a long body to a
  /// small window is O(maxLength) — not O(count), which would re-scan the full
  /// body on every call and dominates the fuzzy body-scan path at scale.
  func shortened(to maxLength: Int) -> String {
    guard maxLength >= 0 else {
      return self
    }
    guard let cutoff = index(startIndex, offsetBy: maxLength, limitedBy: endIndex),
          cutoff != endIndex else {
      return self
    }
    return String(self[..<cutoff])
  }
}

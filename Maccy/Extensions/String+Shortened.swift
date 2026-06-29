extension String {
  /// Returns the receiver truncated to at most `maxLength` characters.
  ///
  /// A negative `maxLength` is treated as no truncation, since
  /// `index(startIndex, offsetBy:)` traps on a negative offset. Strings already at
  /// or below the limit are returned unchanged.
  func shortened(to maxLength: Int) -> String {
    guard maxLength >= 0, count > maxLength else {
      return self
    }

    return String(self[..<index(startIndex, offsetBy: maxLength)])
  }
}

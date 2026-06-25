extension String {
  func shortened(to maxLength: Int) -> String {
    // F4 (master plan): guard negative maxLength — index(startIndex, offsetBy:)
    // traps on a negative offset (and a negative cap is meaningless anyway).
    guard maxLength >= 0, count > maxLength else {
      return self
    }

    return String(self[..<index(startIndex, offsetBy: maxLength)])
  }
}

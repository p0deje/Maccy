extension String {
  func shortened(to maxLength: Int) -> String {
    guard count > maxLength else {
      return self
    }

    return String(self[startIndex..<index(startIndex, offsetBy: maxLength)])
  }
}

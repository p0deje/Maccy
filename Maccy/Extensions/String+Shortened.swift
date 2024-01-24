extension String {
  func shortened(to maxLength: Int) -> String {
    guard count > maxLength else {
      return self
    }

    let thirdMaxLength = maxLength / 3
    let indexStart = index(startIndex, offsetBy: thirdMaxLength * 2)
    let indexEnd = index(endIndex, offsetBy: -(thirdMaxLength + 1))
    return "\(self[...indexStart])...\(self[indexEnd...])"
  }
}

extension Collection where Element: Equatable {
  func item(after: Element) -> Element? {
    guard let currentIndex = firstIndex(of: after) else {
      return nil
    }

    let nextIndex = index(currentIndex, offsetBy: 1)
    if nextIndex < endIndex {
      return self[nextIndex]
    } else {
      return nil
    }
  }

  func item(before: Element) -> Element? {
    guard let currentIndex = firstIndex(of: before) else {
      return nil
    }

    let prevIndex = index(currentIndex, offsetBy: -1)
    if prevIndex >= startIndex {
      return self[prevIndex]
    } else {
      return nil
    }
  }

}

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

  func between(from fromElement: Element, to toElement: Element, inOrder: Bool = false) -> [Element]? {
    guard let fromIndex = firstIndex(of: fromElement) else {
      return nil
    }
    guard let toIndex = firstIndex(of: toElement) else {
      return nil
    }
    let startIndex = Swift.min(fromIndex, toIndex)
    let endIndex = Swift.max(fromIndex, toIndex)
    let items = self[startIndex...endIndex]
    if !inOrder && fromIndex > toIndex {
      return items.reversed()
    } else {
      return Array(items)
    }
  }
}

extension Array where Element: Equatable {
  func nearest(to element: Element, where condition: (Element) -> Bool) -> Element? {
    guard let currentIndex = firstIndex(of: element) else {
      return nil
    }
    let nextNearest = self[currentIndex...].firstIndex(where: { condition($0) })
    let previousNearest = self[...currentIndex].lastIndex(where: { condition($0) })
    switch (nextNearest, previousNearest) {
    case (nil, nil):
      return nil
    case (.some(let index), .none):
      return self[currentIndex + index]
    case (.none, .some(let index)):
      return self[index]
    case (.some(let index1), .some(let index2)):
      let pos1 = currentIndex + index1
      let pos2 = index2
      return abs(pos1 - currentIndex) < abs(pos2 - currentIndex)
      ? self[pos1]
      : self[pos2]
    }

  }
}

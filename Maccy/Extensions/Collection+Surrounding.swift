extension Collection where Element: Equatable {
  /// Returns the first element after `after` (in collection order) that satisfies `predicate`.
  func item(after: Element, where predicate: (Element) -> Bool) -> Element? {
    guard let currentIndex = firstIndex(of: after) else {
      return nil
    }

    var nextIndex = index(currentIndex, offsetBy: 1)
    while nextIndex < endIndex {
      let item = self[nextIndex]
      if predicate(item) {
        return item
      }
      nextIndex = index(nextIndex, offsetBy: 1)
    }
    return nil
  }

  /// Returns the last element before `before` (in reverse collection order) that satisfies `predicate`.
  func item(before: Element, where predicate: (Element) -> Bool) -> Element? {
    guard let currentIndex = firstIndex(of: before) else {
      return nil
    }
    guard currentIndex > startIndex else {
      return nil
    }

    var prevIndex = index(currentIndex, offsetBy: -1)
    while prevIndex >= startIndex {
      let item = self[prevIndex]
      if predicate(item) {
        return item
      }
      prevIndex = index(prevIndex, offsetBy: -1)
    }
    return nil
  }

  /// Returns the inclusive run of elements between `fromElement` and `toElement`.
  ///
  /// When `inOrder` is `false` (the default), the slice is reversed if needed so it
  /// reads from `fromElement` toward `toElement`, regardless of their relative positions.
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
  /// Returns the element nearest to `element` that satisfies `condition`.
  ///
  /// Searches both forward and backward from `element` and returns whichever match is
  /// closest by index distance. Ties favor the forward match.
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
      return self[index]
    case (.none, .some(let index)):
      return self[index]
    case (.some(let index1), .some(let index2)):
      return abs(index1 - currentIndex) < abs(index2 - currentIndex)
      ? self[index1]
      : self[index2]
    }

  }
}

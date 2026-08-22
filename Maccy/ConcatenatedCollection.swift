/// A random-access view over two arrays that does not allocate combined storage.
struct ConcatenatedCollection<Element>: RandomAccessCollection {
  typealias Index = Int

  private let leading: [Element]
  private let trailing: [Element]

  init(_ leading: [Element], _ trailing: [Element]) {
    self.leading = leading
    self.trailing = trailing
  }

  var startIndex: Int { 0 }
  var endIndex: Int { leading.count + trailing.count }

  subscript(position: Int) -> Element {
    precondition(position >= startIndex && position < endIndex, "Index out of bounds")
    if position < leading.count {
      return leading[position]
    }
    return trailing[position - leading.count]
  }

  func index(after index: Int) -> Int {
    index + 1
  }

  func index(before index: Int) -> Int {
    index - 1
  }

  func index(_ index: Int, offsetBy distance: Int) -> Int {
    index + distance
  }

  func distance(from start: Int, to end: Int) -> Int {
    end - start
  }

  func toArray() -> [Element] {
    leading + trailing
  }
}

extension ConcatenatedCollection: Equatable where Element: Equatable {}

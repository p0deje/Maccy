/// A random-access view over two collections that does not allocate combined storage.
/// Segments may themselves be concatenated, building ordered groups without copying.
nonisolated struct ConcatenatedCollection<
  Leading: RandomAccessCollection, Trailing: RandomAccessCollection
>: RandomAccessCollection
where Leading.Element == Trailing.Element, Leading.Index == Int, Trailing.Index == Int {
  typealias Element = Leading.Element
  typealias Index = Int

  private let leading: Leading
  private let trailing: Trailing

  init(_ leading: Leading, _ trailing: Trailing) {
    self.leading = leading
    self.trailing = trailing
  }

  var startIndex: Int { 0 }
  var endIndex: Int { leading.count + trailing.count }

  subscript(position: Int) -> Element {
    precondition(position >= startIndex && position < endIndex, "Index out of bounds")
    if position < leading.count {
      return leading[leading.index(leading.startIndex, offsetBy: position)]
    }
    return trailing[trailing.index(trailing.startIndex, offsetBy: position - leading.count)]
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
    Array(self)
  }
}

extension ConcatenatedCollection: Equatable where Leading: Equatable, Trailing: Equatable {}

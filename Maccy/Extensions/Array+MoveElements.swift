import Foundation

extension Array {
  mutating func moveElements(
    from source: IndexSet,
    to destination: Int
  ) {
    let movingIndexes = source.sorted()
    let movingElements = movingIndexes.compactMap {
      indices.contains($0) ? self[$0] : nil
    }
    guard !movingElements.isEmpty else { return }

    for index in movingIndexes.reversed() where indices.contains(index) {
      remove(at: index)
    }

    let removedBeforeDestination = movingIndexes.filter { $0 < destination }
      .count
    let insertionIndex = Swift.max(
      0,
      Swift.min(destination - removedBeforeDestination, count)
    )
    insert(contentsOf: movingElements, at: insertionIndex)
  }
}

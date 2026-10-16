import Foundation
import Testing
import Defaults
@testable import Maccy

extension SharedStateTests {
  @MainActor
  final class SorterTests {
    let savedPinOrder = Defaults[.pinOrder]
    let savedPinTo = Defaults[.pinTo]
    let sorter = Sorter()

    let item1: HistoryItem
    let item2: HistoryItem
    let item3: HistoryItem

    init() {
      item1 = Self.historyItem(value: "foo", firstCopiedAt: -300, lastCopiedAt: -100, numberOfCopies: 3)
      item2 = Self.historyItem(value: "bar", firstCopiedAt: -400, lastCopiedAt: -300, numberOfCopies: 2)
      item3 = Self.historyItem(value: "bar", firstCopiedAt: -200, lastCopiedAt: -200, numberOfCopies: 1)
      Defaults[.pinOrder] = PinOrder()
    }

    deinit {
      Defaults[.pinOrder] = savedPinOrder
      Defaults[.pinTo] = savedPinTo
    }

    @Test("Sort by last copied at")
    func sortByLastCopiedAt() {
      #expect(sorter.sort([item1, item2, item3], by: .lastCopiedAt) == [item1, item3, item2])
    }

    @Test("Sort by first copied at")
    func sortByFirstCopiedAt() {
      #expect(sorter.sort([item1, item2, item3], by: .firstCopiedAt) == [item3, item1, item2])
    }

    @Test("Sort by number of copies")
    func sortByNumberOfCopies() {
      #expect(sorter.sort([item1, item2, item3], by: .numberOfCopies) == [item1, item2, item3])
    }

    @Test("Pinned items go to the top")
    func sortByPinToTop() {
      Defaults[.pinTo] = .top

      item1.pin = "a"
      item3.pin = "b"
      #expect(sorter.sort([item1, item2, item3], by: .lastCopiedAt) == [item1, item3, item2])
    }

    @Test("Pinned items go to the bottom")
    func sortByPinToBottom() {
      Defaults[.pinTo] = .bottom

      item1.pin = "a"
      item3.pin = "b"
      #expect(sorter.sort([item1, item2, item3], by: .lastCopiedAt) == [item2, item1, item3])
    }

    private static func historyItem(
      value: String,
      firstCopiedAt: Int,
      lastCopiedAt: Int,
      numberOfCopies: Int
    ) -> HistoryItem {
      let contents = [HistoryItemContent(type: "", value: value.data(using: .utf8)!)]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.firstCopiedAt = Date(timeIntervalSinceNow: TimeInterval(firstCopiedAt))
      item.lastCopiedAt = Date(timeIntervalSinceNow: TimeInterval(lastCopiedAt))
      item.numberOfCopies = numberOfCopies
      return item
    }
  }
}

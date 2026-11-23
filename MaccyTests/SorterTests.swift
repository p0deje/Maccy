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

    @Test("Insertion matches stable sorting for every key, including ties and boundaries")
    func insertionMatchesStableSort() {
      let referenceDate = Date(timeIntervalSince1970: 1_000)
      let candidates = (0..<9).map { index in
        let item = Self.historyItem(value: "item \(index)", firstCopiedAt: 0, lastCopiedAt: 0, numberOfCopies: 1)
        item.firstCopiedAt = referenceDate.addingTimeInterval(Double(index % 3))
        item.lastCopiedAt = referenceDate.addingTimeInterval(Double((index * 2) % 3))
        item.numberOfCopies = index % 3
        return HistoryItemDecorator(item)
      }

      for sortBy in Sorter.By.allCases {
        for pinTo in PinsPosition.allCases {
          Defaults[.pinTo] = pinTo
          var inserted: [HistoryItemDecorator] = []
          for candidate in candidates {
            let expected = sorter.sort(inserted.map(\.item) + [candidate.item], by: sortBy)
            let index = sorter.insertionIndex(of: candidate, in: inserted, by: sortBy)
            inserted.insert(candidate, at: index)
            #expect(inserted.map(\.item) == expected)
          }
        }
      }
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

// Opt-in, synthetic component benchmark. No wall-clock performance assertions.
extension SharedStateTests {
  @MainActor
  @Suite(.enabled(if: ProcessInfo.processInfo.environment["MACCY_RUN_BENCHMARKS"] == "1"))
  struct InsertionBenchmarks {
    @Test("Sorted insertion", arguments: [200, 2_000, 10_000])
    func insertion(count: Int) throws {
      let sorter = Sorter()
      let items = (0..<count).map { index in
        let item = HistoryItem(contents: [])
        item.title = "Item \(index)"
        item.lastCopiedAt = Date(timeIntervalSince1970: Double(count - index))
        return HistoryItemDecorator(item)
      }
      let incoming = HistoryItem(contents: [])
      incoming.title = "Incoming"
      incoming.lastCopiedAt = Date(timeIntervalSince1970: Double(count / 2))
      let candidate = HistoryItemDecorator(incoming)
      let expected = sorter.sort(items.map(\.item) + [incoming], by: .lastCopiedAt)
      var checksum = 0
      let start = DispatchTime.now().uptimeNanoseconds
      for _ in 0..<100 {
        var copy = items
        // BENCHMARK_INSERTION_INDEX
        let index = sorter.insertionIndex(of: candidate, in: copy, by: .lastCopiedAt)
        copy.insert(candidate, at: index)
        checksum += index
        #expect(copy.map(\.item) == expected)
      }
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
      let data = try JSONSerialization.data(withJSONObject: [
        "case": "insertion", "count": count, "iterations": 100,
        "elapsed_ms": elapsed, "checksum": checksum
      ], options: [.sortedKeys])
      print("MACCY_BENCHMARK " + String(decoding: data, as: UTF8.self))
    }
  }
}

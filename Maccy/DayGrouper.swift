import Foundation

struct DayGroup: Equatable, Identifiable {
  let date: Date
  let items: [HistoryItemDecorator]
  let itemOffset: Int

  var id: Date { date }
}

enum DayGrouper {
  static func group(
    _ items: [HistoryItemDecorator],
    by: Sorter.By,
    calendar: Calendar = .current
  ) -> [DayGroup] {
    var groups: [DayGroup] = []
    var currentDay: Date?
    var currentItems: [HistoryItemDecorator] = []
    var offset = 0

    for item in items {
      let day = calendar.startOfDay(for: date(for: item, by: by))
      if let currentDay, currentDay != day {
        groups.append(DayGroup(date: currentDay, items: currentItems, itemOffset: offset))
        offset += currentItems.count
        currentItems = [item]
      } else {
        currentItems.append(item)
      }
      currentDay = day
    }

    if let currentDay, !currentItems.isEmpty {
      groups.append(DayGroup(date: currentDay, items: currentItems, itemOffset: offset))
    }

    return groups
  }

  private static func date(for item: HistoryItemDecorator, by: Sorter.By) -> Date {
    switch by {
    case .firstCopiedAt:
      return item.item.firstCopiedAt
    case .lastCopiedAt, .numberOfCopies:
      return item.item.lastCopiedAt
    }
  }
}

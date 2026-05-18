import Foundation

enum HistoryDateGrouper {
  struct Section: Identifiable {
    let id: Date
    let title: String
    let items: [HistoryItemDecorator]
  }

  static func headerTitle(for date: Date, calendar: Calendar = .current) -> String {
    let day = calendar.startOfDay(for: date)
    return title(for: day, calendar: calendar)
  }

  static func shouldShowHeader(for item: HistoryItemDecorator, at index: Int, in items: [HistoryItemDecorator]) -> Bool {
    guard index > 0 else { return true }
    let calendar = Calendar.current
    return !calendar.isDate(
      items[index - 1].item.lastCopiedAt,
      inSameDayAs: item.item.lastCopiedAt
    )
  }

  static func sections(from items: [HistoryItemDecorator]) -> [Section] {
    let calendar = Calendar.current
    var grouped: [Date: [HistoryItemDecorator]] = [:]

    for item in items {
      let day = calendar.startOfDay(for: item.item.lastCopiedAt)
      grouped[day, default: []].append(item)
    }

    return grouped.keys.sorted(by: >).map { day in
      let dayItems = (grouped[day] ?? []).sorted { $0.item.lastCopiedAt > $1.item.lastCopiedAt }
      return Section(id: day, title: title(for: day, calendar: calendar), items: dayItems)
    }
  }

  private static func title(for day: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(day) {
      return NSLocalizedString("Today", tableName: "Localizable", comment: "")
    }
    if calendar.isDateInYesterday(day) {
      return NSLocalizedString("Yesterday", tableName: "Localizable", comment: "")
    }
    return day.formatted(date: .abbreviated, time: .omitted)
  }
}

import XCTest
@testable import Maccy

@MainActor
class DayGrouperTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  func testEmptyItemsProduceNoSections() {
    XCTAssertEqual(DayGrouper.group([], by: .lastCopiedAt, calendar: calendar), [])
  }

  func testSameCalendarDayProducesOneSection() {
    let morning = date(2026, 9, 1, 10, 0)
    let evening = date(2026, 9, 1, 22, 30)
    let items = [
      decorator(title: "morning", lastCopiedAt: evening),
      decorator(title: "evening", lastCopiedAt: morning)
    ]

    let groups = DayGrouper.group(items, by: .lastCopiedAt, calendar: calendar)

    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].date, calendar.startOfDay(for: morning))
    XCTAssertEqual(groups[0].items.map(\.title), ["morning", "evening"])
    XCTAssertEqual(groups[0].itemOffset, 0)
  }

  func testItemsAcrossMidnightProduceSeparateSections() {
    let beforeMidnight = date(2026, 9, 1, 23, 59)
    let afterMidnight = date(2026, 9, 2, 0, 1)
    let items = [
      decorator(title: "newer", lastCopiedAt: afterMidnight),
      decorator(title: "older", lastCopiedAt: beforeMidnight)
    ]

    let groups = DayGrouper.group(items, by: .lastCopiedAt, calendar: calendar)

    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].date, calendar.startOfDay(for: afterMidnight))
    XCTAssertEqual(groups[0].items.map(\.title), ["newer"])
    XCTAssertEqual(groups[0].itemOffset, 0)
    XCTAssertEqual(groups[1].date, calendar.startOfDay(for: beforeMidnight))
    XCTAssertEqual(groups[1].items.map(\.title), ["older"])
    XCTAssertEqual(groups[1].itemOffset, 1)
  }

  func testFirstCopiedAtUsesFirstCopiedDate() {
    let day1 = date(2026, 9, 1, 12, 0)
    let day2 = date(2026, 9, 2, 12, 0)
    let items = [
      decorator(title: "copied-again", firstCopiedAt: day1, lastCopiedAt: day2),
      decorator(title: "same-first-day", firstCopiedAt: day1, lastCopiedAt: day1)
    ]

    let lastCopiedGroups = DayGrouper.group(items, by: .lastCopiedAt, calendar: calendar)
    XCTAssertEqual(lastCopiedGroups.count, 2)
    XCTAssertEqual(lastCopiedGroups.map(\.date), [
      calendar.startOfDay(for: day2),
      calendar.startOfDay(for: day1)
    ])

    let firstCopiedGroups = DayGrouper.group(items, by: .firstCopiedAt, calendar: calendar)
    XCTAssertEqual(firstCopiedGroups.count, 1)
    XCTAssertEqual(firstCopiedGroups[0].date, calendar.startOfDay(for: day1))
    XCTAssertEqual(firstCopiedGroups[0].items.map(\.title), ["copied-again", "same-first-day"])
  }

  func testFilteredSubsetOmitsEmptyDays() {
    let day1 = date(2026, 9, 1, 12, 0)
    let day2 = date(2026, 9, 2, 12, 0)
    let day3 = date(2026, 9, 3, 12, 0)
    let allItems = [
      decorator(title: "day3", lastCopiedAt: day3),
      decorator(title: "day2", lastCopiedAt: day2),
      decorator(title: "day1", lastCopiedAt: day1)
    ]
    let hits = allItems.filter { $0.title != "day2" }

    let groups = DayGrouper.group(hits, by: .lastCopiedAt, calendar: calendar)

    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups.map(\.date), [
      calendar.startOfDay(for: day3),
      calendar.startOfDay(for: day1)
    ])
    XCTAssertEqual(groups.flatMap { $0.items.map(\.title) }, ["day3", "day1"])
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute
    ))!
  }

  private func decorator(
    title: String,
    firstCopiedAt: Date? = nil,
    lastCopiedAt: Date
  ) -> HistoryItemDecorator {
    let contents = [HistoryItemContent(type: "", value: title.data(using: .utf8)!)]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = title
    item.firstCopiedAt = firstCopiedAt ?? lastCopiedAt
    item.lastCopiedAt = lastCopiedAt
    return HistoryItemDecorator(item)
  }
}

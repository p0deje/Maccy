import XCTest
@testable import Maccy

@MainActor
final class TodoReminderPresetsTests: XCTestCase {
  func testIn1HourResolve() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let resolved = TodoReminderPreset.in1Hour.resolve(from: now)

    XCTAssertEqual(resolved.date.timeIntervalSince(now), 3_600, accuracy: 0.001)
    XCTAssertEqual(resolved.repeat, .once)
  }

  func testTomorrowMorningResolve() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 14, minute: 30))!
    let resolved = TodoReminderPreset.tomorrow9am.resolve(calendar: calendar, from: now)

    XCTAssertEqual(calendar.component(.year, from: resolved.date), 2026)
    XCTAssertEqual(calendar.component(.month, from: resolved.date), 7)
    XCTAssertEqual(calendar.component(.day, from: resolved.date), 20)
    XCTAssertEqual(calendar.component(.hour, from: resolved.date), 9)
    XCTAssertEqual(calendar.component(.minute, from: resolved.date), 0)
    XCTAssertEqual(resolved.repeat, .once)
  }

  func testRollToTomorrowIfPast() {
    // `date(..., rollToTomorrowIfPast:)` is private; exercise it via presets that opt in.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let pastAfternoon = calendar.date(
      from: DateComponents(year: 2020, month: 1, day: 1, hour: 15, minute: 0)
    )!
    let resolved = TodoReminderPreset.daily9am.resolve(calendar: calendar, from: pastAfternoon)

    XCTAssertEqual(calendar.component(.year, from: resolved.date), 2020)
    XCTAssertEqual(calendar.component(.month, from: resolved.date), 1)
    XCTAssertEqual(calendar.component(.day, from: resolved.date), 2)
    XCTAssertEqual(calendar.component(.hour, from: resolved.date), 9)
    XCTAssertEqual(resolved.repeat, .daily)
  }

  func testNextReminderDateDailyAndWeekdays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let friday = calendar.date(
      from: DateComponents(year: 2026, month: 7, day: 17, hour: 9, minute: 0)
    )!
    let nextDaily = nextReminderDate(from: friday, rule: .daily, calendar: calendar)
    let nextWeekday = nextReminderDate(from: friday, rule: .weekdays, calendar: calendar)

    XCTAssertEqual(calendar.component(.day, from: nextDaily!), 18)
    XCTAssertEqual(calendar.component(.weekday, from: nextWeekday!), 2) // Monday
    XCTAssertNil(nextReminderDate(from: friday, rule: .once, calendar: calendar))
  }
}

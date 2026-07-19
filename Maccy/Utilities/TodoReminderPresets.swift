import Foundation

enum TodoReminderPreset: String, CaseIterable, Identifiable {
  case in15Minutes
  case in30Minutes
  case in1Hour
  case in2Hours
  case in3Hours
  case tonight8pm
  case tomorrow9am
  case tomorrow6pm
  case nextWeek9am
  case daily9am
  case daily6pm
  case hourly
  case weekly
  case weekdays9am

  var id: String { rawValue }

  var title: String {
    NSLocalizedString("ReminderPreset.\(rawValue)", tableName: "Todos", comment: "")
  }

  var systemImage: String {
    switch self {
    case .in15Minutes, .in30Minutes:
      return "clock"
    case .in1Hour, .in2Hours, .in3Hours:
      return "clock.arrow.circlepath"
    case .tonight8pm, .tomorrow9am, .tomorrow6pm, .nextWeek9am:
      return "calendar"
    case .daily9am, .daily6pm:
      return "sun.max"
    case .hourly:
      return "repeat"
    case .weekly:
      return "calendar.badge.clock"
    case .weekdays9am:
      return "briefcase"
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func resolve(calendar: Calendar = .current, from now: Date = .now) -> (date: Date, repeat: TodoReminderRepeat) {
    switch self {
    case .in15Minutes:
      return (now.addingTimeInterval(15 * 60), .once)
    case .in30Minutes:
      return (now.addingTimeInterval(30 * 60), .once)
    case .in1Hour:
      return (now.addingTimeInterval(60 * 60), .once)
    case .in2Hours:
      return (now.addingTimeInterval(2 * 60 * 60), .once)
    case .in3Hours:
      return (now.addingTimeInterval(3 * 60 * 60), .once)
    case .tonight8pm:
      return (Self.date(on: now, hour: 20, minute: 0, calendar: calendar, rollToTomorrowIfPast: true), .once)
    case .tomorrow9am:
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
      return (Self.date(on: tomorrow, hour: 9, minute: 0, calendar: calendar), .once)
    case .tomorrow6pm:
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
      return (Self.date(on: tomorrow, hour: 18, minute: 0, calendar: calendar), .once)
    case .nextWeek9am:
      let nextWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now
      return (Self.date(on: nextWeek, hour: 9, minute: 0, calendar: calendar), .once)
    case .daily9am:
      return (Self.date(on: now, hour: 9, minute: 0, calendar: calendar, rollToTomorrowIfPast: true), .daily)
    case .daily6pm:
      return (Self.date(on: now, hour: 18, minute: 0, calendar: calendar, rollToTomorrowIfPast: true), .daily)
    case .hourly:
      return (now, .hourly)
    case .weekly:
      let nextWeekday = calendar.date(byAdding: .day, value: 7, to: now) ?? now
      return (Self.date(on: nextWeekday, hour: 9, minute: 0, calendar: calendar), .weekly)
    case .weekdays9am:
      return (Self.date(on: now, hour: 9, minute: 0, calendar: calendar, rollToTomorrowIfPast: true), .weekdays)
    }
  }

  private static func date(
    on day: Date,
    hour: Int,
    minute: Int,
    calendar: Calendar,
    rollToTomorrowIfPast: Bool = false
  ) -> Date {
    var components = calendar.dateComponents([.year, .month, .day], from: day)
    components.hour = hour
    components.minute = minute
    var date = calendar.date(from: components) ?? day
    if rollToTomorrowIfPast, date <= .now {
      date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }
    return date
  }
}

/// Returns the next occurrence for a repeating reminder rule, or `nil` for once/none.
func nextReminderDate(
  from date: Date,
  rule: TodoReminderRepeat,
  calendar: Calendar = .current
) -> Date? {
  switch rule {
  case .none, .once:
    return nil
  case .hourly:
    return calendar.date(byAdding: .hour, value: 1, to: date)
  case .daily:
    return calendar.date(byAdding: .day, value: 1, to: date)
  case .weekly:
    return calendar.date(byAdding: .day, value: 7, to: date)
  case .weekdays:
    var candidate = date
    // Match ReminderScheduler weekdays: Monday–Friday (Calendar weekday 2…6).
    for _ in 0..<8 {
      guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
        return nil
      }
      candidate = next
      let weekday = calendar.component(.weekday, from: candidate)
      if (2...6).contains(weekday) {
        return candidate
      }
    }
    return nil
  }
}

enum TodoReminderFormatting {
  static func summary(repeatRule: TodoReminderRepeat, date: Date?) -> String {
    guard let date else {
      return NSLocalizedString("ReminderNone", tableName: "Todos", comment: "")
    }

    switch repeatRule {
    case .none:
      return NSLocalizedString("ReminderNone", tableName: "Todos", comment: "")
    case .once:
      return String(
        format: NSLocalizedString("ReminderOnce", tableName: "Todos", comment: ""),
        formatted(date)
      )
    case .hourly:
      return NSLocalizedString("ReminderHourly", tableName: "Todos", comment: "")
    case .daily:
      return String(
        format: NSLocalizedString("ReminderDaily", tableName: "Todos", comment: ""),
        formattedTime(date)
      )
    case .weekly:
      return String(
        format: NSLocalizedString("ReminderWeekly", tableName: "Todos", comment: ""),
        formattedWeekday(date),
        formattedTime(date)
      )
    case .weekdays:
      return String(
        format: NSLocalizedString("ReminderWeekdays", tableName: "Todos", comment: ""),
        formattedTime(date)
      )
    }
  }

  static func notificationSubtitle(repeatRule: TodoReminderRepeat, date: Date) -> String? {
    switch repeatRule {
    case .none, .once:
      return String(
        format: NSLocalizedString("ReminderNotificationOnce", tableName: "TodoSettings", comment: ""),
        formatted(date)
      )
    case .hourly:
      return NSLocalizedString("ReminderNotificationHourly", tableName: "TodoSettings", comment: "")
    case .daily:
      return String(
        format: NSLocalizedString("ReminderNotificationDaily", tableName: "TodoSettings", comment: ""),
        formattedTime(date)
      )
    case .weekly:
      return String(
        format: NSLocalizedString("ReminderNotificationWeekly", tableName: "TodoSettings", comment: ""),
        formattedWeekday(date),
        formattedTime(date)
      )
    case .weekdays:
      return String(
        format: NSLocalizedString("ReminderNotificationWeekdays", tableName: "TodoSettings", comment: ""),
        formattedTime(date)
      )
    }
  }

  private static func formatted(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  private static func formattedTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private static func formattedWeekday(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.wide))
  }
}

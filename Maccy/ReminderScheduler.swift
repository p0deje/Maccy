import Defaults
import Foundation
import Logging
import SwiftData
import UserNotifications

@MainActor
final class ReminderScheduler {
  static let shared = ReminderScheduler()

  private let logger = Logger(label: "org.p0deje.Maccy.ReminderScheduler")
  private let center = UNUserNotificationCenter.current()

  private init() {}

  func register() {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
      if let error {
        self.logger.debug("Reminder authorization failed: \(error.localizedDescription)")
      }
    }

    let snoozeCategory = UNNotificationCategory(
      identifier: "TODO_REMINDER",
      actions: [
        UNNotificationAction(
          identifier: "SNOOZE_15",
          title: NSLocalizedString("Snooze15", tableName: "TodoSettings", comment: "")
        ),
        UNNotificationAction(
          identifier: "SNOOZE_60",
          title: NSLocalizedString("Snooze60", tableName: "TodoSettings", comment: "")
        ),
        UNNotificationAction(
          identifier: "SNOOZE_TOMORROW",
          title: NSLocalizedString("SnoozeTomorrow", tableName: "TodoSettings", comment: "")
        ),
        UNNotificationAction(
          identifier: "COMPLETE",
          title: NSLocalizedString("MarkDone", tableName: "TodoSettings", comment: "")
        )
      ],
      intentIdentifiers: []
    )
    center.setNotificationCategories([snoozeCategory])
  }

  func rescheduleAll() {
    guard Defaults[.enableTodoReminders] else { return }

    let descriptor = FetchDescriptor<TodoItem>(
      predicate: #Predicate { !$0.isCompleted && $0.reminderDate != nil }
    )
    guard let items = try? Storage.shared.context.fetch(descriptor) else { return }

    for item in items {
      schedule(item)
    }
  }

  func schedule(_ item: TodoItem) {
    guard Defaults[.enableTodoReminders] else { return }
    guard !item.isCompleted, let reminderDate = item.reminderDate else {
      cancel(item)
      return
    }

    let effectiveRule = TodoReminderRepeat(storedValue: item.reminderRepeatRule)
    let repeatRule: TodoReminderRepeat = effectiveRule == .none ? .once : effectiveRule
    if repeatRule == .once, reminderDate <= .now {
      cancel(item)
      return
    }

    cancel(item)

    switch repeatRule {
    case .none:
      cancel(item)
    case .once:
      addRequest(item, trigger: calendarTrigger(for: reminderDate, repeats: false), suffix: nil)
    case .hourly:
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: true)
      addRequest(item, trigger: trigger, suffix: "repeat")
    case .daily:
      let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
      let dailyTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
      addRequest(item, trigger: dailyTrigger, suffix: "repeat")
    case .weekly:
      let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: reminderDate)
      let weeklyTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
      addRequest(item, trigger: weeklyTrigger, suffix: "repeat")
    case .weekdays:
      scheduleWeekdays(item, anchor: reminderDate)
    }
  }

  func cancel(_ item: TodoItem) {
    let prefix = notificationPrefix(for: item)
    center.getPendingNotificationRequests { requests in
      let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
      self.center.removePendingNotificationRequests(withIdentifiers: ids)
    }
    center.getDeliveredNotifications { notifications in
      let ids = notifications.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
      self.center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    item.notificationId = nil
  }

  func snooze(_ item: TodoItem, by interval: TimeInterval) {
    item.reminderDate = .now.addingTimeInterval(interval)
    item.reminderRepeatRule = TodoReminderRepeat.once.rawValue
    item.updatedAt = .now
    schedule(item)
    try? Storage.shared.context.save()
  }

  func snoozeTomorrowMorning(_ item: TodoItem) {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
    components.day = (components.day ?? 0) + 1
    components.hour = 9
    components.minute = 0
    let date = Calendar.current.date(from: components) ?? .now.addingTimeInterval(86_400)
    item.reminderDate = date
    item.reminderRepeatRule = TodoReminderRepeat.once.rawValue
    item.updatedAt = .now
    schedule(item)
    try? Storage.shared.context.save()
  }

  @MainActor
  func handleNotificationResponse(_ response: UNNotificationResponse) {
    let identifier = response.notification.request.identifier
    guard identifier.hasPrefix("todo-reminder-") else { return }

    let uuidString = identifier
      .dropFirst("todo-reminder-".count)
      .split(separator: "-")
      .first
      .map(String.init) ?? ""
    guard let uuid = UUID(uuidString: uuidString) else { return }

    let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == uuid })
    guard let item = try? Storage.shared.context.fetch(descriptor).first else { return }

    switch response.actionIdentifier {
    case "COMPLETE":
      Todos.shared.toggleComplete(id: uuid, source: .notification)
    case "SNOOZE_15":
      snooze(item, by: 15 * 60)
    case "SNOOZE_60":
      snooze(item, by: 60 * 60)
    case "SNOOZE_TOMORROW":
      snoozeTomorrowMorning(item)
    default:
      AppState.shared.appDelegate?.openTodosWindow()
    }
  }

  private func scheduleWeekdays(_ item: TodoItem, anchor: Date) {
    let calendar = Calendar.current
    let time = calendar.dateComponents([.hour, .minute], from: anchor)
    // Calendar weekday: 1 = Sunday … 7 = Saturday. Schedule Monday–Friday (2–6).
    for weekday in 2...6 {
      var components = DateComponents()
      components.weekday = weekday
      components.hour = time.hour
      components.minute = time.minute
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
      addRequest(item, trigger: trigger, suffix: "wd-\(weekday)")
    }
    item.notificationId = notificationIdentifier(for: item, suffix: "wd-2")
    try? Storage.shared.context.save()
  }

  private func addRequest(_ item: TodoItem, trigger: UNNotificationTrigger, suffix: String?) {
    let content = notificationContent(for: item)
    let identifier = notificationIdentifier(for: item, suffix: suffix)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    center.add(request) { error in
      if let error {
        self.logger.debug("Failed to schedule reminder: \(error.localizedDescription)")
        return
      }

      Task { @MainActor in
        if suffix == nil || suffix == "repeat" {
          item.notificationId = identifier
          try? Storage.shared.context.save()
        }
      }
    }
  }

  private func notificationContent(for item: TodoItem) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = item.title.isEmpty
      ? NSLocalizedString("TodoReminderTitle", tableName: "TodoSettings", comment: "")
      : item.title

    var bodyParts: [String] = []
    if !item.notes.isEmpty {
      bodyParts.append(item.notes)
    }
    let repeatRule = TodoReminderRepeat(storedValue: item.reminderRepeatRule)
    if let reminderDate = item.reminderDate,
       let subtitle = TodoReminderFormatting.notificationSubtitle(repeatRule: repeatRule, date: reminderDate) {
      bodyParts.append(subtitle)
    }
    content.body = bodyParts.joined(separator: "\n")

    content.categoryIdentifier = "TODO_REMINDER"
    content.sound = .default
    return content
  }

  private func calendarTrigger(for date: Date, repeats: Bool) -> UNCalendarNotificationTrigger {
    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: date
    )
    return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
  }

  private func notificationPrefix(for item: TodoItem) -> String {
    "todo-reminder-\(item.id.uuidString)"
  }

  private func notificationIdentifier(for item: TodoItem, suffix: String?) -> String {
    if let suffix {
      return "\(notificationPrefix(for: item))-\(suffix)"
    }
    return notificationPrefix(for: item)
  }
}

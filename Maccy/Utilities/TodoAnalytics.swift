import Foundation

enum TodoAnalytics {
  static func activeDurationSeconds(for item: TodoItem, at date: Date = .now) -> Int {
    let start = item.completionHistory
      .sorted { $0.completedAt < $1.completedAt }
      .last(where: { $0.reopenedAt != nil })?
      .reopenedAt ?? item.createdAt
    return max(0, Int(date.timeIntervalSince(start)))
  }

  static func wasOverdue(_ item: TodoItem, at date: Date = .now) -> Bool {
    guard let dueDate = item.dueDate else { return false }
    return dueDate < date
  }

  static func completionSubtitle(for item: TodoItem) -> String? {
    guard item.isCompleted, let completedAt = item.completedAt else { return nil }

    var parts: [String] = [
      String(
        format: NSLocalizedString("DoneAt", tableName: "Todos", comment: ""),
        relativeDateTime(completedAt)
      )
    ]

    if let seconds = item.completionDurationSeconds {
      parts.append(
        String(
          format: NSLocalizedString("TookDuration", tableName: "Todos", comment: ""),
          formatDuration(seconds)
        )
      )
    }

    if item.wasOverdueWhenCompleted {
      parts.append(NSLocalizedString("Overdue", tableName: "Todos", comment: ""))
    }

    return parts.joined(separator: " · ")
  }

  static func formatDuration(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
    formatter.maximumUnitCount = 2
    return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
  }

  static func relativeDateTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: .now)
  }

  static func formattedDateTime(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}

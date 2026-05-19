import SwiftUI

struct TodoDetailView: View {
  @Bindable var item: TodoItemDecorator
  @Environment(AppState.self) private var appState

  private var sortedCompletionHistory: [TodoCompletionEvent] {
    item.item.completionHistory.sorted { $0.completedAt > $1.completedAt }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      TodoDetailSection(titleKey: "SectionReminder") {
        TodoReminderEditorView(item: item)
      }

      TodoDetailSection(titleKey: "SectionDetails") {
        VStack(alignment: .leading, spacing: 6) {
          detailRow(
            NSLocalizedString("Created", tableName: "Todos", comment: ""),
            TodoAnalytics.formattedDateTime(item.item.createdAt)
          )
          detailRow(
            NSLocalizedString("Updated", tableName: "Todos", comment: ""),
            TodoAnalytics.formattedDateTime(item.item.updatedAt)
          )

          if let completedAt = item.item.completedAt {
            detailRow(
              NSLocalizedString("Completed", tableName: "Todos", comment: ""),
              TodoAnalytics.formattedDateTime(completedAt)
            )
          }

          if let seconds = item.item.completionDurationSeconds {
            detailRow(
              NSLocalizedString("ActiveDuration", tableName: "Todos", comment: ""),
              TodoAnalytics.formatDuration(seconds)
            )
          }

          if item.item.timesCompleted > 1 {
            detailRow(
              NSLocalizedString("TimesCompleted", tableName: "Todos", comment: ""),
              "\(item.item.timesCompleted)"
            )
          }
        }
      }

      TodoDetailSection(titleKey: "Notes") {
        TextField(
          NSLocalizedString("NotesPlaceholder", tableName: "Todos", comment: ""),
          text: $item.notes,
          axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.callout)
        .lineLimit(4...12)
        .onSubmit {
          appState.todos.update(item)
        }
      }

      if !sortedCompletionHistory.isEmpty {
        TodoDetailSection(titleKey: "CompletionHistory") {
          completionHistory
        }
      }
    }
  }

  @ViewBuilder
  private var completionHistory: some View {
    ForEach(Array(sortedCompletionHistory.enumerated()), id: \.element.persistentModelID) { index, event in
      VStack(alignment: .leading, spacing: 2) {
        Text(TodoAnalytics.formattedDateTime(event.completedAt))
          .font(.caption)
          .fontWeight(.medium)

        Text(
          String(
            format: NSLocalizedString("HistoryEntry", tableName: "Todos", comment: ""),
            TodoAnalytics.formatDuration(event.durationSeconds),
            event.source
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)

        if let reopened = event.reopenedAt {
          Text(
            String(
              format: NSLocalizedString("ReopenedAt", tableName: "Todos", comment: ""),
              TodoAnalytics.formattedDateTime(reopened)
            )
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)

      if index < sortedCompletionHistory.count - 1 {
        Divider()
      }
    }
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 72, alignment: .leading)
      Text(value)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption)
  }
}

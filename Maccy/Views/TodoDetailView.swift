import SwiftUI

struct TodoDetailView: View {
  @Bindable var item: TodoItemDecorator

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      TodoReminderEditorView(item: item)

      Divider()

      VStack(alignment: .leading, spacing: 3) {
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

        notesEditor

        if !item.item.completionHistory.isEmpty {
          completionHistory
        }
      }
    }
  }

  @ViewBuilder
  private var notesEditor: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(NSLocalizedString("Notes", tableName: "Todos", comment: ""))
        .font(.caption2)
        .foregroundStyle(.secondary)
      TextField(
        NSLocalizedString("NotesPlaceholder", tableName: "Todos", comment: ""),
        text: $item.notes,
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .font(.caption2)
      .lineLimit(3...8)
      .onSubmit {
        AppState.shared.todos.update(item)
      }
    }
    .padding(.top, 4)
  }

  @ViewBuilder
  private var completionHistory: some View {
    Text(NSLocalizedString("CompletionHistory", tableName: "Todos", comment: ""))
      .font(.caption2)
      .foregroundStyle(.secondary)
      .padding(.top, 2)

    ForEach(item.item.completionHistory.sorted(by: { $0.completedAt > $1.completedAt }), id: \.completedAt) { event in
      VStack(alignment: .leading, spacing: 1) {
        Text(TodoAnalytics.formattedDateTime(event.completedAt))
          .font(.caption2)
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
    }
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 68, alignment: .leading)
      Text(value)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption2)
  }
}

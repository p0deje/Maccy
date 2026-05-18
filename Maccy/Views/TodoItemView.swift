import SwiftUI

struct TodoItemView: View {
  @Bindable var item: TodoItemDecorator
  @Environment(AppState.self) private var appState

  private var isSelected: Bool {
    appState.todos.selectedId == item.id
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 6) {
        Button {
          appState.todos.toggleComplete(item, source: .checkbox)
        } label: {
          Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.callout)
            .foregroundStyle(item.isCompleted ? .green : .secondary)
        }
        .buttonStyle(.plain)

        TextField(
          NSLocalizedString("TodoTitlePlaceholder", tableName: "Todos", comment: ""),
          text: $item.title
        )
        .textFieldStyle(.plain)
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
        .strikethrough(item.isCompleted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onSubmit { appState.todos.update(item) }

        if item.item.reminderDate != nil, !item.isCompleted {
          Image(systemName: "bell.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
            .help(
              TodoReminderFormatting.summary(
                repeatRule: TodoReminderRepeat(storedValue: item.item.reminderRepeatRule),
                date: item.item.reminderDate
              )
            )
        }

        if !item.isCompleted {
          Button {
            appState.todos.togglePin(item)
          } label: {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
              .font(.caption)
              .foregroundStyle(item.isPinned ? .orange : .secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .frame(minHeight: Popup.itemHeight)

      if item.isCompleted, let subtitle = TodoAnalytics.completionSubtitle(for: item.item) {
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .padding(.leading, 22)
          .padding(.top, 1)
      } else if let due = item.item.dueDate {
        Text(due, format: .dateTime.day().month().hour().minute())
          .font(.caption2)
          .foregroundStyle(TodoAnalytics.wasOverdue(item.item) ? .red : .secondary)
          .padding(.leading, 22)
          .padding(.top, 1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    .background(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.001))
    .clipShape(RoundedRectangle(cornerRadius: Popup.cornerRadius))
    .contentShape(Rectangle())
    .todoHoverSelectionId(item.id)
  }
}

import SwiftUI

struct TodoItemView: View {
  @Bindable var item: TodoItemDecorator
  @Environment(AppState.self) private var appState
  @State private var isHovered = false

  private var isSelected: Bool {
    appState.todos.selectedId == item.id
  }

  private var showsTrailingActions: Bool {
    isHovered || isSelected
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .center, spacing: 8) {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) {
            appState.todos.toggleComplete(item, source: .checkbox)
          }
        } label: {
          Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(item.isCompleted ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help(
          item.isCompleted
            ? NSLocalizedString("MarkActive", tableName: "Todos", comment: "")
            : NSLocalizedString("MarkDone", tableName: "Todos", comment: "")
        )

        if item.priority != .none {
          Image(systemName: item.priority.systemImage)
            .font(.caption)
            .foregroundStyle(priorityColor(item.priority))
            .help(item.priority.label)
        }

        TextField(
          NSLocalizedString("TodoTitlePlaceholder", tableName: "Todos", comment: ""),
          text: $item.title
        )
        .textFieldStyle(.plain)
        .font(.callout)
        .lineLimit(2)
        .truncationMode(.tail)
        .strikethrough(item.isCompleted, color: .secondary)
        .foregroundStyle(item.isCompleted ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onSubmit { appState.todos.update(item) }
        .onChange(of: item.title) {
          appState.todos.update(item)
        }

        trailingActions
      }
      .frame(minHeight: Popup.itemHeight)

      if item.isCompleted, let subtitle = TodoAnalytics.completionSubtitle(for: item.item) {
        metadataLine(subtitle, icon: "checkmark", color: .secondary)
      } else if let due = item.item.dueDate {
        metadataLine(
          due.formatted(.dateTime.day().month().hour().minute()),
          icon: TodoAnalytics.wasOverdue(item.item) ? "exclamationmark.circle.fill" : "calendar",
          color: TodoAnalytics.wasOverdue(item.item) ? .red : .secondary
        )
      }

      if appState.todos.selectedListFilter == .all,
         let listName = appState.todos.listName(for: item.item) {
        metadataLine(listName, icon: "folder", color: .secondary)
      }
    }
    .padding(TodoDesign.rowInset)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    .background(rowBackgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: Popup.cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: Popup.cornerRadius, style: .continuous))
    .opacity(item.isCompleted && !isSelected ? 0.72 : 1)
    .onHover { isHovered = $0 }
    .onTapGesture {
      appState.todos.select(id: item.id)
    }
    .todoHoverSelectionId(item.id)
  }

  @ViewBuilder
  private var trailingActions: some View {
    HStack(spacing: 4) {
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
          withAnimation(.easeInOut(duration: 0.18)) {
            appState.todos.togglePin(item)
          }
        } label: {
          Image(systemName: item.isPinned ? "pin.fill" : "pin")
            .font(.caption)
            .foregroundStyle(item.isPinned ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .opacity(item.isPinned || showsTrailingActions ? 1 : 0)
        .allowsHitTesting(item.isPinned || showsTrailingActions)
      }
    }
  }

  private var rowBackgroundColor: Color {
    if isSelected {
      return TodoDesign.selectedFill
    }
    if isHovered {
      return Color.primary.opacity(0.06)
    }
    return Color.white.opacity(0.001)
  }

  private func metadataLine(_ text: String, icon: String, color: Color) -> some View {
    Label(text, systemImage: icon)
      .font(.caption2)
      .foregroundStyle(color)
      .lineLimit(1)
      .padding(.leading, 26)
  }

  private func priorityColor(_ priority: TodoPriority) -> Color {
    switch priority {
    case .none:
      return .secondary
    case .low:
      return .blue
    case .medium:
      return .orange
    case .high:
      return .red
    }
  }
}

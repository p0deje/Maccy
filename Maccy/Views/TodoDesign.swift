import SwiftUI

enum TodoDesign {
  static let rowSpacing: CGFloat = 3
  static let rowInset = EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
  static let sectionHeaderTopPadding: CGFloat = 10
  static let chipCornerRadius: CGFloat = 6
  static let cardCornerRadius: CGFloat = 8

  static var subtleFill: Color { Color.primary.opacity(0.05) }
  static var chipFill: Color { Color.primary.opacity(0.07) }
  static var selectedFill: Color { Color.accentColor.opacity(0.85) }
}

struct TodoSectionHeaderView: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.tertiary)
      .textCase(.uppercase)
      .tracking(0.35)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, TodoDesign.sectionHeaderTopPadding)
      .padding(.bottom, 4)
      .padding(.horizontal, 4)
  }
}

struct TodoEmptyStateView: View {
  let systemImage: String
  let message: String

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 30, weight: .light))
        .foregroundStyle(.tertiary)
        .symbolRenderingMode(.hierarchical)

      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
    .padding(.horizontal, 20)
  }
}

struct TodoDetailSection<Content: View>: View {
  let titleKey: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString(titleKey, tableName: "Todos", comment: ""))
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)

      content()
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(TodoDesign.subtleFill)
    .clipShape(RoundedRectangle(cornerRadius: TodoDesign.cardCornerRadius, style: .continuous))
  }
}

struct TodoSlideoutHeaderView: View {
  @Environment(AppState.self) private var appState
  @Bindable var item: TodoItemDecorator

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField(
        NSLocalizedString("TodoTitlePlaceholder", tableName: "Todos", comment: ""),
        text: $item.title
      )
      .textFieldStyle(.plain)
      .font(.title3.weight(.semibold))
      .lineLimit(2)
      .onSubmit { appState.todos.update(item) }
      .onChange(of: item.title) { _, _ in
        appState.todos.scheduleUpdate(item)
      }

      HStack(spacing: 8) {
        if item.isCompleted {
          Label(
            NSLocalizedString("StatusCompleted", tableName: "Todos", comment: ""),
            systemImage: "checkmark.circle.fill"
          )
          .font(.caption)
          .foregroundStyle(.green)
        } else if item.isPinned {
          Label(
            NSLocalizedString("StatusPinned", tableName: "Todos", comment: ""),
            systemImage: "pin.fill"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }

        if let due = item.item.dueDate, !item.isCompleted {
          Label {
            Text(due, format: .dateTime.day().month().hour().minute())
          } icon: {
            Image(systemName: TodoAnalytics.wasOverdue(item.item) ? "exclamationmark.circle.fill" : "calendar")
          }
          .font(.caption)
          .foregroundStyle(TodoAnalytics.wasOverdue(item.item) ? .red : .secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct TodoSlideoutToolbarView: View {
  @Environment(AppState.self) private var appState
  let item: TodoItemDecorator

  var body: some View {
    HStack(spacing: 4) {
      Spacer()

      ToolbarButton {
        withAnimation(.easeInOut(duration: 0.18)) {
          appState.todos.toggleComplete(item, source: .menu)
        }
      } label: {
        Image(systemName: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
      }

      ToolbarButton {
        withAnimation(.easeInOut(duration: 0.18)) {
          appState.todos.togglePin(item)
        }
      } label: {
        Image(systemName: item.isPinned ? "pin.slash" : "pin")
      }
      .disabled(item.isCompleted)

      ToolbarButton {
        appState.todos.delete(item)
      } label: {
        Image(systemName: "trash")
      }
    }
    .padding(.bottom, 4)
  }
}

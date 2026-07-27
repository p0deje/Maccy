import Defaults
import SwiftUI

struct TodoReminderEditorView: View {
  @Environment(AppState.self) private var appState
  @Bindable var item: TodoItemDecorator
  @Default(.enableTodoReminders) private var remindersEnabled

  @State private var customDate = Date()
  @State private var customRepeat: TodoReminderRepeat = .once
  @State private var showCustomPicker = false

  private var repeatRule: TodoReminderRepeat {
    TodoReminderRepeat(storedValue: item.item.reminderRepeatRule)
  }

  private var hasReminder: Bool {
    item.item.reminderDate != nil
  }

  private let presetColumns = [
    GridItem(.adaptive(minimum: 100), spacing: 6)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !remindersEnabled {
        Label(
          NSLocalizedString("RemindersDisabled", tableName: "Todos", comment: ""),
          systemImage: "bell.slash"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        if hasReminder, let date = item.item.reminderDate {
          activeReminderBanner(date: date)
        }

        LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 6) {
          ForEach(TodoReminderPreset.allCases) { preset in
            presetButton(preset)
          }
        }

        Button {
          withAnimation(.easeInOut(duration: 0.18)) {
            showCustomPicker.toggle()
          }
          if showCustomPicker, item.item.reminderDate == nil {
            customDate = Date().addingTimeInterval(60 * 60)
          } else if let existing = item.item.reminderDate {
            customDate = existing
            customRepeat = repeatRule == .none ? .once : repeatRule
          }
        } label: {
          Label(
            NSLocalizedString("ReminderCustom", tableName: "Todos", comment: ""),
            systemImage: "slider.horizontal.3"
          )
          .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        if showCustomPicker {
          customPickerPanel
        }
      }
    }
  }

  @ViewBuilder
  private func activeReminderBanner(date: Date) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "bell.fill")
        .font(.caption)
        .foregroundStyle(.orange)

      Text(TodoReminderFormatting.summary(repeatRule: repeatRule, date: date))
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        appState.todos.clearReminder(item)
        showCustomPicker = false
      } label: {
        Text(NSLocalizedString("ReminderClear", tableName: "Todos", comment: ""))
      }
      .buttonStyle(.plain)
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(8)
    .background(Color.orange.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: TodoDesign.chipCornerRadius, style: .continuous))
  }

  private var customPickerPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      DatePicker(
        NSLocalizedString("ReminderDate", tableName: "Todos", comment: ""),
        selection: $customDate
      )
      .datePickerStyle(.compact)
      .labelsHidden()

      Picker(NSLocalizedString("ReminderRepeat", tableName: "Todos", comment: ""), selection: $customRepeat) {
        Text(NSLocalizedString("ReminderRepeatOnce", tableName: "Todos", comment: ""))
          .tag(TodoReminderRepeat.once)
        Text(NSLocalizedString("ReminderRepeatHourly", tableName: "Todos", comment: ""))
          .tag(TodoReminderRepeat.hourly)
        Text(NSLocalizedString("ReminderRepeatDaily", tableName: "Todos", comment: ""))
          .tag(TodoReminderRepeat.daily)
        Text(NSLocalizedString("ReminderRepeatWeekly", tableName: "Todos", comment: ""))
          .tag(TodoReminderRepeat.weekly)
        Text(NSLocalizedString("ReminderRepeatWeekdays", tableName: "Todos", comment: ""))
          .tag(TodoReminderRepeat.weekdays)
      }
      .pickerStyle(.menu)
      .font(.caption)

      Button {
        appState.todos.setReminder(item, date: customDate, repeatRule: customRepeat)
        showCustomPicker = false
      } label: {
        Text(NSLocalizedString("ReminderSaveCustom", tableName: "Todos", comment: ""))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .padding(10)
    .background(TodoDesign.chipFill)
    .clipShape(RoundedRectangle(cornerRadius: TodoDesign.cardCornerRadius, style: .continuous))
  }

  private func presetButton(_ preset: TodoReminderPreset) -> some View {
    Button {
      appState.todos.applyReminderPreset(item, preset: preset)
      showCustomPicker = false
    } label: {
      Label(preset.title, systemImage: preset.systemImage)
        .font(.caption2)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(TodoDesign.chipFill)
        .clipShape(RoundedRectangle(cornerRadius: TodoDesign.chipCornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

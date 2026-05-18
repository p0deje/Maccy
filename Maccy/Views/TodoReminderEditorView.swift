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
    GridItem(.adaptive(minimum: 108), spacing: 6)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(NSLocalizedString("Reminder", tableName: "Todos", comment: ""))
        .font(.caption)
        .foregroundStyle(.secondary)

      if !remindersEnabled {
        Text(NSLocalizedString("RemindersDisabled", tableName: "Todos", comment: ""))
          .font(.caption2)
          .foregroundStyle(.secondary)
      } else {
        LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 6) {
          ForEach(TodoReminderPreset.allCases) { preset in
            presetButton(preset)
          }
        }

        Button {
          showCustomPicker.toggle()
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
        }
        .buttonStyle(.plain)
        .font(.caption)

        if showCustomPicker {
          VStack(alignment: .leading, spacing: 6) {
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
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          }
          .padding(8)
          .background(Color.primary.opacity(0.05))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }

        if hasReminder, let date = item.item.reminderDate {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "bell.fill")
              .font(.caption2)
              .foregroundStyle(.orange)
            Text(TodoReminderFormatting.summary(repeatRule: repeatRule, date: date))
              .font(.caption2)
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
        }
      }
    }
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
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
  }
}

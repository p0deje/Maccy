import Defaults
import Settings
import SwiftUI

struct TodoSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(label: { Text("Display", tableName: "TodoSettings") }) {
        Defaults.Toggle(key: .showCompletedTodos) {
          Text("ShowCompleted", tableName: "TodoSettings")
        }
        Defaults.Toggle(key: .openTodosWindowAtLaunch) {
          Text("OpenAtLaunch", tableName: "TodoSettings")
        }
      }

      Settings.Section(label: { Text("Reminders", tableName: "TodoSettings") }) {
        Defaults.Toggle(key: .enableTodoReminders) {
          Text("EnableReminders", tableName: "TodoSettings")
        }

        if let notificationsURL {
          Link(destination: notificationsURL) {
            Text("NotificationSettings", tableName: "TodoSettings")
          }
        }
      }

      Settings.Section(title: "") {
        Text("RemindersHelp", tableName: "TodoSettings")
          .foregroundStyle(.secondary)
          .controlSize(.small)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

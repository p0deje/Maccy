import SwiftUI
import Defaults
import Settings

struct NotificationsSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Notify", tableName: "NotificationsSettings") }
      ) {
        Defaults.Toggle(key: .notifyOnCopy) {
          Text("NotifyOnCopy", tableName: "NotificationsSettings")
        }

        Defaults.Toggle(key: .notifyOnSelection) {
          Text("NotifyOnSelection", tableName: "NotificationsSettings")
        }
      }

      Settings.Section(title: "") {
        if let notificationsURL = notificationsURL {
          Link(destination: notificationsURL, label: {
            Text("NotificationsAndSounds", tableName: "NotificationsSettings")
          })
        }
      }
    }
  }
}

#Preview {
  NotificationsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}

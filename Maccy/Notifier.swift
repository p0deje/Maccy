import AppKit
import UserNotifications

class Notifier {
  private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
  private static var hasRequestedAuthorization = false

  private static var isTesting: Bool {
    #if DEBUG
    return CommandLine.arguments.contains("enable-testing")
    #else
    return false
    #endif
  }

  static func authorize() {
    guard !isTesting else {
      return
    }

    guard !hasRequestedAuthorization else {
      return
    }
    hasRequestedAuthorization = true

    center.requestAuthorization(options: [.alert, .sound]) { _, error in
      if error != nil {
        NSLog("Failed to authorize notifications: \(String(describing: error))")
      }
    }
  }

  static func notify(body: String?, sound: NSSound?) {
    guard !isTesting else {
      return
    }

    guard let body else { return }

    authorize()

    center.getNotificationSettings { settings in
      guard (settings.authorizationStatus == .authorized) ||
            (settings.authorizationStatus == .provisional) else { return }

      let content = UNMutableNotificationContent()
      if settings.alertSetting == .enabled {
        content.body = body
      }

      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      center.add(request) { error in
        if error != nil {
          NSLog("Failed to deliver notification: \(String(describing: error))")
        } else {
          if settings.soundSetting == .enabled {
            sound?.play()
          }
        }
      }
    }
  }
}

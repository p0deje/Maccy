import AppKit
import Logging
import UserNotifications

final class Notifier {
  private static let center = UNUserNotificationCenter.current()
  private static let logger = Logger(label: "org.p0deje.Maccy.Notifier")
  private static var didRequestAuthorization = false

  static func register() {
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      requestAuthorization()
    }
  }

  static func notify(body: String?, sound: NSSound?) {
    guard let body else { return }

    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional else {
        return
      }

      let content = UNMutableNotificationContent()
      if settings.alertSetting == .enabled {
        content.body = body
      }

      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      center.add(request) { error in
        if let error {
          logger.debug("Failed to deliver notification: \(error.localizedDescription)")
        } else if settings.soundSetting == .enabled {
          sound?.play()
        }
      }
    }
  }

  private static func requestAuthorization() {
    guard !didRequestAuthorization else { return }
    didRequestAuthorization = true

    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error {
        logger.debug("Notification authorization failed: \(error.localizedDescription)")
      } else if !granted {
        logger.debug("Notification authorization denied")
      }
    }
  }
}

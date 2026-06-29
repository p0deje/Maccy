import AppKit
@preconcurrency import UserNotifications
import os

/// Posts local user notifications for clipboard events.
class Notifier {
  private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
  // A runtime-mutated `static var` Bool is nonisolated global shared mutable
  // state. A Sendable `OSAllocatedUnfairLock<Bool>` held in a `static let` is a
  // Sendable global (allowed), and the read-modify-write under the lock also
  // closes a latent TOCTOU where concurrent notify() calls could double-request
  // authorization.
  private static let hasRequestedAuthorization = OSAllocatedUnfairLock(initialState: false)

  /// True under DEBUG when launched with `enable-testing`.
  private static var isTesting: Bool {
    #if DEBUG
    return CommandLine.arguments.contains("enable-testing")
    #else
    return false
    #endif
  }

  /// Requests notification authorization once (subsequent calls are no-ops).
  static func authorize() {
    guard !isTesting else {
      return
    }

    let shouldRequest = hasRequestedAuthorization.withLock { flag -> Bool in
      guard !flag else { return false }
      flag = true
      return true
    }
    guard shouldRequest else {
      return
    }

    center.requestAuthorization(options: [.alert, .sound]) { _, error in
      if error != nil {
        NSLog("Failed to authorize notifications: \(String(describing: error))")
      }
    }
  }

  /// Posts a notification with the given body text and optional sound.
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
      // Extract the Sendable Bool before the @Sendable `add` completion closure
      // so the non-Sendable `settings` (`UNNotificationSettings`) is not captured.
      let soundEnabled = settings.soundSetting == .enabled
      center.add(request) { error in
        if error != nil {
          NSLog("Failed to deliver notification: \(String(describing: error))")
        } else {
          if soundEnabled {
            sound?.play()
          }
        }
      }
    }
  }
}

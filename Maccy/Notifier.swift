import AppKit
@preconcurrency import UserNotifications
import os

class Notifier {
  private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
  // Swift 6 (SE-0412): a runtime-mutated `static var` Bool is nonisolated global
  // shared mutable state. A Sendable `OSAllocatedUnfairLock<Bool>` held in a
  // `static let` is a Sendable global (allowed), and the read-modify-write under
  // the lock also closes a latent TOCTOU (concurrent notify() could double-request).
  private static let hasRequestedAuthorization = OSAllocatedUnfairLock(initialState: false)

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
      // so the non-Sendable `settings` (UNNotificationSettings) isn't captured.
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

import AppKit

/// Posts an announcement when VoiceOver is enabled.
///
/// Medium priority avoids interrupting rapid selection updates. Use high priority only
/// for announcements that should interrupt current speech.
func announceForAccessibility(_ announcement: () -> String, priority: NSAccessibilityPriorityLevel = .medium) {
  guard NSWorkspace.shared.isVoiceOverEnabled else { return }
  NSAccessibility.post(
    element: NSApp as Any,
    notification: .announcementRequested,
    userInfo: [
      .announcement: announcement(),
      .priority: priority.rawValue
    ]
  )
}

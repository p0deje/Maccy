import AppKit

/// Maccy communicates most state visually (selection highlight, popup position). These are the
/// non-visual equivalents for VoiceOver users. No-op when VoiceOver is off.
///
/// Defaults to `.medium`: the selection announcement in NavigationManager fires on every
/// arrow keypress while browsing history, so `.high` (which interrupts whatever VoiceOver
/// is currently saying) would make fast navigation feel like it's constantly cutting itself
/// off. Pass `.high` explicitly only for something the user needs to hear immediately even
/// mid-sentence.
func announceForAccessibility(_ announcement: String, priority: NSAccessibilityPriorityLevel = .medium) {
  guard NSWorkspace.shared.isVoiceOverEnabled else { return }
  NSAccessibility.post(
    element: NSApp as Any,
    notification: .announcementRequested,
    userInfo: [
      .announcement: announcement,
      .priority: priority.rawValue
    ]
  )
}

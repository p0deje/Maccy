import AppKit

/// Maccy communicates most state visually (selection highlight, popup position). These are the
/// non-visual equivalents for VoiceOver users. No-op when VoiceOver is off.
///
/// Takes the announcement as an autoclosure so callers that build a non-trivial string (e.g.
/// joining several parts) don't pay for that work when VoiceOver isn't running.
///
/// Defaults to `.medium`: the selection announcement in NavigationManager fires on every
/// arrow keypress while browsing history, so `.high` (which interrupts whatever VoiceOver
/// is currently saying) would make fast navigation feel like it's constantly cutting itself
/// off. Pass `.high` explicitly only for something the user needs to hear immediately even
/// mid-sentence.
func announceForAccessibility(_ announcement: @autoclosure () -> String, priority: NSAccessibilityPriorityLevel = .medium) {
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

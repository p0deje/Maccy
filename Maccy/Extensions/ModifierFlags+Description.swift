import AppKit.NSEvent
import Carbon.HIToolbox

extension NSEvent.ModifierFlags {
  /// Renders the active modifier flags as their glyph sequence (e.g. `"⌃⌥⇧⌘"`).
  ///
  /// Order is fixed as control, option, shift, command, function, matching the
  /// convention used by KeyboardShortcuts.
  var description: String {
    var description = ""

    if contains(.control) {
      description += "⌃"
    }

    if contains(.option) {
      description += "⌥"
    }

    if contains(.shift) {
      description += "⇧"
    }

    if contains(.command) {
      description += "⌘"
    }

    if contains(.function) {
      description += "🌐\u{FE0E}"
    }

    return description
  }
}

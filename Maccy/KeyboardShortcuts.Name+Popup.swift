import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Name("popup", default: Shortcut(.c, modifiers: [.command, .shift]))
  static let privateMode = Name("privateMode", default: Shortcut(.x, modifiers: [.command, .shift]))
}

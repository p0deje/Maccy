import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Name("popup", default: Shortcut(.c, modifiers: [.command, .shift]))
  static let pin = Name("pin", default: Shortcut(.p, modifiers: [.option]))
  static let delete = Name("delete", default: Shortcut(.delete, modifiers: [.option]))
}

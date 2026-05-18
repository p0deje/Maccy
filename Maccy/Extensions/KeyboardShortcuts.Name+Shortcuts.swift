import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", default: Shortcut(.c, modifiers: [.command, .shift]))
  static let pin = Self("pin", default: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", default: Shortcut(.delete, modifiers: [.option]))
  static let togglePreview = Self("togglePreview", default: Shortcut(.space, modifiers: [.control]))

  static let quickPasteBase = Self("quickPasteBase", default: Shortcut(.one, modifiers: [.command, .shift]))
  static let quickPaste1 = Self("quickPaste1", default: Shortcut(.one, modifiers: [.command, .shift]))
  static let quickPaste2 = Self("quickPaste2", default: Shortcut(.two, modifiers: [.command, .shift]))
  static let quickPaste3 = Self("quickPaste3", default: Shortcut(.three, modifiers: [.command, .shift]))
  static let quickPaste4 = Self("quickPaste4", default: Shortcut(.four, modifiers: [.command, .shift]))
  static let quickPaste5 = Self("quickPaste5", default: Shortcut(.five, modifiers: [.command, .shift]))

  static let quickPastes: [KeyboardShortcuts.Name] = [
    .quickPaste1, .quickPaste2, .quickPaste3, .quickPaste4, .quickPaste5
  ]
}

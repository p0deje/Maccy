import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  /// Toggle the Maccy popup menu.
  static let popup = Self("popup", default: Shortcut(.c, modifiers: [.command, .shift]))
  /// Pin or unpin the selected history item.
  static let pin = Self("pin", default: Shortcut(.p, modifiers: [.option]))
  /// Delete the selected history item.
  static let delete = Self("delete", default: Shortcut(.delete, modifiers: [.option]))
  /// Toggle the preview pane for the selected item.
  static let togglePreview = Self("togglePreview", default: Shortcut(.space, modifiers: [.control]))
}

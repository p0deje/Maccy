import Cocoa

extension NSImage {
  /// SF Symbol: settings gear.
  static let gearshape = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "gearshape")
  /// SF Symbol: external drive (storage settings).
  static let externaldrive = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "externaldrive")
  /// SF Symbol: paint palette (appearance settings).
  static let paintpalette = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "paintpalette")
  /// SF Symbol: pin in a circle (the pin action).
  static let pincircle = NSImage(systemSymbolName: "pin.circle", accessibilityDescription: "pin.circle")
  /// SF Symbol: no-entry sign (clear/delete).
  static let nosign = NSImage(systemSymbolName: "nosign", accessibilityDescription: "nosign")
  /// SF Symbol: pair of gears (advanced settings).
  static let gearshape2 = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "gearshape2")
}

extension NSImage.Name {
  /// Asset name for the clipboard-fill glyph.
  static let clipboard = NSImage.Name("clipboard.fill")
  /// Asset name for the status-bar menu image.
  static let maccyStatusBar = NSImage.Name("StatusBarMenuImage")
  /// Asset name for the scissors glyph.
  static let scissors = NSImage.Name("scissors")
  /// Asset name for the paperclip glyph.
  static let paperclip = NSImage.Name("paperclip")
}

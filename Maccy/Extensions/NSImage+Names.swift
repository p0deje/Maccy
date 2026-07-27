import Cocoa

extension NSImage {
  static let gearshape = symbol("gearshape")
  static let externaldrive = symbol("externaldrive")
  static let paintpalette = symbol("paintpalette")
  static let pincircle = symbol("pin.circle")
  static let nosign = symbol("nosign")
  static let gearshape2 = symbol("gearshape.2")
  static let quickPaste = symbol("123.rectangle", fallback: "command")
  static let checklist = symbol("checklist", fallback: "checkmark.circle")

  static func symbol(_ name: String, fallback: String = "gearshape") -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: name)
      ?? NSImage(systemSymbolName: fallback, accessibilityDescription: fallback)
      ?? NSImage()
  }
}

extension NSImage.Name {
  static let clipboard = NSImage.Name("clipboard.fill")
  static let maccyStatusBar = NSImage.Name("StatusBarMenuImage")
  static let scissors = NSImage.Name("scissors")
  static let paperclip = NSImage.Name("paperclip")
}

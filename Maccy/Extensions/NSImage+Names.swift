import Cocoa

extension NSImage {
  static let gearshape = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "gearshape")
  static let externaldrive = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "externaldrive")
  static let paintpalette = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "paintpalette")
  static let nosign = NSImage(systemSymbolName: "nosign", accessibilityDescription: "nosign")
  static let gearshape2 = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "gearshape2")
}

extension NSImage.Name {
  static let clipboard = NSImage.Name("clipboard.fill")
  static let maccyStatusBar = NSImage.Name("StatusBarMenuImage")
  static let pincircle = loadName("pin.circle")
  static let scissors = NSImage.Name("scissors")
  static let paperclip = NSImage.Name("paperclip")

  private static func loadName(_ name: String) -> NSImage.Name {
    if #available(macOS 11, *) {
      return NSImage.Name("\(name).svg")
    } else {
      return NSImage.Name("\(name).png")
    }
  }
}

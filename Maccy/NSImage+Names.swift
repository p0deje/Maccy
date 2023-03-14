import Cocoa

extension NSImage.Name {
  static let clipboard = NSImage.Name("clipboard.fill")
  static let externaldrive = loadName("externaldrive")
  static let gearshape = loadName("gearshape")
  static let gearshape2 = loadName("gearshape.2")
  static let maccyStatusBar = NSImage.Name("StatusBarMenuImage")
  static let nosign = loadName("nosign")
  static let paintpalette = loadName("paintpalette")
  static let pincircle = loadName("pin.circle")
  static let scissors = NSImage.Name("scissors")

  private static func loadName(_ name: String) -> NSImage.Name {
    if #available(macOS 11, *) {
      return NSImage.Name("\(name).svg")
    } else {
      return NSImage.Name("\(name).png")
    }
  }
}

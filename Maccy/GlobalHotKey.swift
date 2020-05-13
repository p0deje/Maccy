import Magnet
import Sauce

class GlobalHotKey {
  typealias Handler = () -> Void

  static public var key: Key?
  static public var modifierFlags: NSEvent.ModifierFlags?

  private var hotKey: HotKey!
  private var handler: Handler
  private var hotKeyPrefObserver: NSKeyValueObservation?

  init(_ handler: @escaping Handler) {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.hotKey: UserDefaults.Values.hotKey])

    self.handler = handler
    hotKeyPrefObserver = UserDefaults.standard.observe(\.hotKey, options: [.initial, .new], changeHandler: { _, _ in
      if let (key, modifiers) = self.parseHotKey() {
        if let keyCombo = KeyCombo(key: key, cocoaModifiers: modifiers) {
          self.hotKey = HotKey(identifier: UserDefaults.standard.hotKey, keyCombo: keyCombo) { hotKey in
            hotKey.unregister()
            self.handler()
            hotKey.register()
          }
          self.hotKey.register()
        }
      }
    })
  }

  deinit {
    hotKeyPrefObserver?.invalidate()
  }

  private func parseHotKey() -> (Key, NSEvent.ModifierFlags)? {
    var keysList = UserDefaults.standard.hotKey.split(separator: "+")

    guard let keyString = keysList.popLast() else {
      return nil
    }
    guard let key = Key(character: String(keyString)) else {
      return nil
    }

    var modifiers: NSEvent.ModifierFlags = []
    for keyString in keysList {
      switch keyString {
      case "command":
        modifiers.insert(.command)
      case "control":
        modifiers.insert(.control)
      case "option":
        modifiers.insert(.option)
      case "shift":
        modifiers.insert(.shift)
      default: ()
      }
    }

    GlobalHotKey.key = key
    GlobalHotKey.modifierFlags = modifiers

    return (key, modifiers)
  }
}

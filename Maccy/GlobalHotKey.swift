import HotKey

class GlobalHotKey {
  static public var key: Key?
  static public var modifierFlags: NSEvent.ModifierFlags?

  private var hotKey: HotKey!
  private var handler: HotKey.Handler
  private var hotKeyPrefObserver: NSKeyValueObservation?

  init(_ handler: @escaping HotKey.Handler) {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.hotKey: UserDefaults.Values.hotKey])

    self.handler = handler
    hotKeyPrefObserver = UserDefaults.standard.observe(\.hotKey, options: [.initial, .new], changeHandler: { _, _ in
      if let (key, modifiers) = self.parseHotKey() {
        self.hotKey = HotKey(key: key, modifiers: modifiers)
        self.hotKey.keyDownHandler = {
          self.hotKey.isPaused = true
          self.handler()
          self.hotKey.isPaused = false
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
    guard let key = Key(string: String(keyString)) else {
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

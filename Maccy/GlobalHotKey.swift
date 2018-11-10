import HotKey

class GlobalHotKey {
  var handler: HotKey.Handler? {
    get { return hotKey?.keyDownHandler }
    set(newHandler) { hotKey?.keyDownHandler = newHandler }
  }

  private let hotKeyStore = "hotKey"
  private let defaultKeyBinding = "command+shift+c"
  private var hotKey: HotKey?

  init() {
    UserDefaults.standard.register(defaults: [hotKeyStore: defaultKeyBinding])
    registerHotKey()
  }

  private func registerHotKey() {
    guard let keybindingString = UserDefaults.standard.string(forKey: hotKeyStore) else {
      return
    }
    var keysList = keybindingString.split(separator: "+")

    guard let keyString = keysList.popLast() else {
      return
    }
    guard let key = Key(string: String(keyString)) else {
      return
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

    hotKey = HotKey(key: key, modifiers: modifiers)
  }
}

import Carbon
import Sauce

class KeyboardLayout {
  static var current: KeyboardLayout { KeyboardLayout() }

  var commandSwitchesToQWERTY: Bool { localizedName.contains("QWERTY ⌘") }
  var localizedName: String {
    if let value = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
       return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    } else {
      return ""
    }
  }

  private var inputSource: TISInputSource!

  init() {
    inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue()
  }
}

import Carbon

class KeyboardLayout {
  static var current: KeyboardLayout { KeyboardLayout() }

  // Dvorak - QWERTY ⌘ (https://github.com/p0deje/Maccy/issues/482)
  // bépo 1.1 - Azerty ⌘ (https://github.com/p0deje/Maccy/issues/520)
  var commandSwitchesToQWERTY: Bool { localizedName.hasSuffix("⌘") }

  var localizedName: String {
    guard let inputSource else {
      return ""
    }

    if let value = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
      return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    } else {
      return ""
    }
  }

  private var inputSource: TISInputSource?

  init() {
    // M2 (2026-06-25 master plan): TISCopyCurrentKeyboardLayoutInputSource()
    // follows the Core Foundation Copy rule (+1 retain). Bridging with
    // takeUnretainedValue() leaked one TISInputSource (== TSMInputSource) per
    // call — the exclusive source of the 18,417 ROOT LEAKs in the 2026-06-24
    // leaks dump (72% of leaked bytes, 93% of leaked instances). takeRetainedValue
    // consumes the +1 so ARC releases it when this transient instance deallocs.
    // NOTE: the localizedName getter below uses TISGetInputSourceProperty
    // (Get rule, +0) and must stay takeUnretainedValue() — changing it would
    // over-release and crash. Only this Copy-rule site is wrong.
    inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
  }
}

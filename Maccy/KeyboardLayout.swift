import Carbon

/// Inspects the active keyboard input source.
class KeyboardLayout {
  /// A fresh snapshot of the current keyboard layout.
  static var current: KeyboardLayout { KeyboardLayout() }

  /// True when the active layout switches to QWERTY while the command key is
  /// held (e.g. "Dvorak - QWERTY ⌘", "bépo 1.1 - Azerty ⌘").
  ///
  /// - SeeAlso: https://github.com/p0deje/Maccy/issues/482,
  ///   https://github.com/p0deje/Maccy/issues/520
  var commandSwitchesToQWERTY: Bool { localizedName.hasSuffix("⌘") }

  /// Localized name of the active input source, or empty when unavailable.
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
    // TISCopyCurrentKeyboardLayoutInputSource() follows the Core Foundation
    // Copy rule (+1 retain). takeRetainedValue() consumes that +1 so ARC
    // releases it when this transient instance deallocs; bridging with
    // takeUnretainedValue() here would leak one input source per call. Note
    // that `localizedName` uses TISGetInputSourceProperty (Get rule, +0) and
    // must stay takeUnretainedValue() — using takeRetainedValue() there would
    // over-release and crash.
    inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
  }
}

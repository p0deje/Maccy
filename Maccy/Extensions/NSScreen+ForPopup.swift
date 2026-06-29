import AppKit.NSScreen
import Defaults

extension NSScreen {
  /// The screen on which the popup should appear.
  ///
  /// Honors the user's `popupScreen` preference (1-based index); falls back to the
  /// main screen when unset (`<= 0`) or out of range.
  static var forPopup: NSScreen? {
    let desiredScreen = Defaults[.popupScreen]
    if desiredScreen <= 0 || desiredScreen > NSScreen.screens.count {
      return NSScreen.main
    } else {
      return NSScreen.screens[desiredScreen - 1]
    }
  }
}

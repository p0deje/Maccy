import AppKit.NSScreen
import Defaults

extension NSScreen {
  static var forPopup: NSScreen? {
    let desiredScreen = Defaults[.popupScreen]
    if desiredScreen == 0 || desiredScreen > NSScreen.screens.count {
      return NSScreen.main
    } else {
      return NSScreen.screens[desiredScreen - 1]
    }
  }
}

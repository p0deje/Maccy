import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
    let verticalPadding: CGFloat = 5

    var needsResize = false
    var height: CGFloat = 0
    var headerHeight: CGFloat = 0
    var pinnedItemsHeight: CGFloat = 0
    var footerHeight: CGFloat = 0

    init() {
        KeyboardShortcuts.onKeyUp(for: .popup) {
            Task { @MainActor in
                self.toggle()
            }
        }
    }

    @MainActor
    func toggle(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
        AppState.shared.appDelegate?.panel.toggle(height: height, at: popupPosition)
    }

    @MainActor
    func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
        AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
    }

    @MainActor
    func close() {
        AppState.shared.appDelegate?.panel.close()
    }

    @MainActor
    func resize(height: CGFloat) {
        self.height = height + headerHeight + pinnedItemsHeight + footerHeight + (verticalPadding * 2)
        AppState.shared.appDelegate?.panel.verticallyResize(to: self.height)
        needsResize = false
    }
}

import Foundation
import AppKit

class PasteStack: Identifiable {
  private static var listener: Any?

  static func initializeIfNeeded() {
    guard listener == nil else { return }
    Accessibility.check()

    var pasteDown: Bool = false
    listener = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .keyDown]) { event in
      switch event.type {
      case .keyDown:
        if event.keyCode == KeyChord.pasteKey.QWERTYKeyCode
           && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] {
          pasteDown = true
        }
      case .keyUp:
        if pasteDown && event.keyCode == KeyChord.pasteKey.QWERTYKeyCode {
          pasteDown = false
          AppState.shared.history.handlePasteStack()
        }
      default:
        break
      }
    }
  }

  var id: UUID = UUID()
  var items: [HistoryItemDecorator] = []
  var modifierFlags: NSEvent.ModifierFlags

  init(items: [HistoryItemDecorator], modifierFlags: NSEvent.ModifierFlags) {
    self.items = items
    self.modifierFlags = modifierFlags
  }
}

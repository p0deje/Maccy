import Foundation
import AppKit

/// Paste stack UX:
/// 1. Multi-select items and confirm → first item is copied (and pasted when the
///    action is paste / paste-without-formatting / paste-by-default).
/// 2. Each subsequent global ⌘V pastes the current clipboard item; on key-up we
///    advance by copying the next stack item onto the clipboard.
/// 3. An external copy interrupts the stack unless `pasteStackQueueExternalCopies`.
@Observable
class PasteStack: Identifiable, Hashable {
  private static var listener: Any?
  private static var didInitialize = false

  private static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  static func initializeIfNeeded() {
    guard !didInitialize else { return }
    didInitialize = true

    // Unit tests exercise stack state without a global monitor or Accessibility prompt.
    guard !isRunningTests else { return }

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
          Task { @MainActor in
            AppState.shared.history.handlePasteStack()
          }
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

  static func == (lhs: PasteStack, rhs: PasteStack) -> Bool {
    return lhs.id == rhs.id
      && lhs.items == rhs.items
      && lhs.modifierFlags.rawValue == rhs.modifierFlags.rawValue
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(items)
    hasher.combine(modifierFlags.rawValue)
  }

}

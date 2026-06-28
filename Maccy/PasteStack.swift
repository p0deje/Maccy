import Foundation
import AppKit

@Observable
class PasteStack: Identifiable, Hashable {
  // Swift 6 (SE-0412): isolate the mutable static + its accessor to @MainActor
  // (initializeIfNeeded runs once at launch on main; the global monitor handler
  // hops to main via Task { @MainActor }). An actor-isolated static is not
  // nonisolated global shared mutable state.
  @MainActor private static var listener: Any?

  @MainActor
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

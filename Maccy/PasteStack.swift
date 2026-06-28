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

    // Read the paste key code once on main (initializeIfNeeded is @MainActor)
    // and capture the Sendable Int into the @Sendable global-monitor closure,
    // so it doesn't reference the @MainActor KeyChord.pasteKey from nonisolated.
    let pasteKeyCode = KeyChord.pasteKey.QWERTYKeyCode

    var pasteDown: Bool = false
    listener = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .keyDown]) { event in
      switch event.type {
      case .keyDown:
        if event.keyCode == pasteKeyCode
           && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] {
          pasteDown = true
        }
      case .keyUp:
        if pasteDown && event.keyCode == pasteKeyCode {
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

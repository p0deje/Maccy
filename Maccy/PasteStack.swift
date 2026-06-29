import Foundation
import AppKit

/// A user-assembled sequence of items replayed in order by repeated paste
/// keystrokes.
@Observable
class PasteStack: Identifiable, Hashable {
  // The mutable static and its accessor are isolated to `@MainActor`
  // (`initializeIfNeeded` runs once at launch on main; the global-monitor
  // handler hops back to main via `Task { @MainActor }`). An actor-isolated
  // static is not nonisolated global shared mutable state.
  @MainActor private static var listener: Any?

  /// Installs the global key monitor that detects the paste chord, once.
  @MainActor
  static func initializeIfNeeded() {
    guard listener == nil else { return }
    Accessibility.check()

    // Read the paste key code once on main (`initializeIfNeeded` is
    // `@MainActor`) and capture the Sendable `Int` into the `@Sendable`
    // global-monitor closure, so it does not reference the `@MainActor`
    // `KeyChord.pasteKey` from a nonisolated context.
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
  /// Items queued for sequential paste, in paste order.
  var items: [HistoryItemDecorator] = []
  /// Modifier flags that activate this stack.
  var modifierFlags: NSEvent.ModifierFlags

  init(items: [HistoryItemDecorator], modifierFlags: NSEvent.ModifierFlags) {
    self.items = items
    self.modifierFlags = modifierFlags
  }

  /// Value equality over id, items, and modifier raw value.
  static func == (lhs: PasteStack, rhs: PasteStack) -> Bool {
    return lhs.id == rhs.id
      && lhs.items == rhs.items
      && lhs.modifierFlags.rawValue == rhs.modifierFlags.rawValue
  }

  /// Hashes id, items, and modifier raw value.
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(items)
    hasher.combine(modifierFlags.rawValue)
  }

}

import AppKit
import KeyboardShortcuts
import Testing
@testable import Maccy

@Suite(.serialized)
enum SharedStateTests {
  @Test("HTML source shortcut can be changed and disabled without changing Enter")
  @MainActor
  static func htmlSourceShortcut() {
    let savedShortcut = KeyboardShortcuts.getShortcut(for: .pasteHTMLSource)
    defer { KeyboardShortcuts.setShortcut(savedShortcut, for: .pasteHTMLSource) }

    KeyboardShortcuts.reset(.pasteHTMLSource)
    #expect(KeyChord(.return, [.control]) == .pasteHTMLSource)
    #expect(KeyChord(.return, [.option]) == .selectCurrentItem)
    #expect(KeyChord(.return, [.shift]) == .selectCurrentItem)
    #expect(KeyChord(.return, []) == .selectCurrentItem)
    #expect(KeyChord(.return, [.command]) == .selectCurrentItem)

    KeyboardShortcuts.setShortcut(.init(.h, modifiers: [.command, .shift]), for: .pasteHTMLSource)
    #expect(KeyChord(.h, [.command, .shift]) == .pasteHTMLSource)
    #expect(KeyChord(.return, [.control]) == .selectCurrentItem)
    #expect(!HistoryItem.supportedPins.contains("h"))

    KeyboardShortcuts.setShortcut(nil, for: .pasteHTMLSource)
    #expect(KeyChord(.h, [.command, .shift]) != .pasteHTMLSource)
    #expect(KeyChord(.return, [.control]) == .selectCurrentItem)
  }
}

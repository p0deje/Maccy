import AppKit
import Testing
@testable import Maccy

nonisolated(unsafe) private var posted: [CGEvent] = []
nonisolated(unsafe) private var actions: [Slots.Action] = []

extension SharedStateTests {
  // Feeds synthetic key events to the tap handler: nothing is posted and no slot is touched.
  final class SlotsTests {
    private let savedPostEvent = Slots.postEvent
    private let savedPerform = Slots.perform

    private let cKey: Int64 = 8
    private let vKey: Int64 = 9
    private let oneKey: Int64 = 18
    private let twoKey: Int64 = 19
    private let aKey: Int64 = 0

    init() {
      Slots.postEvent = { posted.append($0) }
      Slots.perform = { actions.append($0) }
      command(down: false)
      posted = []
      actions = []
    }

    deinit {
      Slots.postEvent = savedPostEvent
      Slots.perform = savedPerform
    }

    @Test("Plain ⌘V pastes when V is released")
    func plainPaste() {
      command(down: true)
      #expect(!key(vKey, down: true))
      #expect(posted.isEmpty)
      #expect(!key(vKey, down: false))
      #expect(pastedCommandV())
      command(down: false)
    }

    @Test("⌘ + V held + 2 pastes slot 2 instead of the clipboard")
    func slotPaste() {
      command(down: true)
      #expect(!key(vKey, down: true))
      #expect(!key(twoKey, down: true))
      #expect(actions == [.paste(slot: 1)])
      #expect(!key(vKey, down: false))
      #expect(!key(twoKey, down: false))
      #expect(posted.isEmpty)
      command(down: false)
    }

    @Test("Holding V repeats paste like a normal ⌘V")
    func repeatedPaste() {
      command(down: true)
      _ = key(vKey, down: true)
      #expect(key(vKey, down: true, autorepeat: true))
      #expect(pastedCommandV())
      #expect(key(vKey, down: true, autorepeat: true))
      #expect(posted.isEmpty)
      #expect(key(vKey, down: false))
      command(down: false)
    }

    @Test("Releasing ⌘ before V pastes right away")
    func commandReleasedFirst() {
      command(down: true)
      _ = key(vKey, down: true)
      command(down: false)
      #expect(pastedCommandV())
      #expect(!key(vKey, down: false, flags: []))
      #expect(posted.isEmpty)
    }

    @Test("Another key while ⌘V is held back is replayed after the paste")
    func otherKeyReplayed() {
      command(down: true)
      _ = key(vKey, down: true)
      #expect(!key(aKey, down: true))
      #expect(posted.count == 3)
      #expect(posted.last?.getIntegerValueField(.keyboardEventKeycode) == aKey)
      _ = key(aKey, down: false)
      _ = key(vKey, down: false)
      command(down: false)
    }

    @Test("⌘ + C held + 1 saves slot 1 and the copy itself passes")
    func slotSave() {
      command(down: true)
      #expect(key(cKey, down: true))
      #expect(key(cKey, down: true, autorepeat: true))
      #expect(!key(oneKey, down: true))
      #expect(!key(oneKey, down: false))
      #expect(key(cKey, down: false))
      #expect(actions == [.save(slot: 0, changeCount: NSPasteboard.general.changeCount)])
      command(down: false)
    }

    @Test("A digit after C is released saves nothing, so ⌘C then ⌘V + 1 can't overwrite a slot")
    func copyReleasedBeforeDigit() {
      command(down: true)
      _ = key(cKey, down: true)
      _ = key(cKey, down: false)
      #expect(key(oneKey, down: true))
      #expect(key(oneKey, down: false))
      #expect(actions.isEmpty)
      command(down: false)
    }

    @Test("Plain ⌘1 and ⌘⇧V pass to the front app")
    func otherShortcutsPass() {
      command(down: true)
      #expect(key(oneKey, down: true))
      #expect(key(oneKey, down: false))
      #expect(key(vKey, down: true, flags: [.maskCommand, .maskShift]))
      #expect(key(vKey, down: false, flags: [.maskCommand, .maskShift]))
      #expect(posted.isEmpty)
      #expect(actions.isEmpty)
      command(down: false)
    }

    @Test("Events posted by Maccy pass untouched")
    func markedEventsPass() {
      let event = keyEvent(vKey, down: true, flags: .maskCommand)
      event.setIntegerValueField(.eventSourceUserData, value: Slots.marker)
      #expect(Slots.handle(.keyDown, event))
    }

    private func keyEvent(_ code: Int64, down: Bool, flags: CGEventFlags) -> CGEvent {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
      event.flags = flags
      return event
    }

    private func key(_ code: Int64, down: Bool, flags: CGEventFlags = .maskCommand, autorepeat: Bool = false) -> Bool {
      let event = keyEvent(code, down: down, flags: flags)
      if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
      return Slots.handle(down ? .keyDown : .keyUp, event)
    }

    private func command(down: Bool) {
      _ = Slots.handle(.flagsChanged, keyEvent(55, down: down, flags: down ? .maskCommand : []))
    }

    private func pastedCommandV() -> Bool {
      defer { posted = [] }
      return posted.count == 2 && posted.allSatisfy {
        $0.getIntegerValueField(.keyboardEventKeycode) == vKey && $0.flags.contains(.maskCommand)
          && $0.getIntegerValueField(.eventSourceUserData) == Slots.marker
      }
    }
  }
}

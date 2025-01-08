import Carbon
import XCTest

class OpenShortcutUITests: BaseTest {

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString
  let copy3 = UUID().uuidString

  override func setUp() {
    super.setUp()

    copyToClipboard(copy3)
    copyToClipboard(copy2)
    copyToClipboard(copy1)
  }

  func testOpenAndClose() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    assertPopupAppeared()

    // Release the 'C' key but keep the popup open.
    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    assertPopupAppeared()

    // Release the 'Shift' key and assert that the popup remains open - "normal" mode.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    assertPopupAppeared()

    // Release the 'CMD' key and assert that the popup remains open - "normal" mode.
    let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    commandUp.flags = []
    commandUp.post(tap: .cghidEventTap)

    assertPopupAppeared()

    // Press shortcut again and assert the window closes
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    assertPopupDismissed()
  }

  func testOpenAndSelectSecondItem() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    assertPopupAppeared()

    // Press C 1 more time while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)

    // Release the 'Shift' key and assert that the popup closes.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testOpenAndSelectThirdItem() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    assertPopupAppeared()

    // Press C 2 more times while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)

    // Release the 'Shift' key and assert that the popup closes.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy3)
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }
}

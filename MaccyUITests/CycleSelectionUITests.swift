import Carbon
import XCTest

class CycleSelectionUITests: BaseTest {

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
    // Simulate the popup hotkey press (Cmd + Shift + V).
    let vDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)!
    vDown.flags = [.maskCommand, .maskShift]
    vDown.post(tap: .cghidEventTap)

    // Wait for the popup to appear.
    waitUntilPoppedUp()

    // Release the 'V' key but keep the popup open.
    let vUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)!
    vUp.flags = [.maskCommand, .maskShift]
    vUp.post(tap: .cghidEventTap)

    // Assert that the popup is still visible.
    waitUntilPoppedUp()

    // Release the 'Shift' key and assert that the popup closes.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    waitUntilDismissed()
  }

  func testOpenAndSelectSecondItem() throws {
    // Simulate the popup hotkey press (Cmd + Shift + V).
    let vDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)!
    vDown.flags = [.maskCommand, .maskShift]
    vDown.post(tap: .cghidEventTap)

    // Wait for the popup to appear.
    waitUntilPoppedUp()

    vDown.post(tap: .cghidEventTap)

    // Release the 'Shift' key and assert that the popup closes.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    waitUntilDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testOpenAndSelectThirdItem() throws {
    // Simulate the popup hotkey press (Cmd + Shift + V).
    let vDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)!
    vDown.flags = [.maskCommand, .maskShift]
    vDown.post(tap: .cghidEventTap)

    // Wait for the popup to appear.
    waitUntilPoppedUp()

    vDown.post(tap: .cghidEventTap)
    vDown.post(tap: .cghidEventTap)

    // Release the 'Shift' key and assert that the popup closes.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    waitUntilDismissed()
    assertPasteboardStringEquals(copy3)
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }
}

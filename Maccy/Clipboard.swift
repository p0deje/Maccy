import AppKit
import Carbon

class Clipboard {
  typealias OnNewCopyHook = (String) -> Void
  typealias OnRemovedCopyHook = () -> Void

  private let pasteboard = NSPasteboard.general
  private let timerInterval = 1.0

  private var changeCount: Int
  private var onNewCopyHooks: [OnNewCopyHook]
  private var onRemovedCopyHooks: [OnRemovedCopyHook]

  init() {
    changeCount = pasteboard.changeCount
    onNewCopyHooks = []
    onRemovedCopyHooks = []
  }

  func onNewCopy(_ hook: @escaping OnNewCopyHook) {
    onNewCopyHooks.append(hook)
  }

  func onRemovedCopy(_ hook: @escaping OnRemovedCopyHook) {
    onRemovedCopyHooks.append(hook)
  }

  func startListening() {
    Timer.scheduledTimer(timeInterval: timerInterval,
                         target: self,
                         selector: #selector(checkForChangesInPasteboard),
                         userInfo: nil,
                         repeats: true)
  }

  func copy(_ string: String) {
    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
    pasteboard.setString(string, forType: NSPasteboard.PasteboardType.string)
  }

  // Based on https://github.com/Clipy/Clipy/blob/develop/Clipy/Sources/Services/PasteService.swift.
  func paste() {
    checkAccessibilityPermissions()

    DispatchQueue.main.async {
      let vCode = UInt16(kVK_ANSI_V)
      let source = CGEventSource(stateID: .combinedSessionState)
      // Disable local keyboard events while pasting
      source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                         state: .eventSuppressionStateSuppressionInterval)

      let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true)
      let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
      keyVDown?.flags = .maskCommand
      keyVUp?.flags = .maskCommand
      keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
      keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
  }

  @objc
  func checkForChangesInPasteboard() {
    guard pasteboard.changeCount != changeCount else {
      return
    }

    if let lastItem = pasteboard.pasteboardItems?.last {
      if let lastItemString = lastItem.string(forType: .string) {
        for hook in onNewCopyHooks {
          hook(lastItemString)
        }
      }
    } else {
      for hook in onRemovedCopyHooks {
        hook()
      }
    }

    changeCount = pasteboard.changeCount
  }

  private func checkAccessibilityPermissions() {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    AXIsProcessTrustedWithOptions(options)
  }
}

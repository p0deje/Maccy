import AppKit

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

  @objc
  func checkForChangesInPasteboard() {
    guard pasteboard.changeCount != changeCount else {
      return
    }

    if let lastItem = pasteboard.string(forType: NSPasteboard.PasteboardType.string) {
      for hook in onNewCopyHooks {
        hook(lastItem)
      }
    } else {
      for hook in onRemovedCopyHooks {
        hook()
      }
    }

    changeCount = pasteboard.changeCount
  }
}

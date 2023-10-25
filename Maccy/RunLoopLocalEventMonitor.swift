import AppKit

// Credits to https://github.com/sindresorhus/KeyboardShortcuts/commit/8b1a9ce78c2f35c8a55dcc95897573abd2cc4f6e.
final class RunLoopLocalEventMonitor {
  private let runLoopMode: RunLoop.Mode
  private let callback: (NSEvent) -> NSEvent?
  private let observer: CFRunLoopObserver

  private var started: Bool = false

  init(
    runLoopMode: RunLoop.Mode,
    callback: @escaping (NSEvent) -> NSEvent?
  ) {
    self.runLoopMode = runLoopMode
    self.callback = callback

    self.observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeSources.rawValue, true, 0) { _, _ in
      // Pull all events from the queue and handle the ones matching the given types.
      // As non-processes events are redispatched we have to gather them first before
      // processing to avoid infinite loops.
      var eventsToHandle = [NSEvent]()

      // Note: Non-processed events are redispatched and may therefore be out of order with respect to other events.
      //       Even though we are only interested in keydown events we deque the keyUp events as well to preserve
      //       their order.
      while let eventToHandle = NSApp.nextEvent(
        matching: [.keyDown, .keyUp], until: nil, inMode: .default, dequeue: true
      ) {
        eventsToHandle.append(eventToHandle)
      }

      // Iterate over the gathered events, instead of doing it directly in the `while` loop,
      // to avoid potential infinite loops caused by re-retrieving undiscarded events.
      for eventToHandle in eventsToHandle {
        if let callbackEvent = callback(eventToHandle) {
          NSApp.postEvent(callbackEvent, atStart: false)
        }
      }
    }
  }

  deinit {
    stop()
  }

  func start() {
    guard !started else { return }

    CFRunLoopAddObserver(RunLoop.current.getCFRunLoop(), observer, CFRunLoopMode(runLoopMode.rawValue as CFString))
    started = true
  }

  func stop() {
    CFRunLoopRemoveObserver(RunLoop.current.getCFRunLoop(), observer, CFRunLoopMode(runLoopMode.rawValue as CFString))
    started = false
  }
}

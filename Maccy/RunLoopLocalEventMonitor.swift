import AppKit

// Credits to https://github.com/sindresorhus/KeyboardShortcuts/commit/8b1a9ce78c2f35c8a55dcc95897573abd2cc4f6e.
final class RunLoopLocalEventMonitor {
  private let runLoopMode: RunLoop.Mode
  private let callback: (NSEvent) -> NSEvent?
  private let observer: CFRunLoopObserver

  init(
    events: NSEvent.EventTypeMask,
    runLoopMode: RunLoop.Mode,
    callback: @escaping (NSEvent) -> NSEvent?
  ) {
    self.runLoopMode = runLoopMode
    self.callback = callback

    self.observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeSources.rawValue, true, 0) { _, _ in
      // Pull all events from the queue and handle the ones matching the given types.
      // Non-matching events are left untouched, maintaining their order in the queue.
      var eventsToHandle = [NSEvent]()

      while let eventToHandle = NSApp.nextEvent(
        matching: [.keyDown, .keyUp], until: nil, inMode: .default, dequeue: true
      ) {
        eventsToHandle.append(eventToHandle)
      }

      // Iterate over the gathered events, instead of doing it directly in the `while` loop,
      // to avoid potential infinite loops caused by re-retrieving undiscarded events.
      for eventToHandle in eventsToHandle {
        var handledEvent: NSEvent?

        if !events.contains(NSEvent.EventTypeMask(rawValue: 1 << eventToHandle.type.rawValue)) {
          handledEvent = eventToHandle
        } else if let callbackEvent = callback(eventToHandle) {
          handledEvent = callbackEvent
        }

        guard let handledEvent else {
          continue
        }

        NSApp.postEvent(handledEvent, atStart: false)
      }
    }
  }

  deinit {
    stop()
  }

  @discardableResult
  func start() -> Self {
    CFRunLoopAddObserver(RunLoop.current.getCFRunLoop(), observer, CFRunLoopMode(runLoopMode.rawValue as CFString))
    return self
  }

  func stop() {
    CFRunLoopRemoveObserver(RunLoop.current.getCFRunLoop(), observer, CFRunLoopMode(runLoopMode.rawValue as CFString))
  }
}

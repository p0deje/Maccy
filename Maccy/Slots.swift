import AppKit

// Hold ⌘, press C then 1/2/3 to save the copied content into a slot.
// Hold ⌘ and V, press 1/2/3 to paste a slot.
// A plain ⌘V is held back and pasted as soon as V is released.
// Not on the main actor (the module default): the tap runs on its own thread.
nonisolated enum Slots {
  enum Action: Equatable {
    case save(slot: Int, changeCount: Int)
    case paste(slot: Int)
  }

  static let marker: Int64 = 0x4D61_6363 // Marks events we post so the tap lets them through.

  // Replaced in tests, so no real keystrokes are posted and no slots are touched.
  nonisolated(unsafe) static var postEvent: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
  nonisolated(unsafe) static var perform: (Action) -> Void = { action in
    DispatchQueue.main.async { run(action) }
  }

  private static let cKey: Int64 = 8
  private static let vKey: Int64 = 9
  private static let digitKeys: [Int64: Int] = [18: 0, 19: 1, 20: 2] // 1, 2, 3
  private static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
  // Same flags as Clipboard.paste(): ⌘ plus the left ⌘ device bit some apps check.
  private static let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
  private static let url = URL.applicationSupportDirectory.appending(path: "Maccy/Slots.plist")

  // Tap, enabled flag and slot contents are only touched on the main thread.
  nonisolated(unsafe) private static var tap: CFMachPort?
  nonisolated(unsafe) private static var enabled = false
  // Each slot is a list of pasteboard items (type → data); empty means the slot is unset.
  nonisolated(unsafe) private static var slots: [[[String: Data]]] = [[], [], []]
  // Key state is only touched on the tap thread, so keystrokes never wait for the main thread.
  nonisolated(unsafe) private static var copyChangeCount: Int?
  nonisolated(unsafe) private static var pastePending = false
  nonisolated(unsafe) private static var swallowedKeyUps: Set<Int64> = []

  static func start(prompt: Bool = true) {
    enabled = true
    guard tap == nil else { return }

    if let data = try? Data(contentsOf: url),
       let saved = try? PropertyListDecoder().decode([[[String: Data]]].self, from: data),
       saved.count == slots.count {
      slots = saved
    }

    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(types.reduce(0) { $0 | (1 << $1.rawValue) }),
      callback: { _, type, event, _ in
        Slots.handle(type, event) ? Unmanaged.passUnretained(event) : nil
      },
      userInfo: nil
    )

    guard tap != nil else {
      // Accessibility permission is not granted yet: ask once, then start as soon as it is.
      if prompt {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        if enabled { start(prompt: false) }
      }
      return
    }

    copyChangeCount = nil
    pastePending = false
    swallowedKeyUps = []

    let thread = Thread {
      guard let tap = Slots.tap else { return }
      CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
      // Returns once the tap is invalidated in stop().
      CFRunLoopRun()
    }
    thread.qualityOfService = .userInteractive
    thread.start()
  }

  static func stop() {
    enabled = false
    guard let tap else { return }

    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    self.tap = nil
  }

  // Returns false to swallow the event.
  static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return true
    }

    guard event.getIntegerValueField(.eventSourceUserData) != marker else { return true }

    let key = event.getIntegerValueField(.keyboardEventKeycode)
    let commandOnly = event.flags.intersection(modifiers) == .maskCommand

    switch type {
    case .flagsChanged:
      if !event.flags.contains(.maskCommand) {
        copyChangeCount = nil
        flushPaste()
      }
      return true

    case .keyUp:
      if key == vKey { flushPaste() }
      return swallowedKeyUps.remove(key) == nil

    case .keyDown:
      return handleKeyDown(event, key: key, commandOnly: commandOnly)

    default:
      return true
    }
  }

  private static func handleKeyDown(_ event: CGEvent, key: Int64, commandOnly: Bool) -> Bool {
    if commandOnly, let slot = digitKeys[key], pastePending || copyChangeCount != nil {
      swallowedKeyUps.insert(key)
      if pastePending {
        pastePending = false
        perform(.paste(slot: slot))
      } else if let count = copyChangeCount {
        perform(.save(slot: slot, changeCount: count))
      }
      return false
    }

    if commandOnly && key == vKey {
      if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        flushPaste()
        pastePending = true
        swallowedKeyUps.insert(key)
        return false
      }
      // V held down: paste now and let the repeats through, like a normal ⌘V.
      if pastePending {
        flushPaste()
        swallowedKeyUps.remove(key)
      }
      // Repeats after a slot paste are swallowed until V is released.
      return !swallowedKeyUps.contains(key)
    }

    copyChangeCount = commandOnly && key == cKey ? NSPasteboard.general.changeCount : nil

    // Another key while ⌘V is held back: paste first, then replay the key to keep the order.
    if pastePending {
      flushPaste()
      post(event.copy())
      return false
    }
    return true
  }

  private static func run(_ action: Action) {
    switch action {
    case .save(let slot, let changeCount):
      save(slot, after: changeCount)
    case .paste(let slot):
      paste(slot)
    }
  }

  private static func flushPaste() {
    guard pastePending else { return }
    pastePending = false
    postCommandV()
  }

  private static func save(_ slot: Int, after count: Int, tries: Int = 10) {
    let pasteboard = NSPasteboard.general

    // The app may not have written the copied content yet.
    if pasteboard.changeCount == count && tries > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { save(slot, after: count, tries: tries - 1) }
      return
    }

    slots[slot] = pasteboard.pasteboardItems?.map { item in
      Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
        item.data(forType: type).map { (type.rawValue, $0) }
      })
    } ?? []

    do {
      try PropertyListEncoder().encode(slots).write(to: url, options: .atomic)
    } catch {
      NSLog("Failed to save slots: \(error)")
    }
  }

  private static func paste(_ slot: Int) {
    let items = slots[slot]
    guard !items.isEmpty else { return NSSound.beep() }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(items.map { contents in
      let item = NSPasteboardItem()
      contents.forEach { item.setData($1, forType: NSPasteboard.PasteboardType($0)) }
      return item
    })
    postCommandV()
  }

  private static func postCommandV() {
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(vKey), keyDown: keyDown)
      event?.flags = commandFlags
      post(event)
    }
  }

  private static func post(_ event: CGEvent?) {
    guard let event else { return }
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    postEvent(event)
  }
}

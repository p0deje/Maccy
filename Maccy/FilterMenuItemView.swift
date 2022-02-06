import AppKit
import Carbon
import Sauce

// swiftlint:disable type_body_length
class FilterMenuItemView: NSView, NSTextFieldDelegate {
  @objc public var title: String {
    get { return titleField.stringValue }
    set { titleField.stringValue = newValue }
  }

  private let eventSpecs = [
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyDown)),
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyRepeat))
  ]
  private let searchThrottler = Throttler(minimumDelay: 0.2)

  lazy private var horizontalTitleAndSearchConstraint: String = {
    if #available(macOS 11, *) {
      return "|-(==14)-[titleField]-[queryField]-(==14)-|"
    } else {
      return "|-[titleField]-[queryField]-(==10)-|"
    }
  }()
  lazy private var horizontalSearchOnlyConstraint: String = {
    if #available(macOS 11, *) {
      return "|-(==14)-[queryField]-(==14)-|"
    } else {
      return "|-(==10)-[queryField]-(==10)-|"
    }
  }()

  private var layoutConstraints: [String] {
    var constraints: [String] = []

    if !UserDefaults.standard.hideSearch {
      if UserDefaults.standard.hideTitle {
        constraints.append(horizontalSearchOnlyConstraint)
      } else {
        constraints.append(horizontalTitleAndSearchConstraint)
        constraints.append("V:|-(==3)-[titleField]-(==3)-|")
      }
      constraints.append("V:|[queryField]-(==3)-|")
    }

    return constraints
  }

  private var eventHandler: EventHandlerRef?

  lazy private var titleField: NSTextField = { [unowned self] in
    let field = NSTextField(frame: NSRect.zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.stringValue = ""
    field.isBordered = false
    field.isEditable = false
    field.isEnabled = false
    field.drawsBackground = false
    field.font = NSFont.menuFont(ofSize: 15)
    field.textColor = NSColor.disabledControlTextColor
    field.cell!.usesSingleLineMode = true
    return field
  }()

  lazy private var queryField: NSTextField = { [unowned self] in
    let field = NSTextField(frame: NSRect.zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.stringValue = ""
    field.isBordered = true
    field.isEditable = true
    field.isEnabled = true
    field.isBezeled = true
    field.isHidden = false
    field.placeholderString = NSLocalizedString("search_placeholder", comment: "")
    field.bezelStyle = NSTextField.BezelStyle.roundedBezel
    field.delegate = self
    field.focusRingType = .none
    field.font = NSFont.menuFont(ofSize: 13)
    field.textColor = NSColor.disabledControlTextColor
    field.refusesFirstResponder = true
    field.cell!.usesSingleLineMode = true
    field.cell!.lineBreakMode = NSLineBreakMode.byTruncatingHead
    return field
  }()

  lazy private var customMenu: Menu? = { [unowned self] in
    return self.enclosingMenuItem?.menu as? Menu
  }()

  required init?(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.autoresizingMask = .width

    if !UserDefaults.standard.hideTitle {
      addSubview(titleField)
    }
    addSubview(queryField)

    let views = ["titleField": titleField, "queryField": queryField]
    for layoutConstraint in layoutConstraints {
      let constraint = NSLayoutConstraint.constraints(
        withVisualFormat: layoutConstraint,
        options: NSLayoutConstraint.FormatOptions(rawValue: 0),
        metrics: nil,
        views: views
      )
      addConstraints(constraint)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if window != nil {
      if let dispatcher = GetEventDispatcherTarget() {
        // Create pointer to our event processer.
        let eventProcessorPointer = UnsafeMutablePointer<Any>.allocate(capacity: 1)
        eventProcessorPointer.initialize(to: processInterceptedEvent)

        let eventHandlerCallback: EventHandlerUPP = { _, eventRef, userData in
          guard let event = eventRef else { return noErr }
          guard let callbackPointer = userData else { return noErr }

          // Call our event processor from pointer.
          let eventProcessPointer = UnsafeMutablePointer<(EventRef) -> (Bool)>(OpaquePointer(callbackPointer))
          let eventProcessed = eventProcessPointer.pointee(event)

          if eventProcessed {
            return noErr
          } else {
            return OSStatus(Carbon.eventNotHandledErr)
          }
        }

        InstallEventHandler(dispatcher, eventHandlerCallback, 2, eventSpecs, eventProcessorPointer, &eventHandler)
      }
    } else {
      RemoveEventHandler(eventHandler)
      DispatchQueue.main.async {
        self.setQuery("")
        self.queryField.refusesFirstResponder = true
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ||
       NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
      NSColor(named: "MenuColor")?.setFill()
      dirtyRect.fill()
    }
    queryField.refusesFirstResponder = false
  }

  // Process query when search field was focused (i.e. user clicked on it).
  func controlTextDidChange(_ obj: Notification) {
    fireNotification()
  }

  // Switch to main window if Tab is pressed when search is focused.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(insertTab(_:)) {
      window?.makeFirstResponder(window)
      return true
    }
    return false
  }

  private func fireNotification() {
    searchThrottler.throttle {
      self.customMenu?.updateFilter(filter: self.queryField.stringValue)
    }
  }

  private func setQuery(_ newQuery: String) {
    guard queryField.stringValue != newQuery else {
      return
    }

    queryField.stringValue = newQuery
    fireNotification()
  }

  private func processInterceptedEvent(_ eventRef: EventRef) -> Bool {
    guard let event = NSEvent(eventRef: UnsafeRawPointer(eventRef)) else {
      return false
    }

    if event.type != NSEvent.EventType.keyDown {
      return false
    }

    guard let key = Sauce.shared.key(by: Int(event.keyCode)) else {
      return false
    }
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let chars = event.charactersIgnoringModifiers

    let firstResponder = window?.firstResponder
    if firstResponder == queryField ||
        firstResponder == queryField.currentEditor() &&
        !isPasteEvent(key: key, modifierFlags: modifierFlags) {
      return false
    }

    return processKeyDownEvent(key: key, modifierFlags: modifierFlags, chars: chars)
  }

  // swiftlint:disable cyclomatic_complexity
  // swiftlint:disable function_body_length
  private func processKeyDownEvent(key: Key, modifierFlags: NSEvent.ModifierFlags, chars: String?) -> Bool {
    if Keys.shouldPassThrough(key) {
      return false
    }

    switch key {
    case Key.delete:
      processDeleteKey(menu: customMenu, key: key, modifierFlags: modifierFlags)
      return true
    case Key.h:
      if modifierFlags.contains(.control) {
        processDeleteKey(menu: customMenu, key: key, modifierFlags: modifierFlags)
        return true
      }
    case Key.u:
      if modifierFlags.contains(.control) {
        setQuery("")
        return true
      }
    case Key.w:
      if modifierFlags.contains(.control) {
        removeLastWordInSearchField()
        return true
      }
    case Key.j, Key.n:
      if modifierFlags.contains(.control) {
        customMenu?.selectNext(alt: false)
        return true
      }
    case Key.p:
      if modifierFlags.contains(.option) {
        customMenu?.pinOrUnpin()
        queryField.stringValue = "" // clear search field just in case
        return true
      } else if modifierFlags.contains(.control) {
        customMenu?.selectPrevious(alt: false)
        return true
      }
    case Key.k:
      if modifierFlags.contains(.control) {
        customMenu?.selectPrevious(alt: false)
        return true
      }
    case Key.return, Key.keypadEnter, Key.upArrow, Key.downArrow:
      processSelectionKey(menu: customMenu, key: key, modifierFlags: modifierFlags)
      return true
    case GlobalHotKey.key:
      if modifierFlags == GlobalHotKey.modifierFlags {
        customMenu?.cancelTracking()
        return false
      }
    case Key.comma:
      // Hidden items can't be selected with key equivalents,
      // so emulate the behavior like items are visible.
      if UserDefaults.standard.hideFooter && modifierFlags == MenuFooter.preferences.keyEquivalentModifierMask {
        performMenuItemAction(MenuFooter.preferences.rawValue)
        return false
      }
    default:
      break
    }

    if isPasteEvent(key: key, modifierFlags: modifierFlags) {
      queryField.becomeFirstResponder()
      queryField.currentEditor()?.paste(nil)
      return true
    }

    if modifierFlags.contains(.command) || modifierFlags.contains(.control) || modifierFlags.contains(.option) {
      return false
    }

    if let chars = chars {
      if chars.count == 1 {
        if UserDefaults.standard.avoidTakingFocus {
          // append character to the search field to trigger
          // and stop event from being propagated
          setQuery("\(queryField.stringValue)\(chars)")
          return true
        } else {
          // make the search field first responder
          // and propagate event to it
          focusQueryField()
          return false
        }
      }
    }

    return false
  }
  // swiftlint:enable cyclomatic_complexity
  // swiftlint:enable function_body_length

  private func processDeleteKey(menu: Menu?, key: Key, modifierFlags: NSEvent.ModifierFlags) {
    switch modifierFlags {
    case NSEvent.ModifierFlags([.command]):
      setQuery("")
    case NSEvent.ModifierFlags([.option]):
      menu?.delete()
    case MenuFooter.clear.keyEquivalentModifierMask:
      if UserDefaults.standard.hideFooter {
        performMenuItemAction(MenuFooter.clear.rawValue)
      }
    case MenuFooter.clearAll.keyEquivalentModifierMask:
      if UserDefaults.standard.hideFooter {
        performMenuItemAction(MenuFooter.clearAll.rawValue)
      }
    default:
      if !queryField.stringValue.isEmpty {
        setQuery(String(queryField.stringValue.dropLast()))
      }
    }
  }

  private func processSelectionKey(menu: Menu?, key: Key, modifierFlags: NSEvent.ModifierFlags) {
    switch key {
    case .return, .keypadEnter:
      menu?.select()
    case .upArrow:
      if modifierFlags.contains(.command) {
        menu?.selectFirst()
      } else {
        menu?.selectPrevious(alt: modifierFlags.contains(.option))
      }
    case .downArrow:
      if modifierFlags.contains(.command) {
        menu?.selectLast()
      } else {
        menu?.selectNext(alt: modifierFlags.contains(.option))
      }
    default: ()
    }
  }

  private func focusQueryField() {
    queryField.becomeFirstResponder()
    // Making text field a first responder selects all the text by default.
    // We need to make sure events are appended to existing text.
    if let fieldEditor = queryField.currentEditor() {
      fieldEditor.selectedRange = NSRange(location: fieldEditor.selectedRange.length, length: 0)
    }
  }

  private func removeLastWordInSearchField() {
    let searchValue = queryField.stringValue
    let newValue = searchValue.split(separator: " ").dropLast().joined(separator: " ")

    if newValue.isEmpty {
      setQuery("")
    } else {
      setQuery("\(newValue) ")
    }
  }

  private func performMenuItemAction(_ tag: Int) {
    guard let menuItem = customMenu?.item(withTag: tag) else {
      return
    }

    _ = menuItem.target?.perform(menuItem.action, with: menuItem)
    customMenu?.cancelTracking()
  }

  private func isPasteEvent(key: Key, modifierFlags: NSEvent.ModifierFlags) -> Bool {
    return key == .v && modifierFlags == NSEvent.ModifierFlags([.command])
  }
}
// swiftlint:enable type_body_length

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
    field.font = .menuFont(ofSize: 15)
    field.textColor = .disabledControlTextColor
    field.cell?.usesSingleLineMode = true
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
    field.bezelStyle = .roundedBezel
    field.delegate = self
    field.focusRingType = .none
    field.font = .menuFont(ofSize: 13)
    field.textColor = .disabledControlTextColor
    field.refusesFirstResponder = true
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byTruncatingHead
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
        eventProcessorPointer.initialize(to: processInterceptedEventRef)

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

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(insertTab(_:)) {
      // Switch to main window if Tab is pressed when search is focused.
      window?.makeFirstResponder(window)
      return true
    }

    if commandSelector == NSSelectorFromString("noop:") {
      // Support Control-W when search is focused.
      if let event = NSApp.currentEvent {
        return processInterceptedEvent(event)
      }
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

  private func processInterceptedEventRef(_ eventRef: EventRef) -> Bool {
    guard let event = NSEvent(eventRef: UnsafeRawPointer(eventRef)) else {
      return false
    }

    return processInterceptedEvent(event)
  }

  private func processInterceptedEvent(_ event: NSEvent) -> Bool {
    if event.type != NSEvent.EventType.keyDown {
      return false
    }

    guard let key = Sauce.shared.key(by: Int(event.keyCode)) else {
      return false
    }
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let chars = event.charactersIgnoringModifiers

    return processKeyDownEvent(key: key, modifierFlags: modifierFlags, chars: chars)
  }

  // swiftlint:disable cyclomatic_complexity
  // swiftlint:disable function_body_length
  private func processKeyDownEvent(key: Key, modifierFlags: NSEvent.ModifierFlags, chars: String?) -> Bool {
    switch KeyChord(key, modifierFlags) {
    case .clearSearch:
      setQuery("")
      return true
    case .deleteCurrentItem:
      customMenu?.delete()
      return true
    case .clearHistory:
      if UserDefaults.standard.hideFooter {
        performMenuItemAction(MenuFooter.clear.rawValue)
        return true
      }
    case .clearHistoryAll:
      if UserDefaults.standard.hideFooter {
        performMenuItemAction(MenuFooter.clearAll.rawValue)
        return true
      }
    case .deleteOneCharFromSearch:
      if !queryField.stringValue.isEmpty {
        setQuery(String(queryField.stringValue.dropLast()))
        return true
      }
    case .deleteLastWordFromSearch:
      removeLastWordInSearchField()
      return true
    case .moveToNext:
      customMenu?.selectNext()
      return true
    case .moveToPrevious:
      customMenu?.selectPrevious()
      return true
    case .pinOrUnpin:
      if let menu = customMenu, menu.pinOrUnpin() {
        queryField.stringValue = "" // clear search field just in case
        return true
      }
    case .hide:
      customMenu?.cancelTracking()
      return false
    case .openPreferences:
      if UserDefaults.standard.hideFooter {
        performMenuItemAction(MenuFooter.preferences.rawValue)
        return false
      }
    case .paste:
      queryField.becomeFirstResponder()
      queryField.currentEditor()?.paste(nil)
      return true
    case .selectCurrentItem:
      customMenu?.select()
      return true
    case .ignored:
      return false
    default:
      ()
    }

    return processSingleCharacter(chars)
  }
  // swiftlint:enable cyclomatic_complexity
  // swiftlint:enable function_body_length

  private func processSingleCharacter(_ chars: String?) -> Bool {
    guard let char = chars, char.count == 1 else {
      return false
    }

    if UserDefaults.standard.avoidTakingFocus {
      // append character to the search field to trigger
      // and stop event from being propagated
      setQuery("\(queryField.stringValue)\(char)")
      return true
    } else {
      // make the search field first responder
      // and propagate event to it
      focusQueryField()
      return false
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
}
// swiftlint:enable type_body_length

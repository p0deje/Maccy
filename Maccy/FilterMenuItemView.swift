import AppKit
import Carbon
import HotKey

class FilterMenuItemView: NSView, NSTextFieldDelegate {
  @objc
  var title: String {
    get { return titleField.stringValue }
    set(newTitle) { titleField.stringValue = newTitle }
  }

  private let eventSpecs = [
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyDown)),
    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyRepeat))
  ]

  private let layoutConstraints = [
    "|-[titleField]-[queryField]-(==10)-|",
    "V:|-(==5)-[titleField]-(==2)-|",
    "V:|[queryField]-(==3)-|"
  ]

  private var eventHandler: EventHandlerRef?

  lazy private var titleField: NSTextField = { [unowned self] in
    let field = NSTextField(frame: NSRect.zero)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.stringValue = ""
    field.isBordered = false
    field.isEditable = false
    field.isEnabled = false
    field.drawsBackground = false
    field.font = NSFont.menuFont(ofSize: 13)
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
    field.isHidden = true
    field.bezelStyle = NSTextField.BezelStyle.roundedBezel
    field.delegate = self
    field.font = NSFont.menuFont(ofSize: 13)
    field.textColor = NSColor.disabledControlTextColor
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

    addSubview(titleField)
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
      setQuery("")
    }
  }

  func controlTextDidChange(_ obj: Notification) {
    updateVisibility()
    fireNotification()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(insertTab(_:)) {
      window?.makeFirstResponder(window)
      return true
    }
    return false
  }

  @objc
  func fireNotification() {
    if let menu = customMenu {
      menu.updateFilter(filter: queryField.stringValue)
    }
  }

  private func setQuery(_ newQuery: String) {
    guard queryField.stringValue != newQuery else {
      return
    }

    queryField.stringValue = newQuery
    updateVisibility()
    fireNotification()
  }

  private func updateVisibility() {
    queryField.isHidden = queryField.stringValue.isEmpty
  }

  private func processInterceptedEvent(_ eventRef: EventRef) -> Bool {
    let firstResponder = window?.firstResponder
    if firstResponder == queryField || firstResponder == queryField.currentEditor() {
      return false
    }

    guard let event = NSEvent(eventRef: UnsafeRawPointer(eventRef)) else {
      return false
    }

    if event.type != NSEvent.EventType.keyDown {
      return false
    }

    return processKeyDownEvent(event)
  }

  private func processKeyDownEvent(_ event: NSEvent) -> Bool {
    guard let key = Key(carbonKeyCode: UInt32(event.keyCode)) else {
      return false
    }
    let modifierFlags = event.modifierFlags

    if Keys.shouldPassThrough(key) {
      return false
    }

    if key == Key.delete {
      if modifierFlags.contains(.command) {
        setQuery("")
      } else {
        processDeleteKey(queryField.stringValue)
      }
      return true
    }

    if key == Key.return || key == Key.upArrow || key == Key.downArrow {
      if let menu = customMenu {
        processSelectionKey(menu: menu, key: key, modifierFlags: modifierFlags)
        return true
      }

      return false
    }

    if modifierFlags.contains(.command) || modifierFlags.contains(.control) || modifierFlags.contains(.option) {
      return false
    }

    if let chars = event.charactersIgnoringModifiers {
      if chars.count == 1 {
        appendSearchField(chars)
        return true
      }
    }

    return false
  }

  private func processDeleteKey(_ query: String) {
    if query.isEmpty == false {
      setQuery(String(query.dropLast()))
    }
  }

  private func processSelectionKey(menu: Menu, key: Key, modifierFlags: NSEvent.ModifierFlags) {
    switch key {
    case .return:
      menu.select()
    case .upArrow:
      if modifierFlags.contains(.command) {
        menu.selectFirst()
      } else {
        menu.selectPrevious()
      }
    case .downArrow:
      if modifierFlags.contains(.command) {
        menu.selectLast()
      } else {
        menu.selectNext()
      }
    default: ()
    }
  }

  private func appendSearchField(_ chars: String) {
    setQuery("\(queryField.stringValue)\(chars)")
  }
}

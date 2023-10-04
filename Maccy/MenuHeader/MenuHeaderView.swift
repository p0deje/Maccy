import Carbon
import Cocoa
import Sauce

class MenuHeaderView: NSView, NSSearchFieldDelegate {
  @IBOutlet weak var queryField: NSSearchField!
  @IBOutlet weak var titleField: NSTextField!

  @IBOutlet weak var horizontalLeftPadding: NSLayoutConstraint!
  @IBOutlet weak var horizontalRightPadding: NSLayoutConstraint!
  @IBOutlet weak var titleAndSearchSpacing: NSLayoutConstraint!

  private let macOSXLeftPadding: CGFloat = 20.0
  private let macOSXRightPadding: CGFloat = 10.0
  private let searchThrottler = Throttler(minimumDelay: 0.4)

  private var characterPickerVisible: Bool {
    NSApp.windows.filter({ $0.isVisible }).map({ $0.className }).contains("NSPanelViewBridge")
  }

  private lazy var eventMonitor = RunLoopLocalEventMonitor(runLoopMode: .eventTracking) { event in
    if self.processInterceptedEvent(event) {
      return nil
    } else {
      return event
    }
  }

  private lazy var customMenu: Menu? = self.enclosingMenuItem?.menu as? Menu
  private lazy var headerHeight = UserDefaults.standard.hideSearch ? 1 : 28
  private lazy var headerSize = NSSize(width: Menu.menuWidth, height: headerHeight)

  override func awakeFromNib() {
    autoresizingMask = .width
    setFrameSize(headerSize)

    queryField.delegate = self
    queryField.placeholderString = NSLocalizedString("search_placeholder", comment: "")

    if #available(macOS 11, *) {
      // all good
    } else {
      horizontalLeftPadding.constant = macOSXLeftPadding
      horizontalRightPadding.constant = macOSXRightPadding
    }

    if UserDefaults.standard.hideTitle {
      titleField.isHidden = true
      removeConstraint(titleAndSearchSpacing)
    }

    if UserDefaults.standard.hideSearch {
      constraints.forEach(removeConstraint)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if window != nil && customMenu?.isVisible == true {
      eventMonitor.start()
    } else if window == nil && customMenu?.isVisible == false {
      eventMonitor.stop()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    if #available(macOS 13, *) {
      // all good
    } else {
      if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ||
         NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        NSColor(named: "MenuColor")?.setFill()
        dirtyRect.fill()
      }
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

    return false
  }

  private func fireNotification() {
    searchThrottler.throttle {
      self.customMenu?.updateFilter(filter: self.queryField.stringValue)
    }
  }

  public func setQuery(_ newQuery: String) {
    guard queryField.stringValue != newQuery else {
      return
    }

    queryField.stringValue = newQuery
    fireNotification()
  }

  private func processInterceptedEvent(_ event: NSEvent) -> Bool {
    if event.type != NSEvent.EventType.keyDown {
      return false
    }

    guard let key = Sauce.shared.key(for: Int(event.keyCode)) else {
      return false
    }
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
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
      setQuery("")
      return true
    case .clearHistory:
      performMenuItemAction(MenuFooter.clear.rawValue)
      return true
    case .clearHistoryAll:
      performMenuItemAction(MenuFooter.clearAll.rawValue)
      return true
    case .deleteOneCharFromSearch:
      if !queryField.stringValue.isEmpty {
        setQuery(String(queryField.stringValue.dropLast()))
      }
      return true
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
      return true
    case .openPreferences:
      performMenuItemAction(MenuFooter.preferences.rawValue)
      return true
    case .paste:
      queryField.becomeFirstResponder()
      queryField.currentEditor()?.paste(nil)
      return true
    case .selectCurrentItem:
      customMenu?.select(queryField.stringValue)
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
    guard !characterPickerVisible else {
      return false
    }

    guard let char = chars, char.count == 1 else {
      return false
    }

    // Sometimes even though we attempt to activate Maccy,
    // it doesn't get active. This happens particularly with
    // password fields in Safari. Let's at least allow
    // search to work in these cases.
    // See https://github.com/p0deje/Maccy/issues/473.
    if UserDefaults.standard.avoidTakingFocus || !NSApp.isActive {
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
    // If the field is already focused, there is no need for force-focus it.
    // Worse, it breaks Korean input handling.
    // See https://github.com/p0deje/Maccy/issues/476 for details.
    guard queryField.currentEditor() == nil else {
      return
    }

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

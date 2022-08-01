import Cocoa

extension UserDefaults {
  public struct Keys {
    static let avoidTakingFocus = "avoidTakingFocus"
    static let clearOnQuit = "clearOnQuit"
    static let enabledPasteboardTypes = "enabledPasteboardTypes"
    static let fuzzySearch = "fuzzySearch"
    static let hideFooter = "hideFooter"
    static let hideSearch = "hideSearch"
    static let hideTitle = "hideTitle"
    static let ignoreEvents = "ignoreEvents"
    static let ignoreOnlyNextEvent = "ignoreOnlyNextEvent"
    static let ignoredApps = "ignoredApps"
    static let ignoredPasteboardTypes = "ignoredPasteboardTypes"
    static let imageMaxHeight = "imageMaxHeight"
    static let maxMenuItems = "maxMenuItems"
    static let migrations = "migrations"
    static let pasteByDefault = "pasteByDefault"
    static let pinTo = "pinTo"
    static let playSounds = "playSounds"
    static let popupPosition = "popupPosition"
    static let removeFormattingByDefault = "removeFormattingByDefault"
    static let saratovSeparator = "enableSaratovSeparator"
    static let showRecentCopyInMenuBar = "showRecentCopyInMenuBar"
    static let size = "historySize"
    static let sortBy = "sortBy"
    static let suppressClearAlert = "suppressClearAlert"

    static var showInStatusBar: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "showInStatusBarUITests" : "showInStatusBar"
    }

    static var storage: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "historyUITests" : "history"
    }
  }

  public struct Values {
    static let ignoredApps: [String] = []
    static let ignoredPasteboardTypes: [String] = []
    static let imageMaxHeight = 40.0
    static let maxMenuItems = 0
    static let migrations: [String: Bool] = [:]
    static let pinTo = "top"
    static let popupPosition = "cursor"
    static let showInStatusBar = true
    static let size = 200
    static let sortBy = "lastCopiedAt"
  }

  public var avoidTakingFocus: Bool {
    get { bool(forKey: Keys.avoidTakingFocus) }
    set { set(newValue, forKey: Keys.avoidTakingFocus) }
  }

  public var clearOnQuit: Bool {
    get { bool(forKey: Keys.clearOnQuit) }
    set { set(newValue, forKey: Keys.clearOnQuit) }
  }

  @objc dynamic public var enabledPasteboardTypes: Set<NSPasteboard.PasteboardType> {
    get {
      let types = array(forKey: Keys.enabledPasteboardTypes) as? [String] ?? []
      return Set(types.map({ NSPasteboard.PasteboardType($0) }))
    }
    set { set(Array(newValue.map({ $0.rawValue })), forKey: Keys.enabledPasteboardTypes) }
  }

  public var fuzzySearch: Bool {
    get { ProcessInfo.processInfo.arguments.contains("ui-testing") ? false : bool(forKey: Keys.fuzzySearch) }
    set { set(newValue, forKey: Keys.fuzzySearch) }
  }

  @objc dynamic public var hideFooter: Bool {
    get { bool(forKey: Keys.hideFooter) }
    set { set(newValue, forKey: Keys.hideFooter) }
  }

  @objc dynamic public var hideSearch: Bool {
    get { bool(forKey: Keys.hideSearch) }
    set { set(newValue, forKey: Keys.hideSearch) }
  }

  @objc dynamic public var hideTitle: Bool {
    get { bool(forKey: Keys.hideTitle) }
    set { set(newValue, forKey: Keys.hideTitle) }
  }

  @objc dynamic public var ignoreEvents: Bool {
    get { bool(forKey: Keys.ignoreEvents) }
    set { set(newValue, forKey: Keys.ignoreEvents) }
  }

  public var ignoreOnlyNextEvent: Bool {
    get { bool(forKey: Keys.ignoreOnlyNextEvent) }
    set { set(newValue, forKey: Keys.ignoreOnlyNextEvent) }
  }

  public var ignoredApps: [String] {
    get { array(forKey: Keys.ignoredApps) as? [String] ?? Values.ignoredApps }
    set { set(newValue, forKey: Keys.ignoredApps) }
  }

  public var ignoredPasteboardTypes: Set<String> {
    get { Set(array(forKey: Keys.ignoredPasteboardTypes) as? [String] ?? Values.ignoredPasteboardTypes) }
    set { set(Array(newValue), forKey: Keys.ignoredPasteboardTypes) }
  }

  @objc dynamic public var imageMaxHeight: Int {
    get { integer(forKey: Keys.imageMaxHeight) }
    set { set(newValue, forKey: Keys.imageMaxHeight) }
  }

  public var maxMenuItems: Int {
    get { integer(forKey: Keys.maxMenuItems) }
    set { set(newValue, forKey: Keys.maxMenuItems) }
  }

  public var migrations: [String: Bool] {
    get { dictionary(forKey: Keys.migrations) as? [String: Bool] ?? Values.migrations }
    set { set(newValue, forKey: Keys.migrations) }
  }

  @objc dynamic public var pasteByDefault: Bool {
    get { bool(forKey: Keys.pasteByDefault) }
    set { set(newValue, forKey: Keys.pasteByDefault) }
  }

  @objc dynamic public var pinTo: String {
    get { string(forKey: Keys.pinTo) ?? Values.pinTo }
    set { set(newValue, forKey: Keys.pinTo) }
  }

  public var playSounds: Bool {
    get { bool(forKey: Keys.playSounds) }
    set { set(newValue, forKey: Keys.playSounds) }
  }

  public var popupPosition: String {
    get { string(forKey: Keys.popupPosition) ?? Values.popupPosition }
    set { set(newValue, forKey: Keys.popupPosition) }
  }

  @objc dynamic public var removeFormattingByDefault: Bool {
    get { bool(forKey: Keys.removeFormattingByDefault) }
    set { set(newValue, forKey: Keys.removeFormattingByDefault) }
  }

  public var saratovSeparator: Bool {
    get { bool(forKey: Keys.saratovSeparator) }
    set { set(newValue, forKey: Keys.saratovSeparator) }
  }

  @objc dynamic public var showInStatusBar: Bool {
    get { ProcessInfo.processInfo.arguments.contains("ui-testing") ? true : bool(forKey: Keys.showInStatusBar) }
    set { set(newValue, forKey: Keys.showInStatusBar) }
  }

  @objc dynamic public var showRecentCopyInMenuBar: Bool {
    get { bool(forKey: Keys.showRecentCopyInMenuBar) }
    set { set(newValue, forKey: Keys.showRecentCopyInMenuBar) }
  }

  public var size: Int {
    get { integer(forKey: Keys.size) }
    set { set(newValue, forKey: Keys.size) }
  }

  @objc dynamic public var sortBy: String {
    get { string(forKey: Keys.sortBy) ?? Values.sortBy }
    set { set(newValue, forKey: Keys.sortBy) }
  }

  public var suppressClearAlert: Bool {
    get { bool(forKey: Keys.suppressClearAlert) }
    set { set(newValue, forKey: Keys.suppressClearAlert) }
  }
}

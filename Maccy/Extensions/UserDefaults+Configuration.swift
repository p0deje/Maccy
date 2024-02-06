import AppKit

extension UserDefaults {
  public struct Keys {
    static let avoidTakingFocus = "avoidTakingFocus"
    static let clearOnQuit = "clearOnQuit"
    static let clearSystemClipboard = "clearSystemClipboard"
    static let clipboardCheckInterval = "clipboardCheckInterval"
    static let enabledPasteboardTypes = "enabledPasteboardTypes"
    static let hideFooter = "hideFooter"
    static let hideSearch = "hideSearch"
    static let hideTitle = "hideTitle"
    static let ignoreEvents = "ignoreEvents"
    static let ignoreOnlyNextEvent = "ignoreOnlyNextEvent"
    static let ignoreAllAppsExceptListed = "ignoreAllAppsExceptListed"
    static let ignoredApps = "ignoredApps"
    static let ignoredPasteboardTypes = "ignoredPasteboardTypes"
    static let imageMaxHeight = "imageMaxHeight"
    static let lastReviewRequestedAt = "lastReviewRequestedAt"
    static let maxMenuItems = "maxMenuItems"
    static let maxMenuItemLength = "maxMenuItemLength"
    static let menuIcon = "menuIcon"
    static let migrations = "migrations"
    static let numberOfUsages = "numberOfUsages"
    static let pasteByDefault = "pasteByDefault"
    static let pinTo = "pinTo"
    static let popupPosition = "popupPosition"
    static let popupScreen = "popupScreen"
    static let previewDelay = "previewDelay"
    static let searchMode = "searchMode"
    static let removeFormattingByDefault = "removeFormattingByDefault"
    static let showRecentCopyInMenuBar = "showRecentCopyInMenuBar"
    static let showSpecialSymbols = "showSpecialSymbols"
    static let size = "historySize"
    static let sortBy = "sortBy"
    static let suppressClearAlert = "suppressClearAlert"
    static let ignoreRegexp = "ignoreRegexp"
    static let highlightMatch = "highlightMatch"

    static var showInStatusBar: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "showInStatusBarUITests" : "showInStatusBar"
    }

    static var storage: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "historyUITests" : "history"
    }
  }

  public struct Values {
    static let clipboardCheckInterval = 0.5
    static let ignoredApps: [String] = []
    static let ignoredPasteboardTypes: [String] = []
    static let ignoreRegexp: [String] = []
    static let imageMaxHeight = 40.0
    static let maxMenuItems = 0
    static let maxMenuItemLength = 50
    static let migrations: [String: Bool] = [:]
    static let pinTo = "top"
    static let popupPosition = "cursor"
    static let previewDelay = 1500
    static let searchMode = "exact"
    static let showInStatusBar = true
    static let showSpecialSymbols = true
    static let size = 200
    static let sortBy = "lastCopiedAt"
    static let menuIcon = "maccy"
    static let highlightMatch = "bold"
  }

  public var avoidTakingFocus: Bool {
    get { bool(forKey: Keys.avoidTakingFocus) }
    set { set(newValue, forKey: Keys.avoidTakingFocus) }
  }

  public var clearOnQuit: Bool {
    get { bool(forKey: Keys.clearOnQuit) }
    set { set(newValue, forKey: Keys.clearOnQuit) }
  }

  public var clearSystemClipboard: Bool {
    get { bool(forKey: Keys.clearSystemClipboard) }
    set { set(newValue, forKey: Keys.clearSystemClipboard) }
  }

  @objc dynamic var clipboardCheckInterval: Double {
    get { double(forKey: Keys.clipboardCheckInterval) }
    set { set(newValue, forKey: Keys.clipboardCheckInterval) }
  }

  @objc dynamic public var enabledPasteboardTypes: Set<NSPasteboard.PasteboardType> {
    get {
      let types = array(forKey: Keys.enabledPasteboardTypes) as? [String] ?? []
      return Set(types.map({ NSPasteboard.PasteboardType($0) }))
    }
    set { set(Array(newValue.map({ $0.rawValue })), forKey: Keys.enabledPasteboardTypes) }
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

  public var ignoreAllAppsExceptListed: Bool {
    get { bool(forKey: Keys.ignoreAllAppsExceptListed) }
    set { set(newValue, forKey: Keys.ignoreAllAppsExceptListed) }
  }

  public var ignoredApps: [String] {
    get { array(forKey: Keys.ignoredApps) as? [String] ?? Values.ignoredApps }
    set { set(newValue, forKey: Keys.ignoredApps) }
  }

  public var ignoredPasteboardTypes: Set<String> {
    get { Set(array(forKey: Keys.ignoredPasteboardTypes) as? [String] ?? Values.ignoredPasteboardTypes) }
    set { set(Array(newValue), forKey: Keys.ignoredPasteboardTypes) }
  }

  public var ignoreRegexp: [String] {
    get { array(forKey: Keys.ignoreRegexp) as? [String] ?? Values.ignoreRegexp }
    set { set(newValue, forKey: Keys.ignoreRegexp) }
  }

  @objc dynamic public var imageMaxHeight: Int {
    get { integer(forKey: Keys.imageMaxHeight) }
    set { set(newValue, forKey: Keys.imageMaxHeight) }
  }

  public var lastReviewRequestedAt: Date {
    get {
      let int = Int64(integer(forKey: Keys.lastReviewRequestedAt))
      return Date(timeIntervalSince1970: TimeInterval(integerLiteral: int))
    }
    set { set(Int(newValue.timeIntervalSince1970), forKey: Keys.lastReviewRequestedAt) }
  }

  public var maxMenuItems: Int {
    get { integer(forKey: Keys.maxMenuItems) }
    set { set(newValue, forKey: Keys.maxMenuItems) }
  }

  @objc dynamic public var maxMenuItemLength: Int {
    get { integer(forKey: Keys.maxMenuItemLength) }
    set { set(newValue, forKey: Keys.maxMenuItemLength) }
  }

  @objc dynamic public var menuIcon: String {
    get { string(forKey: Keys.menuIcon) ?? Values.menuIcon }
    set { set(newValue, forKey: Keys.menuIcon) }
  }

  public var migrations: [String: Bool] {
    get { dictionary(forKey: Keys.migrations) as? [String: Bool] ?? Values.migrations }
    set { set(newValue, forKey: Keys.migrations) }
  }

  public var numberOfUsages: Int {
    get { integer(forKey: Keys.numberOfUsages) }
    set { set(newValue, forKey: Keys.numberOfUsages) }
  }

  @objc dynamic public var pasteByDefault: Bool {
    get { bool(forKey: Keys.pasteByDefault) }
    set { set(newValue, forKey: Keys.pasteByDefault) }
  }

  @objc dynamic public var pinTo: String {
    get { string(forKey: Keys.pinTo) ?? Values.pinTo }
    set { set(newValue, forKey: Keys.pinTo) }
  }

  public var popupPosition: String {
    get { string(forKey: Keys.popupPosition) ?? Values.popupPosition }
    set { set(newValue, forKey: Keys.popupPosition) }
  }

  public var popupScreen: Int {
    get { integer(forKey: Keys.popupScreen) }
    set { set(newValue, forKey: Keys.popupScreen) }
  }

  public var previewDelay: Int {
    get { integer(forKey: Keys.previewDelay) }
    set { set(newValue, forKey: Keys.previewDelay) }
  }

  @objc dynamic public var removeFormattingByDefault: Bool {
    get { bool(forKey: Keys.removeFormattingByDefault) }
    set { set(newValue, forKey: Keys.removeFormattingByDefault) }
  }

  public var searchMode: String {
    get { string(forKey: Keys.searchMode) ?? Values.searchMode }
    set { set(newValue, forKey: Keys.searchMode) }
  }

  @objc dynamic public var showInStatusBar: Bool {
    get { ProcessInfo.processInfo.arguments.contains("ui-testing") ? true : bool(forKey: Keys.showInStatusBar) }
    set { set(newValue, forKey: Keys.showInStatusBar) }
  }

  @objc dynamic public var showRecentCopyInMenuBar: Bool {
    get { bool(forKey: Keys.showRecentCopyInMenuBar) }
    set { set(newValue, forKey: Keys.showRecentCopyInMenuBar) }
  }

  @objc dynamic var showSpecialSymbols: Bool {
    get { bool(forKey: Keys.showSpecialSymbols) }
    set { set(newValue, forKey: Keys.showSpecialSymbols) }
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

  public var highlightMatches: String {
    get { string(forKey: Keys.highlightMatch) ?? Values.highlightMatch }
    set { set(newValue, forKey: Keys.highlightMatch) }
  }
}

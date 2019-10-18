import Foundation

extension UserDefaults {
  public struct Keys {
    static let fuzzySearch = "fuzzySearch"
    static let hotKey = "hotKey"
    static let ignoreEvents = "ignoreEvents"
    static let pasteByDefault = "pasteByDefault"
    static let saratovSeparator = "enableSaratovSeparator"
    static let size = "historySize"
    static let showSearch = "showSearch"

    static var showInStatusBar: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "showInStatusBarUITests" : "showInStatusBar"
    }

    static var storage: String {
      ProcessInfo.processInfo.arguments.contains("ui-testing") ? "historyUITests" : "history"
    }
  }

  public struct Values {
    static let hotKey = "command+shift+c"
    static let showInStatusBar = true
    static let size = 200
    static let storage: [String] = []
    static let showSearch = true
  }

  public var fuzzySearch: Bool {
    get { ProcessInfo.processInfo.arguments.contains("ui-testing") ? false : bool(forKey: Keys.fuzzySearch) }
    set { set(newValue, forKey: Keys.fuzzySearch) }
  }

  @objc dynamic public var hotKey: String {
    get { string(forKey: Keys.hotKey) ?? Values.hotKey }
    set { set(newValue, forKey: Keys.hotKey) }
  }

  public var ignoreEvents: Bool {
    get { bool(forKey: Keys.ignoreEvents) }
    set { set(newValue, forKey: Keys.ignoreEvents) }
  }

  @objc dynamic public var pasteByDefault: Bool {
    get { bool(forKey: Keys.pasteByDefault) }
    set { set(newValue, forKey: Keys.pasteByDefault) }
  }

  public var saratovSeparator: Bool {
    get { bool(forKey: Keys.saratovSeparator) }
    set { set(newValue, forKey: Keys.saratovSeparator) }
  }

  @objc dynamic public var showInStatusBar: Bool {
    get { ProcessInfo.processInfo.arguments.contains("ui-testing") ? true : bool(forKey: Keys.showInStatusBar) }
    set { set(newValue, forKey: Keys.showInStatusBar) }
  }

  public var size: Int {
    get { integer(forKey: Keys.size) }
    set { set(newValue, forKey: Keys.size) }
  }

  public var storage: [String] {
    get { array(forKey: Keys.storage) as? [String] ?? Values.storage }
    set { set(newValue, forKey: Keys.storage) }
  }

  public var showSearch: Bool {
    get { bool(forKey: Keys.showSearch) }
    set { set(newValue, forKey: Keys.showSearch) }
  }
}

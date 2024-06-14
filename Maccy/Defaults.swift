import AppKit
import Defaults

extension Defaults.Keys {
  static let avoidTakingFocus = Key<Bool>("avoidTakingFocus", default: false)
  static let clearOnQuit = Key<Bool>("clearOnQuit", default: false)
  static let clearSystemClipboard = Key<Bool>("clearSystemClipboard", default: false)
  static let clipboardCheckInterval = Key<Double>("clipboardCheckInterval", default: 0.5)
  static let enabledPasteboardTypes = Key<Set<NSPasteboard.PasteboardType>>(
    "enabledPasteboardTypes", default: [.fileURL, .png, .string, .tiff]
  )
  static let hideFooter = Key<Bool>("hideFooter", default: false)
  static let hideSearch = Key<Bool>("hideSearch", default: false)
  static let hideTitle = Key<Bool>("hideTitle", default: false)
  static let highlightMatch = Key<String>("highlightMatch", default: "bold")
  static let ignoreAllAppsExceptListed = Key<Bool>("ignoreAllAppsExceptListed", default: false)
  static let ignoreEvents = Key<Bool>("ignoreEvents", default: false)
  static let ignoreOnlyNextEvent = Key<Bool>("ignoreOnlyNextEvent", default: false)
  static let ignoreRegexp = Key<[String]>("ignoreRegexp", default: [])
  static let ignoredApps = Key<[String]>("ignoredApps", default: [])
  static let ignoredPasteboardTypes = Key<Set<String>>(
    "ignoredPasteboardTypes",
    default: [
      "Pasteboard generator type",
      "com.agilebits.onepassword",
      "com.typeit4me.clipping",
      "de.petermaurer.TransientPasteboardType"
    ])
  static let imageMaxHeight = Key<Int>("imageMaxHeight", default: 40)
  static let lastReviewRequestedAt = Key<Date>("lastReviewRequestedAt", default: Date.now)
  static let maxMenuItemLength = Key<Int>("maxMenuItemLength", default: 50)
  static let maxMenuItems = Key<Int>("maxMenuItems", default: 0)
  static let menuIcon = Key<String>("menuIcon", default: "maccy")
  static let migrations = Key<[String: Bool]>("migrations", default: [:])
  static let numberOfUsages = Key<Int>("numberOfUsages", default: 0)
  static let pasteByDefault = Key<Bool>("pasteByDefault", default: false)
  static let pinTo = Key<String>("pinTo", default: "top")
  static let popupPosition = Key<String>("popupPosition", default: "cursor")
  static let popupScreen = Key<Int>("popupScreen", default: 0)
  static let previewDelay = Key<Int>("previewDelay", default: 1500)
  static let removeFormattingByDefault = Key<Bool>("removeFormattingByDefault", default: false)
  static let searchMode = Key<Search.Mode>("searchMode", default: .exact)
  static let showInStatusBar = Key<Bool>("showInStatusBar", default: true)
  static let showRecentCopyInMenuBar = Key<Bool>("showRecentCopyInMenuBar", default: false)
  static let showSpecialSymbols = Key<Bool>("showSpecialSymbols", default: true)
  static let size = Key<Int>("historySize", default: 200)
  static let sortBy = Key<Sorter.By>("sortBy", default: .lastCopiedAt)
  static let suppressClearAlert = Key<Bool>("suppressClearAlert", default: false)
}

import AppKit
import Defaults

/// Groups pasteboard types that Maccy can store into file, image, and text categories.
struct StorageType {
  static let files = StorageType(types: [.fileURL])
  static let images = StorageType(types: [.heic, .jpeg, .png, .tiff])
  static let text = StorageType(types: [.html, .rtf, .string])
  static let all = StorageType(types: files.types + images.types + text.types)

  var types: [NSPasteboard.PasteboardType]
}

/// Bounds for the configurable clipboard content size limit, in megabytes.
enum ClipboardContentSizeLimit {
  static let minMegabytes = 1
  static let defaultMegabytes = 10
  static let maxMegabytes = 1024
  static let bytesPerMegabyte = 1_024 * 1_024
}

extension Defaults.Keys {
  static let clearOnQuit = Key<Bool>("clearOnQuit", default: false)
  static let clearSystemClipboard = Key<Bool>("clearSystemClipboard", default: false)
  static let clipboardCheckInterval = Key<Double>("clipboardCheckInterval", default: 0.5)
  static let maxClipboardContentSize = Key<Int>(
    "maxClipboardContentSize",
    default: ClipboardContentSizeLimit.defaultMegabytes
  )
  /// Max rows visible in the popup before scrolling.
  ///
  /// The window height is otherwise content-driven; this caps it so long histories
  /// don't overflow. The default of 36 keeps the shipped ~800px look
  /// (see `Popup.resize` guardrail).
  static let maxVisibleItems = Key<Int>("maxVisibleItems", default: 36)
  static let enabledPasteboardTypes = Key<Set<NSPasteboard.PasteboardType>>(
    "enabledPasteboardTypes", default: Set(StorageType.all.types)
  )
  static let highlightMatch = Key<HighlightMatch>("highlightMatch", default: .bold)
  static let ignoreAllAppsExceptListed = Key<Bool>("ignoreAllAppsExceptListed", default: false)
  static let ignoreEvents = Key<Bool>("ignoreEvents", default: false)
  static let ignoreOnlyNextEvent = Key<Bool>("ignoreOnlyNextEvent", default: false)
  static let ignoreRegexp = Key<[String]>("ignoreRegexp", default: [])
  static let ignoredApps = Key<[String]>("ignoredApps", default: [])
  static let ignoredPasteboardTypes = Key<Set<String>>(
    "ignoredPasteboardTypes",
    default: Set([
      "Pasteboard generator type",
      "com.agilebits.onepassword",
      "com.typeit4me.clipping",
      "de.petermaurer.TransientPasteboardType",
      "net.antelle.keeweb"
    ])
  )
  static let imageMaxHeight = Key<Int>("imageMaxHeight", default: 40)
  /// Longest-side cap (px) for a decoded preview image.
  ///
  /// `0` means no cap; the image decodes at screen resolution — visually "original"
  /// in the pane, without a huge bitmap. See `HistoryItemDecorator.previewImageSize`.
  static let imageMaxPreviewPixels = Key<Int>("imageMaxPreviewPixels", default: 800)
  /// Max chars of text shown in a preview. `0` means full text (no truncation).
  static let textPreviewLimit = Key<Int>("textPreviewLimit", default: 3000)
  static let menuIcon = Key<MenuIcon>("menuIcon", default: .maccy)
  static let migrations = Key<[String: Bool]>("migrations", default: [:])
  static let pasteByDefault = Key<Bool>("pasteByDefault", default: false)
  static let pinTo = Key<PinsPosition>("pinTo", default: .top)
  static let popupPosition = Key<PopupPosition>("popupPosition", default: .cursor)
  static let popupScreen = Key<Int>("popupScreen", default: 0)
  /// Delay (ms) before the preview follows the lead selection.
  ///
  /// `0` (or below ~100) gives instant follow; higher values enable dwell-to-peek.
  /// The retarget timer's cancel-on-change acts as the debounce, so one knob covers
  /// both modes. See `SlideoutController`.
  static let previewDelay = Key<Int>("previewDelay", default: 200)
  static let removeFormattingByDefault = Key<Bool>("removeFormattingByDefault", default: false)
  static let searchMode = Key<Search.Mode>("searchMode", default: .exact)
  static let showFooter = Key<Bool>("showFooter", default: true)
  static let showInStatusBar = Key<Bool>("showInStatusBar", default: true)
  static let showRecentCopyInMenuBar = Key<Bool>("showRecentCopyInMenuBar", default: false)
  static let showSearch = Key<Bool>("showSearch", default: true)
  static let searchVisibility = Key<SearchVisibility>("searchVisibility", default: .always)
  static let showSpecialSymbols = Key<Bool>("showSpecialSymbols", default: true)
  static let showTitle = Key<Bool>("showTitle", default: true)
  static let size = Key<Int>("historySize", default: 200)
  static let sortBy = Key<Sorter.By>("sortBy", default: .lastCopiedAt)
  static let suppressClearAlert = Key<Bool>("suppressClearAlert", default: false)
  static let windowSize = Key<NSSize>("windowSize", default: NSSize(width: 450, height: 800))
  static let windowPosition = Key<NSPoint>("windowPosition", default: NSPoint(x: 0.5, y: 0.8))
  static let showApplicationIcons = Key<Bool>("showApplicationIcons", default: false)
  static let previewWidth = Key<CGFloat>("previewWidth", default: 400)
  /// Max characters of an item's body that the search actor keeps and scans.
  /// Beyond this window a match is not found (degrades to title search). The
  /// stored value is clamped to `TextLimits.searchBodyMin...Max` at read time,
  /// and `History` rebuilds the corpus when this changes.
  static let searchBodyLimit = Key<Int>("searchBodyLimit", default: TextLimits.searchBody)
}

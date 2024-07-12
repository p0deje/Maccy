import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString? = nil

  var isVisible: Bool = true
  var isSelected: Bool = false {
    didSet {
      if isSelected {
        throttler.throttle {
          self.showPreview = true
        }
      } else {
        throttler.cancel()
        self.showPreview = false
      }
    }
  }
  var shortcuts: [KeyShortcut] = []
  var showPreview: Bool = false

  var application: String? {
    if item.universalClipboard {
      return "iCloud"
    }

    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }

    return url.deletingPathExtension().lastPathComponent
  }

  var image: NSImage? { item.image }
  var text: String { item.previewableText }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(title)
  }

  private(set) var item: HistoryItem
  private var throttler: Throttler

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title

    // TODO: Use 0.2 delay after first preview is shown.
    self.throttler = Throttler(minimumDelay: Double(Defaults[.previewDelay]) / 1000)
  }
  
  func highlight(_ query: String) {
    guard !query.isEmpty, !title.isEmpty else {
      self.attributedTitle = nil
      return
    }

    var attributedString = AttributedString(title)
    for range in attributedString.ranges(of: query, options: .caseInsensitive) {
      switch Defaults[.highlightMatch] {
      case .italic:
        attributedString[range].font = .italic(.body)()
      case .underline:
        attributedString[range].underlineStyle = .single
      default:
        attributedString[range].font = .bold(.body)()
      }
    }

    self.attributedTitle = attributedString
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
      shortcuts = []
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
      shortcuts = KeyShortcut.create(character: pin)
    }
  }
}

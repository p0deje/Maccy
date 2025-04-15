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

  static var previewThrottler = Throttler(minimumDelay: Double(Defaults[.previewDelay]) / 1000)
  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var isSelected: Bool = false {
    didSet {
      if isSelected {
        Self.previewThrottler.throttle {
          Self.previewThrottler.minimumDelay = 0.2
          self.showPreview = true
        }
      } else {
        Self.previewThrottler.cancel()
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

  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage
  var isSecret: Bool { item.secret }

  // 10k characters seems to be more than enough on large displays
  var text: String {
    let originalText = item.previewableText.shortened(to: 10_000)
    if item.secret && originalText.count > 2 {
      let first = String(originalText.prefix(1))
      let last = String(originalText.suffix(1))
      let maskLength = min(originalText.count - 2, 10) // Use at most 10 asterisks
      let mask = String(repeating: "*", count: maskLength)
      return first + mask + last
    }
    return originalText
  }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    if item.secret && item.title.count > 2 {
      let first = String(item.title.prefix(1))
      let last = String(item.title.suffix(1))
      let maskLength = min(item.title.count - 2, 10) // Use at most 10 asterisks
      let mask = String(repeating: "*", count: maskLength)
      self.title = first + mask + last
    } else {
      self.title = item.title
    }

    synchronizeItemPin()
    synchronizeItemTitle()
    Task {
      await sizeImages()
    }
  }

  @MainActor
  func sizeImages() {
    guard let image = item.image else {
      return
    }

    previewImage = image.resized(to: HistoryItemDecorator.previewImageSize)
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !title.isEmpty else {
      attributedTitle = nil
      return
    }

    var attributedString = AttributedString(title.shortened(to: 500))
    for range in ranges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
    }
  }

  @MainActor
  func toggleSecret() {
    item.secret.toggle()
    // Update the title display immediately
    if item.secret && item.title.count > 2 {
      let first = String(item.title.prefix(1))
      let last = String(item.title.suffix(1))
      let maskLength = min(item.title.count - 2, 10)
      let mask = String(repeating: "*", count: maskLength)
      title = first + mask + last
    } else {
      title = item.title
    }
  }

  private func synchronizeItemPin() {
    _ = withObservationTracking {
      item.pin
    } onChange: {
      DispatchQueue.main.async {
        if let pin = self.item.pin {
          self.shortcuts = KeyShortcut.create(character: pin)
        }
        self.synchronizeItemPin()
      }
    }
  }

  private func synchronizeItemTitle() {
    _ = withObservationTracking {
      item.title
    } onChange: {
      DispatchQueue.main.async {
        if self.item.secret && self.item.title.count > 2 {
          let first = String(self.item.title.prefix(1))
          let last = String(self.item.title.suffix(1))
          let maskLength = min(self.item.title.count - 2, 10) // Use at most 10 asterisks
          let mask = String(repeating: "*", count: maskLength)
          self.title = first + mask + last
        } else {
          self.title = self.item.title
        }
        self.synchronizeItemTitle()
      }
    }
  }
}

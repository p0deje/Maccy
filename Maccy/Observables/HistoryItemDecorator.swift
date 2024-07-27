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
  var attributedTitle: AttributedString? = nil

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

  var previewImage: NSImage? = nil
  var thumbnailImage: NSImage? = nil

  var text: String { item.previewableText }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(title)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title

    Task {
      await observeItemPin()
    }
    Task {
      await observeItemTitle()
    }
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
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
    }
  }

  private func observeItemPin() async {
    let pinSet = AsyncStream {
      await withCheckedContinuation { continuation in
        let _ = withObservationTracking {
          self.item.pin
        } onChange: {
          continuation.resume()
        }
      }

      return self.item.pin
    }

    for await pin in pinSet {
      self.shortcuts = KeyShortcut.create(character: pin)
    }
  }

  private func observeItemTitle() async {
    let titleSet = AsyncStream {
      await withCheckedContinuation { continuation in
        let _ = withObservationTracking {
          self.item.title
        } onChange: {
          continuation.resume()
        }
      }

      return self.item.title
    }

    for await title in titleSet {
      self.title = title
    }
  }
}

import Cocoa

class HistoryMenuItem: NSMenuItem {
  typealias Callback = (HistoryMenuItem) -> Void

  public var isPinned = false
  public var item: HistoryItem!

  private let showMaxLength = 50
  private let imageMaxWidth: CGFloat = 340.0
  private let showImagesForTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

  private var onSelected: [Callback] = []

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  init(item: HistoryItem, onSelected: @escaping Callback) {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.imageMaxHeight: UserDefaults.Values.imageMaxHeight])

    super.init(title: "", action: #selector(onSelect(_:)), keyEquivalent: "")

    self.item = item
    self.onSelected = [onSelected]
    self.onStateImage = NSImage(named: "PinImage")
    self.target = self

    if showImagesForTypes.contains(item.type) {
      loadImage(item)
    } else {
      loadString(item)
    }

    if let itemPin = item.pin {
      pin(itemPin)
    }
  }

  @objc
  func onSelect(_ sender: NSMenuItem) {
    for hook in onSelected {
      hook(self)
    }
  }

  func pin(_ pin: String) {
    item.pin = pin
    self.isPinned = true
    self.keyEquivalent = pin
    self.state = .on
  }

  func unpin() {
    item.pin = nil
    self.isPinned = false
    self.keyEquivalent = ""
    self.state = .off
  }

  private func loadImage(_ item: HistoryItem) {
    if let image = NSImage(data: item.value) {
      if image.size.width > imageMaxWidth {
        image.size.height = image.size.height / (image.size.width / imageMaxWidth)
        image.size.width = imageMaxWidth
      }

      let imageMaxHeight = CGFloat(UserDefaults.standard.imageMaxHeight)
      if image.size.height > imageMaxHeight {
        image.size.width = image.size.width / (image.size.height / imageMaxHeight)
        image.size.height = imageMaxHeight
      }

      self.image = image
      self.toolTip = """
                     Press ⌥+⌫ to delete.
                     Press ⌥+p to (un)pin.
                     """
    }
  }

  private func loadString(_ item: HistoryItem) {
    if let title = String(data: item.value, encoding: .utf8) {
      self.title = humanizedTitle(title)
      self.image = ColorImage.from(title)
      self.toolTip = """
                     \(title)\n \n
                     Press ⌥+⌫ to delete.
                     Press ⌥+p to (un)pin.
                     """
    }
  }

  private func humanizedTitle(_ title: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedTitle.count > showMaxLength {
      let index = trimmedTitle.index(trimmedTitle.startIndex, offsetBy: showMaxLength)
      return "\(trimmedTitle[...index])..."
    } else {
      return trimmedTitle
    }
  }
}

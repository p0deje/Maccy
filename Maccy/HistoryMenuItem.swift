import Cocoa

class HistoryMenuItem: NSMenuItem {
  typealias Callback = (HistoryMenuItem) -> Void

  public var isPinned = false
  public var item: HistoryItem!

  private let showMaxLength = 50
  private var onSelected: [Callback] = []

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  init(item: HistoryItem, onSelected: @escaping Callback) {
    super.init(title: item.value, action: #selector(onSelect(_:)), keyEquivalent: "")
    self.item = item
    self.onSelected = [onSelected]
    self.onStateImage = NSImage(named: "PinImage")
    self.target = self
    self.title = humanizedTitle(title)
    self.image = ColorImage.from(item.value)
    self.toolTip = """
                   \(item.value)\n \n
                   Press ⌥+⌫ to delete.
                   Press ⌥+p to (un)pin.
                   """

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

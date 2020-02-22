import Cocoa

class HistoryMenuItem: NSMenuItem {
  typealias Callback = (HistoryMenuItem) -> Void

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
    self.target = self
    self.title = humanizedTitle(title)
    self.image = ColorImage.from(item.value)
    self.toolTip = """
                   \(item.value)\n \n
                   Press ⌥+⌫ to delete.
                   """
  }

  @objc
  func onSelect(_ sender: NSMenuItem) {
    for hook in onSelected {
      hook(self)
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

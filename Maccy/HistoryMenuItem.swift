import Cocoa

class HistoryMenuItem: NSMenuItem {
  typealias Callback = (HistoryMenuItem) -> Void

  public var isPinned = false
  public var item: HistoryItem!
  public var value = ""

  private let showMaxLength = 50
  private let tooltipMaxLength = 5_000
  private let imageMaxWidth: CGFloat = 340.0

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

    if isImage(item) {
      loadImage(item)
    } else if isFile(item) {
      loadString(item, from: .fileURL)
    } else {
      loadString(item, from: .string)
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

  private func isImage(_ item: HistoryItem) -> Bool {
    return contentData(item, [.tiff, .png]) != nil
  }

  private func isFile(_ item: HistoryItem) -> Bool {
    return contentData(item, [.fileURL]) != nil
  }

  private func isString(_ item: HistoryItem) -> Bool {
    return contentData(item, [.string]) != nil
  }

  private func loadImage(_ item: HistoryItem) {
    if let contentData = contentData(item, [.tiff, .png]) {
      if let image = NSImage(data: contentData) {
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
        self.toolTip = defaultTooltip(item)
      }
    }
  }

  private func loadString(_ item: HistoryItem, from: NSPasteboard.PasteboardType) {
    if let contentData = contentData(item, [from]) {
      if let string = String(data: contentData, encoding: .utf8) {
        self.value = string
        self.title = trimmedString(string.trimmingCharacters(in: .whitespacesAndNewlines),
                                  showMaxLength)
        self.image = ColorImage.from(title)
        self.toolTip = """
        \(trimmedString(string, tooltipMaxLength))
        \n \n\n
        \(defaultTooltip(item))
        """
      }
    }
  }

  private func contentData(_ item: HistoryItem, _ types: [NSPasteboard.PasteboardType]) -> Data? {
    let contents = item.getContents()
    let content = contents.first(where: { content in
      return types.contains(NSPasteboard.PasteboardType(content.type))
    })

    return content?.value
  }

  private func trimmedString(_ string: String, _ maxLength: Int) -> String {
    guard string.count > maxLength else {
      return string
    }

    let halfMaxLength: Int = maxLength / 2
    let indexStart = string.index(string.startIndex, offsetBy: halfMaxLength - 1)
    let indexEnd = string.index(string.endIndex, offsetBy: -halfMaxLength)
    return "\(string[...indexStart])...\(string[indexEnd...])"
  }

  private func defaultTooltip(_ item: HistoryItem) -> String {
    return """
    \(NSLocalizedString("first_copy_time_tooltip", comment: "")): \(formatDate(item.firstCopiedAt))
    \(NSLocalizedString("last_copy_time_tooltip", comment: "")): \(formatDate(item.lastCopiedAt))
    \(NSLocalizedString("number_of_copies_tooltip", comment: "")): \(item.numberOfCopies)
    \n \n\n
    \(NSLocalizedString("history_item_tooltip", comment: ""))
    """
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, H:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
  }
}

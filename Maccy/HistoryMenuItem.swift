import Cocoa

class HistoryMenuItem: NSMenuItem {
  public var isPinned = false
  public var item: HistoryItem!
  public var value = ""

  internal var clipboard: Clipboard!

  private let tooltipMaxLength = 5_000
  private let imageMaxWidth: CGFloat = 340.0
  private let imagePasteboardTypes = [.tiff, .png, NSPasteboard.PasteboardType(rawValue: "public.jpeg")]

  private let highlightFont: NSFont = {
    if #available(macOS 11, *) {
      return NSFont.boldSystemFont(ofSize: 13)
    } else {
      return NSFont.boldSystemFont(ofSize: 14)
    }
  }()

  private var editPinObserver: NSKeyValueObservation?
  private var editTitleObserver: NSKeyValueObservation?

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  init(item: HistoryItem, clipboard: Clipboard) {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.imageMaxHeight: UserDefaults.Values.imageMaxHeight])

    super.init(title: "", action: #selector(onSelect(_:)), keyEquivalent: "")

    self.clipboard = clipboard
    self.item = item
    self.onStateImage = NSImage(named: "PinImage")
    self.target = self

    if isImage(item) {
      loadImage(item)
    } else if isFile(item) {
      loadFile(item)
    } else if isRTF(item) {
      loadRTF(item)
    } else if isHTML(item) {
      loadHTML(item)
    } else {
      loadString(item, from: .string)
    }

    if let itemPin = item.pin {
      pin(itemPin)
    }

    alternate()

    editPinObserver = item.observe(\.pin, options: .new, changeHandler: { item, _ in
      self.keyEquivalent = item.pin ?? ""
    })
    editTitleObserver = item.observe(\.title, options: .new, changeHandler: { item, _ in
      self.title = item.title
    })
  }

  deinit {
    editPinObserver?.invalidate()
    editTitleObserver?.invalidate()
  }

  @objc
  func onSelect(_ sender: NSMenuItem) {
    select()
  }

  func select() {
    // Override in children.
  }

  func alternate() {
    // Override in children.
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

  func resizeImage() {
    if !isImage(item) {
      return
    }

    loadImage(item)
  }

  func highlight(_ ranges: [ClosedRange<Int>]) {
    guard !ranges.isEmpty else {
      self.attributedTitle = nil
      return
    }

    let attributedTitle = NSMutableAttributedString(string: title)
    for range in ranges {
      let rangeLength = range.upperBound - range.lowerBound + 1
      let highlightRange = NSRange(location: range.lowerBound, length: rangeLength)

      attributedTitle.addAttribute(.font, value: highlightFont, range: highlightRange)
    }

    self.attributedTitle = attributedTitle
  }

  private func isImage(_ item: HistoryItem) -> Bool {
    return contentData(item, imagePasteboardTypes) != nil
  }

  private func isFile(_ item: HistoryItem) -> Bool {
    return contentData(item, [.fileURL]) != nil
  }

  private func isRTF(_ item: HistoryItem) -> Bool {
    return contentData(item, [.rtf]) != nil
  }

  private func isHTML(_ item: HistoryItem) -> Bool {
    return contentData(item, [.html]) != nil
  }

  private func isString(_ item: HistoryItem) -> Bool {
    return contentData(item, [.string]) != nil
  }

  private func loadImage(_ item: HistoryItem) {
    if let contentData = contentData(item, imagePasteboardTypes) {
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

        // Assign "empty" title to the image (but it can't be empty string).
        // This is required for onStateImage to render correctly when item is pinned.
        // Otherwise, it's not rendered with the error:
        //
        // GetEventParameter(inEvent, kEventParamMenuTextBaseline, typeCGFloat, NULL, sizeof baseline, NULL, &baseline)
        // returned error -9870 on line 2078 in -[NSCarbonMenuImpl _carbonDrawStateImageForMenuItem:withEvent:]
        self.title = " "
      }
    }
  }

  private func loadFile(_ item: HistoryItem) {
    if let fileURLData = contentData(item, [.fileURL]) {
      if let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil, isAbsolute: true) {
        if let string = fileURL.absoluteString.removingPercentEncoding {
          self.value = string
          self.title = item.title
          self.image = ColorImage.from(title)
          self.toolTip = """
          \(string.shortened(to: tooltipMaxLength))

          \(defaultTooltip(item))
          """
        }
      }
    }
  }

  private func loadRTF(_ item: HistoryItem) {
    if let contentData = contentData(item, [.rtf]) {
      if let string = NSAttributedString(rtf: contentData, documentAttributes: nil)?.string {
        self.value = string
        self.title = item.title
        self.image = ColorImage.from(title)
        self.toolTip = """
        \(string.shortened(to: tooltipMaxLength))

        \(defaultTooltip(item))
        """
      }
    }
  }

  private func loadHTML(_ item: HistoryItem) {
    if let contentData = contentData(item, [.html]) {
      if let string = NSAttributedString(html: contentData, documentAttributes: nil)?.string {
        self.value = string
        self.title = item.title
        self.image = ColorImage.from(title)
        self.toolTip = """
        \(string.shortened(to: tooltipMaxLength))

        \(defaultTooltip(item))
        """
      }
    }
  }
  private func loadString(_ item: HistoryItem, from: NSPasteboard.PasteboardType) {
    if let contentData = contentData(item, [from]) {
      if let string = String(data: contentData, encoding: .utf8) {
        self.value = string
        self.title = item.title
        self.image = ColorImage.from(title)
        self.toolTip = """
        \(string.shortened(to: tooltipMaxLength))

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

  private func defaultTooltip(_ item: HistoryItem) -> String {
    var lines: [String] = []
    if let bundle = item.application, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
      lines.append(
        [
          NSLocalizedString("copy_application_tooltip", comment: ""),
          url.deletingPathExtension().lastPathComponent
        ].joined(separator: ": ")
      )
    }
    lines.append(
      [
        NSLocalizedString("first_copy_time_tooltip", comment: ""),
        formatDate(item.firstCopiedAt)
      ].joined(separator: ": ")
    )
    lines.append(
      [
        NSLocalizedString("last_copy_time_tooltip", comment: ""),
        formatDate(item.lastCopiedAt)
      ].joined(separator: ": ")
    )
    lines.append(
      [
        NSLocalizedString("number_of_copies_tooltip", comment: ""),
        String(item.numberOfCopies)
      ].joined(separator: ": ")
    )
    lines.append("")
    lines.append(NSLocalizedString("history_item_tooltip", comment: ""))

    return lines.joined(separator: "\n")
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, H:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
  }
}

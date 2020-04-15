import Cocoa

class HistoryMenuItem: NSMenuItem {
  typealias Callback = (HistoryMenuItem) -> Void

  public var isPinned = false
  public var item: HistoryItem!

  private let showMaxLength = 50
  private let imageMaxWidth: CGFloat = 340.0
  private let showImagesForTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .fileURL]

  private var onSelected: [Callback] = []
  private var shouldDisplayTitle: Bool = false

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

    if showImagesForTypes.contains(where: item.typesWithData.keys.contains) {
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

  private func getImageFromItem(_ item: HistoryItem) -> NSImage? {
    if let data = (item.typesWithData[.tiff] ?? item.typesWithData[.png]) {
      self.shouldDisplayTitle = false
      return NSImage(data: data)
    }

    var possibleImage: NSImage?

    if let fileURL = item.typesWithData[.fileURL], let url = URL(dataRepresentation: fileURL, relativeTo: nil) {
      possibleImage = NSImage(contentsOf: url)
      self.shouldDisplayTitle = false
    }

    if possibleImage == nil, let appleIcon = item.typesWithData[NSPasteboard.PasteboardType("com.apple.icns")] {
      possibleImage = NSImage(data: appleIcon)
      self.shouldDisplayTitle = true
    }

    if possibleImage == nil {
      possibleImage = NSImage(named: "PinImage")
      self.shouldDisplayTitle = true
    }

    return possibleImage
  }

  private func loadImage(_ item: HistoryItem) {
    guard let image: NSImage = getImageFromItem(item) else {
      return loadString(item)
    }

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

    if self.shouldSetTitle && item.typesWithData[.fileURL] != nil {
      let fileURL = item.typesWithData[.fileURL]!
      if let url = URL(dataRepresentation: fileURL, relativeTo: nil) {
        let pathInfo = humanizedPath(url)
        self.title = pathInfo.title
        if let tooltipDir = pathInfo.tooltip {
          self.toolTip = """
                         File located in \(tooltipDir)\n \n
                         Press ⌥+⌫ to delete.
                         Press ⌥+p to (un)pin.
                         """
        }
      }
    }
  }

  private func loadString(_ item: HistoryItem) {
    if let title = String(data: (item.typesWithData[.string] ?? item.typesWithData.first!.value)!, encoding: .utf8) {
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

  private struct HumanizedPathInfo {
    var title: String
    var tooltip: String?
  }

  private func humanizedPath(_ url: URL) -> HumanizedPathInfo {
    if url.path.count > showMaxLength {
      let shortUrl = url.pathComponents.dropFirst().dropLast(1).reduce(
          into: URL(fileURLWithPath: url.pathComponents.first!)
      ) { url, dir in
        let shortDir = String(dir[...dir.index(dir.startIndex, offsetBy: 0)])
        url.appendPathComponent(shortDir, isDirectory: true)
      }.appendingPathComponent(url.lastPathComponent)
      let fullDir = url.deletingLastPathComponent().path

      return HumanizedPathInfo(title: shortUrl.path, tooltip: fullDir)
    } else {
      return HumanizedPathInfo(title: url.path)
    }
  }
}

import Cocoa
import CoreData
import Sauce

@objc(HistoryItem)
class HistoryItem: NSManagedObject {
  static var availablePins: Set<String> {
    var keys = Set([
      "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
      "n", "o", "p", "r", "s", "t", "u", "v", "w", "x", "y", "z" // "q" reserved for quit
    ])

    if let deleteKey = KeyChord.deleteKey {
      keys.remove(Sauce.shared.character(for: Int(deleteKey.QWERTYKeyCode), cocoaModifiers: []) ?? "")
    }
    if let pinKey = KeyChord.pinKey {
      keys.remove(Sauce.shared.character(for: Int(pinKey.QWERTYKeyCode), cocoaModifiers: []) ?? "")
    }

    return keys
  }

  static let sortByFirstCopiedAt = NSSortDescriptor(key: #keyPath(HistoryItem.firstCopiedAt), ascending: false)

  static var all: [HistoryItem] {
    let fetchRequest = NSFetchRequest<HistoryItem>(entityName: "HistoryItem")
    fetchRequest.sortDescriptors = [HistoryItem.sortByFirstCopiedAt]
    do {
      return try CoreDataManager.shared.viewContext.fetch(fetchRequest)
    } catch {
      return []
    }
  }

  static var pinned: [HistoryItem] {
    all.filter({ $0.pin != nil })
  }

  static var unpinned: [HistoryItem] {
    all.filter({ $0.pin == nil })
  }

  static var randomAvailablePin: String {
    let assignedPins = Set(all.compactMap({ $0.pin }))
    return availablePins.subtracting(assignedPins).randomElement() ?? ""
  }

  @NSManaged public var application: String?
  @NSManaged public var contents: NSSet?
  @NSManaged public var firstCopiedAt: Date!
  @NSManaged public var lastCopiedAt: Date!
  @NSManaged public var numberOfCopies: Int
  @NSManaged public var pin: String?
  @NSManaged public var title: String?

  var fileURL: URL? {
    guard let data = contentData(filePasteboardTypes) else {
      return nil
    }
    guard !univeralClipboardText else {
      return nil
    }

    return URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
  }

  var htmlData: Data? { contentData(htmlPasteboardTypes) }
  var html: NSAttributedString? {
    guard let data = htmlData else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  var image: NSImage? {
    var data: Data?
    data = contentData(imagePasteboardTypes)
    if data == nil, univeralClipboardImage, let url = fileURL {
      data = try? Data(contentsOf: url)
    }

    guard let data = data else {
      return nil
    }

    return NSImage(data: data)
  }

  var rtfData: Data? { contentData(rtfPasteboardTypes) }
  var rtf: NSAttributedString? {
    guard let data = rtfData else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }

  var text: String? {
    guard let data = contentData(textPasteboardTypes) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  var modified: Int? {
    guard let data = contentData([.modified]),
          let modified = String(data: data, encoding: .utf8) else {
      return nil
    }

    return Int(modified)
  }

  var fromMaccy: Bool { contentData([.fromMaccy]) != nil }
  var universalClipboard: Bool { contentData([.universalClipboard]) != nil }

  private let filePasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL]
  private let htmlPasteboardTypes: [NSPasteboard.PasteboardType] = [.html]
  private let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [.tiff, .png, .jpeg]
  private let rtfPasteboardTypes: [NSPasteboard.PasteboardType] = [.rtf]
  private let textPasteboardTypes: [NSPasteboard.PasteboardType] = [.string]

  private var univeralClipboardImage: Bool { universalClipboard && fileURL?.pathExtension == "jpeg" }
  private var univeralClipboardText: Bool {
     universalClipboard &&
      contentData(htmlPasteboardTypes + imagePasteboardTypes + rtfPasteboardTypes + textPasteboardTypes) != nil
  }

  static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.getContents().count == rhs.getContents().count && lhs.supersedes(rhs)
  }

  convenience init(contents: [HistoryItemContent], application: String? = nil) {
    let entity = NSEntityDescription.entity(forEntityName: "HistoryItem",
                                            in: CoreDataManager.shared.viewContext)!
    self.init(entity: entity, insertInto: CoreDataManager.shared.viewContext)

    self.application = application
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1
    contents.forEach(addToContents(_:))

    self.title = generateTitle(contents)
  }

  override func validateValue(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>, forKey key: String) throws {
    try super.validateValue(value, forKey: key)
    if key == "pin", let pin = value.pointee as? String {
      try validatePin(pin)
    }
  }

  @objc(addContentsObject:)
  @NSManaged public func addToContents(_ value: HistoryItemContent)

  func getContents() -> [HistoryItemContent] {
    return (contents?.allObjects as? [HistoryItemContent]) ?? []
  }

  func supersedes(_ item: HistoryItem) -> Bool {
    return item.getContents()
      .filter { content in
        ![
          NSPasteboard.PasteboardType.modified.rawValue,
          NSPasteboard.PasteboardType.fromMaccy.rawValue
        ].contains(content.type)
      }
      .allSatisfy { content in
        getContents().contains(where: { $0 == content})
      }
  }

  func generateTitle(_ contents: [HistoryItemContent]) -> String {
    var title = ""

    guard image == nil else {
      return title
    }

    if let fileURL = fileURL {
      title = fileURL.absoluteString.removingPercentEncoding ?? ""
    } else if let text = text {
      title = text
    } else if title.isEmpty, let rtf = rtf {
      title = rtf.string
    } else if title.isEmpty, let html = html {
      title = html.string
    }

    return title
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: "⏎")
      .shortened(to: UserDefaults.standard.maxMenuItemLength)
  }

  private func validatePin(_ pin: String) throws {
    for item in HistoryItem.all {
      if let existingPin = item.pin, !pin.isEmpty, existingPin == pin, item != self {
        throw NSError(
          domain: "keyUsed",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("key_used_error", comment: "")])
      }
    }
  }

  private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
    let contents = getContents()
    let content = contents.first(where: { content in
      return types.contains(NSPasteboard.PasteboardType(content.type))
    })

    return content?.value
  }
}

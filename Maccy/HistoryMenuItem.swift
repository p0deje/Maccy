import Cocoa

class HistoryMenuItem: NSMenuItem {
  private let showMaxLength = 50

  private var fullTitle: String?
  private var clipboard: Clipboard?

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  init(title: String, clipboard: Clipboard) {
    super.init(title: title, action: #selector(copy(_:)), keyEquivalent: "")
    self.target = self
    self.fullTitle = title
    self.clipboard = clipboard
    self.title = humanizedTitle(title)
  }

  private func humanizedTitle(_ title: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    if trimmedTitle.count > showMaxLength {
      let index = trimmedTitle.index(trimmedTitle.startIndex, offsetBy: showMaxLength)
      return "\(trimmedTitle[...index])..."
    } else {
      return trimmedTitle
    }
  }

  @objc
  func copy(_ sender: NSMenuItem) {
    clipboard!.copy(self.fullTitle!)
  }
}

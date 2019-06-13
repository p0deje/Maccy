import Cocoa

class HistoryMenuItem: NSMenuItem {
  private let showMaxLength = 50

  public var fullTitle: String?

  typealias callback = (HistoryMenuItem) -> Void

  private var onSelected: [callback]

  required init(coder: NSCoder) {
    self.onSelected=[]
    super.init(coder: coder)
  }


  init(title: String, hotKey:String,onSelected:@escaping (_ item:HistoryMenuItem)->Void){
    self.onSelected=[onSelected]
    super.init(title: title, action: #selector(onSelect(_:)), keyEquivalent: hotKey)
    self.keyEquivalentModifierMask=[]
    self.target = self

    self.fullTitle = title
    self.title = humanizedTitle(title)
  }

  @objc
  func onSelect(_ sender: NSMenuItem) {
    for hook in onSelected{
      hook(self)
    }
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

}

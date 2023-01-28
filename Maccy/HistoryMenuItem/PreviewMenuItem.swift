import AppKit

extension HistoryMenuItem {
  class PreviewMenuItem: NSMenuItem {
    private let initialSize = NSSize(width: CGFloat(Menu.menuWidth), height: 0.1)

    init() {
      super.init(title: "", action: nil, keyEquivalent: "")
      view = NSView(frame: NSRect(origin: .zero, size: initialSize))
      isHidden = true
    }

    required init(coder: NSCoder) {
      super.init(coder: coder)
    }
  }
}

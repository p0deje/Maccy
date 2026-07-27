import AppKit

/// Enables resizing on the Settings package window.
final class ResizableSettingsWindowDelegate: NSObject, NSWindowDelegate {
  static let shared = ResizableSettingsWindowDelegate()

  private static let defaultContentSize = NSSize(width: 750, height: 640)
  private static let minimumContentSize = NSSize(width: 520, height: 400)

  private var hasAppliedInitialSize = false

  func configure(_ window: NSWindow) {
    window.styleMask.insert([.resizable, .miniaturizable])
    window.minSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: Self.minimumContentSize)).size
    window.delegate = self

    guard !hasAppliedInitialSize else { return }
    hasAppliedInitialSize = true

    let current = window.contentLayoutRect.size
    if current.width < 600 || current.height < 480 {
      applyContentSize(Self.defaultContentSize, to: window)
    }
  }

  private func applyContentSize(_ contentSize: NSSize, to window: NSWindow) {
    var frame = window.frame
    let newFrameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
    frame.origin.y += frame.height - newFrameSize.height
    frame.size = newFrameSize
    window.setFrame(frame, display: true)
  }
}

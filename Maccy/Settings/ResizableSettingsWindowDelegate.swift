import AppKit

/// Enables resizing on the Settings package window. Preserves user-enlarged dimensions when
/// switching tabs, but still allows the window to grow when a pane needs more space.
final class ResizableSettingsWindowDelegate: NSObject, NSWindowDelegate {
  static let shared = ResizableSettingsWindowDelegate()

  private static let defaultContentSize = NSSize(width: 750, height: 640)
  private static let minimumContentSize = NSSize(width: 520, height: 400)

  private var savedContentSize: NSSize?
  private var isLiveResizing = false
  private var isApplyingFrameChange = false

  func configure(_ window: NSWindow) {
    window.styleMask.insert([.resizable, .miniaturizable])
    window.minSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: Self.minimumContentSize)).size
    window.delegate = self
  }

  func applyDefaultSizeIfNeeded(_ window: NSWindow) {
    let current = window.contentLayoutRect.size
    if current.width < 600 || current.height < 480 {
      applyContentSize(Self.defaultContentSize, to: window)
    } else if savedContentSize == nil {
      savedContentSize = current
    }
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    isLiveResizing = true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    isLiveResizing = false
    guard let window = notification.object as? NSWindow else { return }
    savedContentSize = window.contentLayoutRect.size
  }

  func windowDidResize(_ notification: Notification) {
    guard !isLiveResizing,
          !isApplyingFrameChange,
          let window = notification.object as? NSWindow else { return }

    let current = window.contentLayoutRect.size

    if let saved = savedContentSize {
      // User previously enlarged the window — don't let tab switches shrink it.
      if current.width + 1 < saved.width || current.height + 1 < saved.height {
        applyContentSize(
          NSSize(width: max(current.width, saved.width), height: max(current.height, saved.height)),
          to: window
        )
        return
      }
    }

    // Track growth from tab switches (taller panes like Quick Paste).
    if let saved = savedContentSize {
      if current.width > saved.width || current.height > saved.height {
        savedContentSize = NSSize(
          width: max(saved.width, current.width),
          height: max(saved.height, current.height)
        )
      }
    } else {
      savedContentSize = current
    }
  }

  private func applyContentSize(_ contentSize: NSSize, to window: NSWindow) {
    isApplyingFrameChange = true
    defer { isApplyingFrameChange = false }

    var frame = window.frame
    let newFrameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
    frame.origin.y += frame.height - newFrameSize.height
    frame.size = newFrameSize
    window.setFrame(frame, display: true)
    savedContentSize = contentSize
  }
}

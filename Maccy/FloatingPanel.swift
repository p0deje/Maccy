import Defaults
import SwiftUI

/// An NSPanel subclass that implements floating panel traits.
/// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented: Bool = false
  var menuBarButton: NSStatusBarButton? = nil

  init(
    contentRect: NSRect,
    title: String = "",
    view: () -> Content
  ) {
    /// Init the window as usual
    super.init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    Defaults[.windowSize] = contentRect.size
    delegate = self

    /// Allow the panel to be on top of other windows
    isFloatingPanel = true
    level = .floating

    /// Allow the panel to be overlaid in a fullscreen space
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]

    /// Don't show a window title, even if it's set
    self.title = title
    titleVisibility = .hidden
    titlebarAppearsTransparent = true

    /// Since there is no title bar make the window moveable by dragging on the background
    isMovableByWindowBackground = true

    /// Don't hide when unfocused
    hidesOnDeactivate = false

    /// Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    /// Sets animations accordingly
    animationBehavior = .none

    /// Set the content view.
    /// The safe area is ignored because the title bar still interferes with the geometry
    contentView = NSHostingView(
      rootView: view().ignoresSafeArea()
    )
  }

  func toggle(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(at: popupPosition)
    }
  }

  // TODO: Check https://github.com/p0deje/Maccy/issues/473.
  func open(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    setFrameOrigin(popupPosition.origin(size: frame.size, menuBarButton: menuBarButton))
    orderFrontRegardless()
    makeKey()
    isPresented = true
  }

  func resizeContentHeight(to newHeight: CGFloat) {
    var newSize = Defaults[.windowSize]
    if newHeight < newSize.height {
      newSize.height = newHeight
    }

    setContentSize(newSize)
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    Defaults[.windowSize] = frameSize

    return frameSize
  }

  /// Close automatically when out of focus, e.g. outside click
  override func resignKey() {
    super.resignKey()
    // Don't hide if confirmation is shown.
    if NSApp.alertWindow == nil {
      close()
    }
  }

  /// Close and toggle presentation, so that it matches the current state of the panel
  override func close() {
    super.close()
    isPresented = false
    menuBarButton?.state = .off
  }

  /// `canBecomeKey` is required so that text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }
}

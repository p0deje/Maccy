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
    level = .statusBar

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
      rootView: view()
        .ignoresSafeArea()
        .gesture(DragGesture()
          .onEnded { _ in
            if let screenFrame = self.screen?.visibleFrame {
              let anchorX = self.frame.minX + self.frame.width / 2 - screenFrame.minX
              let anchorY = self.frame.maxY - screenFrame.minY
              Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
            }
        })
    )
  }

  func toggle(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(height: height, at: popupPosition)
    }
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    setContentSize(NSSize(width: frame.width, height: min(height, Defaults[.windowSize].height)))
    setFrameOrigin(popupPosition.origin(size: frame.size, menuBarButton: menuBarButton))
    orderFrontRegardless()
    makeKey()
    isPresented = true
  }

  func verticallyResize(to newHeight: CGFloat) {
    var newSize = Defaults[.windowSize]
    newSize.height = min(newHeight, newSize.height)

    var newOrigin = frame.origin
    newOrigin.y = newOrigin.y + (frame.height - newSize.height)

    NSAnimationContext.runAnimationGroup { (context) in
      context.duration = 0.2
      animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    Defaults[.windowSize] = frameSize

    return frameSize
  }

  override var isMovable: Bool {
    get {
      return Defaults[.popupPosition] != .statusItem
    }
    set {}
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

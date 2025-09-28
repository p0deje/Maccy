import Defaults
import SwiftUI

// An NSPanel subclass that implements floating panel traits.
// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented: Bool = false
  var statusBarButton: NSStatusBarButton?
  let onClose: () -> Void

  override var isMovable: Bool {
    get { Defaults[.popupPosition] != .statusItem }
    set {}
  }

  init(
    contentRect: NSRect,
    identifier: String = "",
    statusBarButton: NSStatusBarButton? = nil,
    onClose: @escaping () -> Void,
    view: () -> Content
  ) {
    self.onClose = onClose

    super.init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )

    self.statusBarButton = statusBarButton
    self.identifier = NSUserInterfaceItemIdentifier(identifier)

    Defaults[.windowSize] = contentRect.size
    delegate = self

    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false

    // Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = NSHostingView(
      rootView: view()
        // The safe area is ignored because the title bar still interferes with the geometry
        .ignoresSafeArea()
        .gesture(DragGesture()
          .onEnded { _ in
            self.saveUserAdjustedWindowFrame(frame: self.frame)
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
    // Always use user adjusted window size as the maximum height limit
    let userAdjustedSize = Defaults[.userAdjustedWindowSize]
    let targetHeight = min(height, userAdjustedSize.height) // Use the smaller of content height or user adjusted height
    setContentSize(NSSize(width: userAdjustedSize.width, height: targetHeight))
    setFrameOrigin(popupPosition.origin(size: frame.size, statusBarButton: statusBarButton))
    orderFrontRegardless()
    makeKey()
    isPresented = true

    if popupPosition == .statusItem {
      DispatchQueue.main.async {
        self.statusBarButton?.isHighlighted = true
      }
    }
  }

  func verticallyResize(to newHeight: CGFloat) {
    let newSize = NSSize(width: Defaults[.userAdjustedWindowSize].width, height: newHeight)

    var newOrigin = frame.origin
    newOrigin.y += (frame.height - newSize.height)

    NSAnimationContext.runAnimationGroup { (context) in
      context.duration = 0.2
      animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }
    
    // Only save current window size for internal tracking, don't overwrite user adjusted size
    saveWindowFrame(frame: NSRect(origin: newOrigin, size: newSize))
  }

  func saveWindowFrame(frame: NSRect) {
    Defaults[.windowSize] = frame.size

    if let screenFrame = screen?.visibleFrame {
      let anchorX = frame.minX + frame.width / 2 - screenFrame.minX
      let anchorY = frame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }
  
  func saveUserAdjustedWindowFrame(frame: NSRect) {
    Defaults[.userAdjustedWindowSize] = frame.size
    saveWindowFrame(frame: frame)
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    saveUserAdjustedWindowFrame(frame: NSRect(origin: frame.origin, size: frameSize))

    return frameSize
  }

  func windowDidResize(_ notification: Notification) {
    // Save window size after resize is complete - this is user manual resize
    saveUserAdjustedWindowFrame(frame: frame)
  }

  // Close automatically when out of focus, e.g. outside click.
  override func resignKey() {
    super.resignKey()
    // Don't hide if confirmation is shown.
    if NSApp.alertWindow == nil {
      close()
    }
  }

  override func close() {
    // Don't save window size on close - it should only be saved on user manual resize
    super.close()
    isPresented = false
    statusBarButton?.isHighlighted = false
    onClose()
  }

  // Allow text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }
}

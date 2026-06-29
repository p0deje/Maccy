import Defaults
import SwiftUI

/// An `NSPanel` subclass that implements floating-panel traits: it stays above
/// other windows without stealing focus and hosts the popup's SwiftUI content.
///
/// Reference for the non-activating-panel technique:
/// https://stackoverflow.com/questions/46023769/how-to-show-a-window-without-stealing-focus-on-macos
class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate {
  /// Whether the panel is currently on screen.
  var isPresented: Bool = false
  /// The status-item button that anchors a status-item-positioned popup.
  var statusBarButton: NSStatusBarButton?
  /// Invoked after the panel closes.
  let onClose: () -> Void

  /// Whether the user can drag the panel. Disabled when anchored to the status item.
  override var isMovable: Bool {
    get { Defaults[.popupPosition] != .statusItem }
    set {}
  }

  /// Creates the panel with floating, non-activating traits and hosts `view`.
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
        styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
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
    backgroundColor = .clear
    titlebarSeparatorStyle = .none

    // Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = NSHostingView(
      rootView: view()
        // The safe area is ignored because the title bar still interferes with the geometry
        .ignoresSafeArea()
        .gesture(DragGesture()
          .onEnded { [weak self] _ in
            self?.saveWindowPosition()
        })
    )
    contentView?.layer?.cornerRadius = Popup.cornerRadius + Popup.horizontalPadding
  }

  /// Shows the panel if hidden, otherwise closes it.
  func toggle(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    if isPresented {
      close()
    } else {
      open(height: height, at: popupPosition)
    }
  }

  /// Positions and orders the panel front, making it the key window.
  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    let size = Defaults[.windowSize]
    setContentSize(NSSize(width: min(frame.width, size.width), height: min(height, size.height)))
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

  /// Resizes the panel to `newHeight`, keeping its top edge fixed.
  ///
  /// Resizes instantly rather than animating. The prior animated resize forced a
  /// full `NSHostingView.layout()` (a popup-tree re-layout plus CoreText
  /// re-measure of every visible row) on each display-link frame, producing a
  /// per-frame layout storm. A single `setFrame` performs a single layout. The
  /// visible effect is that the popup snaps to size instead of settling over
  /// roughly 0.2 seconds.
  func verticallyResize(to newHeight: CGFloat) {
    var newSize = frame.size
    newSize.height = newHeight
    var newOrigin = frame.origin
    newOrigin.y += (frame.height - newSize.height)

    setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
  }

  /// Recomputes the preview placement against the current window frame, if the preview is closed.
  func determinePreviewPlacement() {
    let preview = AppState.shared.preview
    guard !preview.state.isOpen else { return }
    let newSize = preview.computeSizeWithPreview(frame.size, state: .open)
    preview.placement = preview.computePlacement(window: self, for: newSize)
  }

  /// Persists the window's position relative to the current screen, as a
  /// normalized anchor in the preview-content coordinate space.
  func saveWindowPosition() {
    if let screenFrame = screen?.visibleFrame {
      // Only store the size of the window without the preview
      let width = AppState.shared.preview.contentWidth

      let anchorX = frame.minX + width / 2 - screenFrame.minX
      let anchorY = frame.maxY - screenFrame.minY
      Defaults[.windowPosition] = NSPoint(x: anchorX / screenFrame.width, y: anchorY / screenFrame.height)
    }
  }

  /// Persists the window's size and position.
  func saveWindowFrame(frame: NSRect) {
    Defaults[.windowSize] = frame.size
    saveWindowPosition()
  }

  /// Constrains the live-resize frame: pins height to the stored frame (height
  /// is governed by `maxVisibleItems`) and enforces preview/content width floors.
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let preview = AppState.shared.preview

    if inLiveResize && preview.resizingMode == .none {
      let screenPoint = NSEvent.mouseLocation
      let windowPoint = convertPoint(fromScreen: screenPoint)
      let location: SlideoutPlacement = windowPoint.x <= frame.width / 2 ? .left : .right
      if (location == preview.placement) && preview.state == .open {
        preview.startResize(mode: .slideout)
      } else {
        preview.startResize(mode: .content)
      }
    }

    var finalFrameSize = frameSize
    if inLiveResize {
      // Height is governed by `Defaults[.maxVisibleItems]`; pin the returned
      // height to the current frame so manual vertical drag is a no-op. Width
      // stays freely resizable (and still drives preview resize).
      // `windowWillResize` is only sent for user live resize — programmatic
      // `setFrame`/`setContentSize` bypass it — and the `inLiveResize` gate
      // keeps those paths unaffected.
      finalFrameSize.height = frame.height
    }
    var minContent = preview.minimumContentWidth
    var minPreview = 0.0

    if inLiveResize && preview.resizingMode != .none {
      if preview.resizingMode == .content && preview.state == .open {
        minPreview = preview.slideoutWidth
      }
      if preview.resizingMode == .slideout {
        minPreview = preview.minimumSlideoutWidth
        minContent = preview.contentWidth
      }
    }
    finalFrameSize.width = max(finalFrameSize.width, minContent + minPreview)

    if !AppState.shared.preview.state.isAnimating {
      // Width follows the drag; height is governed by maxVisibleItems, so
      // preserve the stored window height rather than clobbering it with the
      // (frozen) frame height.
      var size = Defaults[.windowSize]
      size.width = AppState.shared.preview.contentWidth
      saveWindowFrame(frame: NSRect(origin: frame.origin, size: size))
    }

    return finalFrameSize
  }

  /// Recomputes preview placement as the user begins dragging the window.
  func windowWillMove(_ notification: Notification) {
    determinePreviewPlacement()
  }

  /// Recomputes preview placement after the window has been moved.
  func windowDidMove(_ notification: Notification) {
    determinePreviewPlacement()
  }

  /// Cancels any pending preview auto-open at the start of a live resize.
  func windowWillStartLiveResize(_ notification: Notification) {
    AppState.shared.preview.cancelAutoOpen()
  }

  /// Re-targets the preview to the lead item and ends resize tracking.
  func windowDidEndLiveResize(_ notification: Notification) {
    AppState.shared.preview.scheduleRetarget(lead: AppState.shared.navigator.leadHistoryItem)
    AppState.shared.preview.endResize()
  }

  /// Enables preview auto-open and re-targets it to the lead item when the window gains key.
  func windowDidBecomeKey(_ notification: Notification) {
    AppState.shared.preview.enableAutoOpen()

    if AppState.shared.navigator.leadHistoryItem != nil {
      AppState.shared.preview.scheduleRetarget(lead: AppState.shared.navigator.leadHistoryItem)
    }
  }

  /// Disables preview auto-open when the window loses key.
  func windowDidResignKey(_ notification: Notification) {
    AppState.shared.preview.disableAutoOpen()
  }

  /// Closes the panel automatically when it loses focus (e.g. an outside click),
  /// unless a confirmation alert is currently shown.
  override func resignKey() {
    super.resignKey()
    if NSApp.alertWindow == nil {
      close()
    }
  }

  /// Closes the panel and tears down preview state, then invokes `onClose`.
  override func close() {
    super.close()
    AppState.shared.preview.state = .closed
    AppState.shared.preview.previewedItem = nil
    isPresented = false
    statusBarButton?.isHighlighted = false
    onClose()
  }

  /// Allows text inputs inside the panel to receive keyboard focus.
  override var canBecomeKey: Bool {
    return true
  }
}

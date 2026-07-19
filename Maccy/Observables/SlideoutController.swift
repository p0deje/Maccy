import Defaults
import Logging
import Observation
import SwiftUI

enum SlideoutState {
  case opening
  case closing
  case open
  case closed

  var isAnimating: Bool {
    switch self {
    case .closed, .open:
      return false
    case .opening, .closing:
      return true
    }
  }

  var isOpen: Bool {
    switch self {
    case .open, .opening:
      return true
    case .closed, .closing:
      return false
    }
  }

  fileprivate func toggleWithAnimation() -> SlideoutState {
    switch self {
    case .open, .opening:
      return .closing
    case .closed, .closing:
      return .opening
    }
  }

  func animationDone() -> SlideoutState {
    switch self {
    case .open, .opening:
      return .open
    case .closed, .closing:
      return .closed
    }
  }
}

enum SlideoutPlacement {
  case left
  case right
}

enum SlideoutToggleTrigger {
  case autoOpen
  case manual
}

enum ResizingMode {
  case none
  case content
  case slideout
}

@Observable
class SlideoutController {
  let logger = Logger(label: "org.p0deje.Maccy")
  private static let animationDuration = 0.25

  let onContentResize: (CGFloat) -> Void
  let onSlideoutResize: (CGFloat) -> Void

  let minimumContentWidth: CGFloat = 200
  var contentResizeWidth: CGFloat = 0
  var contentAnimationWidth: CGFloat?

  let minimumSlideoutWidth: CGFloat = 200
  var slideoutResizeWidth: CGFloat = 0

  private var _contentWidth: CGFloat = 0
  var contentWidth: CGFloat {
    get { return _contentWidth }
    set {
      _contentWidth = max(minimumContentWidth, newValue).rounded()
      onContentResize(_contentWidth)
    }
  }
  private var _slideoutWidth: CGFloat = 400
  var slideoutWidth: CGFloat {
    get { return _slideoutWidth }
    set {
      _slideoutWidth = max(minimumSlideoutWidth, newValue).rounded()
      onSlideoutResize(_slideoutWidth)
    }
  }

  var placement: SlideoutPlacement = .right
  var state: SlideoutState = .closed
  var resizingMode: ResizingMode = .none

  var nswindow: NSWindow? {
    AppState.shared.activeFloatingPanel
  }

  /// Todos detail panel is always on the left; the window grows leftward with a fixed right edge.
  private var usesLeftAnchoredExpansion: Bool {
    AppState.shared.activeTab == .todos
  }

  private var windowAnimationOrigin: CGPoint?
  private var windowAnimationOriginBaseState: SlideoutState = .closed

  private var autoOpenTask: Task<Void, Never>?
  private var autoOpenSuppressed = false
  private var autoOpenEnabled = true

  init(onContentResize: @escaping (CGFloat) -> Void, onSlideoutResize: @escaping (CGFloat) -> Void) {
    self.onContentResize = onContentResize
    self.onSlideoutResize = onSlideoutResize
  }

  private func togglePreviewStateWithAnimation(windowFrame: NSRect) {
    let newValue = state.toggleWithAnimation()
    if !state.isAnimating && newValue.isAnimating {
      contentAnimationWidth = contentWidth
      windowAnimationOrigin = windowFrame.origin
      windowAnimationOriginBaseState = state
    }
    state = newValue
  }

  func computePlacement(window: NSWindow, for size: NSSize) -> SlideoutPlacement {
    if usesLeftAnchoredExpansion {
      return .left
    }

    guard let screen = window.screen?.frame else { return placement }
    let windowFrame = window.frame
    if windowFrame.minX + size.width > screen.maxX {
      return .left
    }
    return .right
  }

  /// Keeps the list's right edge fixed and grows or shrinks toward the left, clamped to the visible screen.
  private func frameWithRightEdgeAnchored(
    window: NSWindow,
    rightEdge: CGFloat,
    totalWidth: CGFloat,
    height: CGFloat
  ) -> (origin: NSPoint, width: CGFloat) {
    let screenMinX = window.screen?.visibleFrame.minX ?? window.screen?.frame.minX ?? 0
    var width = totalWidth
    var originX = rightEdge - width
    if originX < screenMinX {
      originX = screenMinX
      width = rightEdge - originX
    }
    let originY = window.frame.origin.y + (window.frame.height - height)
    return (NSPoint(x: originX, y: originY), width)
  }

  /// Repositions the todos window so only the left side grows (e.g. while dragging the divider).
  func applyLeftAnchoredFrame(window: NSWindow) {
    guard usesLeftAnchoredExpansion, state.isOpen else { return }

    let height = computeSizeWithPreview(
      NSSize(width: contentWidth, height: window.frame.height),
      state: state
    ).height
    let totalWidth = contentWidth + slideoutWidth
    let anchored = frameWithRightEdgeAnchored(
      window: window,
      rightEdge: window.frame.maxX,
      totalWidth: totalWidth,
      height: height
    )
    window.setFrame(
      NSRect(origin: anchored.origin, size: NSSize(width: anchored.width, height: height)),
      display: true
    )
  }

  func computeSizeWithPreview(_ size: NSSize, state newState: SlideoutState) -> NSSize {
    var newSize = size
    if newState.isOpen {
      newSize.width += slideoutWidth
    }
    let popup = AppState.shared.popup
    newSize.height = popup.preferredHeight(for: popup.height)
    return newSize
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func togglePreview(trigger: SlideoutToggleTrigger = .manual) {
    if !state.isOpen {
      let appState = AppState.shared
      switch appState.activeTab {
      case .clipboard:
        let navigator = appState.navigator
        guard navigator.leadHistoryItem != nil || navigator.pasteStackSelected else { return }
      case .todos:
        guard appState.todos.selectedItem != nil else { return }
      }
    }

    if trigger == .manual {
      if state.isOpen {
        autoOpenSuppressed = true
      } else {
        autoOpenSuppressed = false
      }
    }

    cancelAutoOpen()

    if let window = nswindow {
      if contentResizeWidth > 0 {
        contentWidth = contentResizeWidth
      } else if usesLeftAnchoredExpansion, !state.isOpen {
        contentWidth = window.frame.width.rounded()
      }
    }

    withAnimation(.easeInOut(duration: Self.animationDuration), completionCriteria: .removed) {
      if let window = nswindow {
        let listRight = window.frame.maxX

        togglePreviewStateWithAnimation(windowFrame: window.frame)
        var newSize = window.frame.size
        newSize.width = contentWidth
        newSize = computeSizeWithPreview(newSize, state: self.state)
        if state.isOpen {
          placement = computePlacement(window: window, for: newSize)
        }

        let expectedAnimationState = state
        NSAnimationContext.runAnimationGroup { (context) in
          var newOrigin = windowAnimationOrigin ?? window.frame.origin
          newOrigin.y += (window.frame.height - newSize.height)

          if usesLeftAnchoredExpansion {
            let anchored = frameWithRightEdgeAnchored(
              window: window,
              rightEdge: listRight,
              totalWidth: newSize.width,
              height: newSize.height
            )
            newOrigin = anchored.origin
            newSize.width = anchored.width
          } else if placement == .left {
            if windowAnimationOriginBaseState == .closed && state.isOpen {
              newOrigin.x -= slideoutWidth
            } else if windowAnimationOriginBaseState == .open
              && !state.isOpen {
              newOrigin.x += slideoutWidth
            }
            // Otherwise the base is the desired position
          }
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          context.completionHandler = {
            if self.state == expectedAnimationState {
              self.state = expectedAnimationState.animationDone()
            }
          }
          context.duration = Self.animationDuration
          window.animator().setFrame(
            NSRect(origin: newOrigin, size: newSize),
            display: true
          )
        }
      }
    } completion: {
    }
  }

  func startResize(mode: ResizingMode) {
    logger.info("Starting resize with mode \(mode)")
    resizingMode = mode
    contentWidth = contentResizeWidth
    slideoutWidth = slideoutResizeWidth
  }

  func endResize() {
    logger.info("Ended resize. Mode was \(resizingMode)")
    switch resizingMode {
    case .none:
      return
    case .content:
      contentWidth = contentResizeWidth
    case .slideout:
      slideoutWidth = slideoutResizeWidth
    }
    resizingMode = .none
  }

  func startAutoOpen() {
    cancelAutoOpen()

    guard Defaults[.openPreviewAutomatically] else { return }
    guard autoOpenEnabled else { return }
    guard !autoOpenSuppressed else { return }
    guard !state.isOpen else { return }

    autoOpenTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(Defaults[.previewDelay]))
      guard !Task.isCancelled else { return }
      guard Defaults[.openPreviewAutomatically] else { return }

      if !state.isOpen {
        togglePreview(trigger: .autoOpen)
      }
    }
  }

  func cancelAutoOpen() {
    autoOpenTask?.cancel()
    autoOpenTask = nil
  }

  func enableAutoOpen() {
    autoOpenEnabled = true
  }

  func disableAutoOpen() {
    autoOpenEnabled = false
    cancelAutoOpen()
  }

  func resetAutoOpenSuppression() {
    autoOpenSuppressed = false
  }
}

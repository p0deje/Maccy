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
  // The item the preview pane is currently showing. Decoupled from the lead
  // selection so the pane doesn't chase every arrow move (sticky-chase fix):
  // it's set only on retarget-fire (scheduleRetarget) or manual open
  // (togglePreview), not on every leadHistoryItem change.
  var previewedItem: HistoryItemDecorator?
  var resizingMode: ResizingMode = .none

  var nswindow: NSWindow? {
    return AppState.shared.appDelegate?.panel
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
    guard let screen = window.screen?.frame else { return placement }
    let windowFrame = window.frame
    if windowFrame.minX + size.width > screen.maxX {
      return .left
    } else {
      return .right
    }
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

  func togglePreview(trigger: SlideoutToggleTrigger = .manual) {
    if !state.isOpen {
      let navigator = AppState.shared.navigator
      guard navigator.leadHistoryItem != nil || navigator.pasteStackSelected else { return }
      // Bind the pane to the current lead on open. Nil for the pasteStack case
      // (SlideoutContentView falls through to its pasteStack branch). Auto-open
      // already set this via scheduleRetarget; this covers the manual path.
      previewedItem = navigator.leadHistoryItem
    }

    if trigger == .manual {
      if state.isOpen {
        autoOpenSuppressed = true
      } else {
        autoOpenSuppressed = false
      }
    }

    cancelAutoOpen()
    withAnimation(.easeInOut(duration: Self.animationDuration), completionCriteria: .removed) {
      if let window = nswindow {
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

          if placement == .left {
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

  /// Schedules the preview pane to retarget to `lead` after `previewDelay` ms,
  /// then open if closed. Each call cancels the prior schedule (cancelAutoOpen),
  /// so rapid lead changes coalesce to the final one — the cancel-on-change IS
  /// the debounce at every delay value. `previewDelay` ≈ 0 (or <~100ms) →
  /// effectively instant follow-selection; higher → dwell-to-peek. `previewedItem`
  /// is set on fire, not on every lead change, so the pane stops chasing every
  /// selection (the sticky-chase fix). Re-checks arming at fire time so a manual
  /// close during the wait aborts the open.
  func scheduleRetarget(lead: HistoryItemDecorator?) {
    cancelAutoOpen()

    guard autoOpenEnabled else { return }
    guard !autoOpenSuppressed else { return }
    guard let lead else { return }

    autoOpenTask = Task { @MainActor in
      let delay = max(0, Defaults[.previewDelay])
      if delay > 0 {
        try? await Task.sleep(for: .milliseconds(delay))
      }
      guard !Task.isCancelled else { return }
      guard autoOpenEnabled, !autoOpenSuppressed else { return }
      previewedItem = lead
      if !state.isOpen {
        let navigator = AppState.shared.navigator
        guard navigator.leadHistoryItem != nil || navigator.pasteStackSelected else { return }
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

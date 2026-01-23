import Defaults
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

@Observable
class SlideoutController {

  private static let animationDuration = 0.25

  var contentWidth: CGFloat = 0
  var contentAnimationWidth: CGFloat?

  let minimumSlideoutWidth: CGFloat = 200
  var slideoutWidth: CGFloat = 400
  var slideoutResizeWidth: CGFloat = 0

  var placement: SlideoutPlacement = .right
  var state: SlideoutState = .closed

  var nswindow: NSWindow? {
    return AppState.shared.appDelegate?.panel
  }

  private var windowAnimationOrigin: CGPoint?
  private var windowAnimationOriginBaseState: SlideoutState = .closed

  private var autoOpenTask: Task<Void, Never>?

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

  func togglePreview() {
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

  func startAutoOpen() {
    cancelAutoOpen()

    guard !state.isOpen else { return }

    autoOpenTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(Defaults[.previewDelay]))
      guard !Task.isCancelled else { return }

      if !state.isOpen {
        togglePreview()
      }
    }
  }

  func cancelAutoOpen() {
    autoOpenTask?.cancel()
    autoOpenTask = nil
  }
}

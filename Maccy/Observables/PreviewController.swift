import Defaults
import Observation
import SwiftUI

enum PreviewState {
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

  fileprivate func toggleWithAnimation() -> PreviewState {
    switch self {
    case .open, .opening:
      return .closing
    case .closed, .closing:
      return .opening
    }
  }

  func animationDone() -> PreviewState {
    switch self {
    case .open, .opening:
      return .open
    case .closed, .closing:
      return .closed
    }
  }
}

enum PreviewPlacement {
  case left
  case right
}

@Observable
class PreviewController {
  
  private static let animationDuration = 0.25

  var historyListWidth: CGFloat = 0
  var historyListAnimationWidth: CGFloat? = nil

  let minimumPreviewWidth: CGFloat = 200
  var previewWidth: CGFloat = 400
  var previewResizeWidth: CGFloat = 0

  var placement: PreviewPlacement = .right
  var state: PreviewState = .closed

  private var windowAnimationOrigin: CGPoint? = nil
  private var windowAnimationOriginBaseState: PreviewState = .closed

  private func togglePreviewStateWithAnimation(windowFrame: NSRect) {
    let newValue = state.toggleWithAnimation()
    if !state.isAnimating && newValue.isAnimating {
      historyListAnimationWidth = historyListWidth
      windowAnimationOrigin = windowFrame.origin
      windowAnimationOriginBaseState = state
    }
    state = newValue
  }

  func togglePreview() {
    withAnimation(.easeInOut(duration: Self.animationDuration), completionCriteria: .removed) {
      if let window = AppState.shared.appDelegate?.panel {
        togglePreviewStateWithAnimation(windowFrame: window.frame)
        let expectedAnimationState = state
        NSAnimationContext.runAnimationGroup { (context) in
          var newSize = window.frame.size
          newSize.width = historyListWidth
          if state.isOpen {
            newSize.width += previewWidth
          }
          var newOrigin = windowAnimationOrigin ?? window.frame.origin
          if placement == .left {
            if windowAnimationOriginBaseState == .closed && state.isOpen
            {
              newOrigin.x -= previewWidth
            } else if windowAnimationOriginBaseState == .open
              && !state.isOpen
            {
              newOrigin.x += previewWidth
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
}

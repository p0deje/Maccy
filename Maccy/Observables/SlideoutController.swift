import Defaults
import Logging
import Observation
import SwiftUI

/// Animation/open state of the slideout preview pane.
enum SlideoutState {
  case opening
  case closing
  case open
  case closed

  /// Whether the pane is mid open/close animation.
  var isAnimating: Bool {
    switch self {
    case .closed, .open:
      return false
    case .opening, .closing:
      return true
    }
  }

  /// Whether the pane is open or opening.
  var isOpen: Bool {
    switch self {
    case .open, .opening:
      return true
    case .closed, .closing:
      return false
    }
  }
}

/// Which side the slideout pane grows toward.
enum SlideoutPlacement {
  case left
  case right
}

/// What triggered a preview toggle (auto-open vs manual).
enum SlideoutToggleTrigger {
  case autoOpen
  case manual
}

/// Active resize handle during a content/slideout drag.
enum ResizingMode {
  case none
  case content
  case slideout
}

/// Drives the slideout preview pane: its open/close state, sizing, placement,
/// and the dwell-to-peek auto-open scheduling bound to selection changes.
@MainActor
@Observable
class SlideoutController {
  let logger = Logger(label: "org.p0deje.Maccy")

  let onContentResize: (CGFloat) -> Void
  let onSlideoutResize: (CGFloat) -> Void

  let minimumContentWidth: CGFloat = 200
  var contentResizeWidth: CGFloat = 0

  let minimumSlideoutWidth: CGFloat = 200
  var slideoutResizeWidth: CGFloat = 0

  private var _contentWidth: CGFloat = 0
  /// Content-column width, floor-clamped to the minimum and reported via `onContentResize`.
  var contentWidth: CGFloat {
    get { return _contentWidth }
    set {
      _contentWidth = max(minimumContentWidth, newValue).rounded()
      onContentResize(_contentWidth)
    }
  }
  private var _slideoutWidth: CGFloat = 400
  /// Slideout-column width, floor-clamped to the minimum and reported via `onSlideoutResize`.
  var slideoutWidth: CGFloat {
    get { return _slideoutWidth }
    set {
      _slideoutWidth = max(minimumSlideoutWidth, newValue).rounded()
      onSlideoutResize(_slideoutWidth)
    }
  }

  var placement: SlideoutPlacement = .right
  var state: SlideoutState = .closed
  /// The item the preview pane is currently showing. Decoupled from the lead
  /// selection so the pane doesn't chase every arrow move (sticky-chase fix):
  /// it's set only on retarget-fire (`scheduleRetarget`) or manual open
  /// (`togglePreview`), not on every `leadHistoryItem` change.
  var previewedItem: HistoryItemDecorator?
  var resizingMode: ResizingMode = .none

  /// The underlying panel window, if any.
  var nswindow: NSWindow? {
    return AppState.shared.appDelegate?.panel
  }

  private var autoOpenTask: Task<Void, Never>?
  private var autoOpenSuppressed = false
  private var autoOpenEnabled = true

  /// Creates the controller with the resize callbacks that persist width changes.
  init(onContentResize: @escaping (CGFloat) -> Void, onSlideoutResize: @escaping (CGFloat) -> Void) {
    self.onContentResize = onContentResize
    self.onSlideoutResize = onSlideoutResize
  }

  /// Picks `.left` when growing right would overflow the screen, else `.right`.
  func computePlacement(window: NSWindow, for size: NSSize) -> SlideoutPlacement {
    guard let screen = window.screen?.frame else { return placement }
    let windowFrame = window.frame
    if windowFrame.minX + size.width > screen.maxX {
      return .left
    } else {
      return .right
    }
  }

  /// Returns `size` widened by the slideout width when open, height-adjusted to `preferredHeight`.
  func computeSizeWithPreview(_ size: NSSize, state newState: SlideoutState) -> NSSize {
    var newSize = size
    if newState.isOpen {
      newSize.width += slideoutWidth
    }
    let popup = AppState.shared.popup
    newSize.height = popup.preferredHeight(for: popup.height)
    return newSize
  }

  /// Opens or closes the preview pane instantly.
  ///
  /// On open it binds `previewedItem` to the current lead (manual path;
  /// auto-open sets it via `scheduleRetarget`), and a manual toggle adjusts the
  /// auto-open suppression flag.
  ///
  /// Resizing uses a single instant `setFrame` — no `animator()`,
  /// `NSAnimationContext`, or `withAnimation`. The prior animated
  /// `window.animator().setFrame` forced a per-frame `NSHostingView.layout()`
  /// plus CoreText re-measure storm on every display-link tick (the dominant
  /// preview open/close jank). One `setFrame` is one layout pass; state collapses
  /// synchronously to `.open`/`.closed`, so there is no completion handler and
  /// no stranded `.opening`/`.closing`. The slideout column fades via SwiftUI
  /// opacity only — opacity is composited by CoreAnimation with no layout pass,
  /// so it can't re-trigger the storm.
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

    guard let window = nswindow else { return }

    let opening = !state.isOpen
    state = opening ? .open : .closed

    var newSize = window.frame.size
    newSize.width = contentWidth
    newSize = computeSizeWithPreview(newSize, state: state)
    if state.isOpen {
      placement = computePlacement(window: window, for: newSize)
    }

    var newOrigin = window.frame.origin
    newOrigin.y += window.frame.height - newSize.height
    if placement == .left {
      // Pin the anchor edge: growing toward the left shifts origin left;
      // shrinking shifts it back right.
      newOrigin.x += opening ? -slideoutWidth : slideoutWidth
    }

    window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
  }

  /// Begins a resize drag of the given mode, applying the in-progress widths.
  func startResize(mode: ResizingMode) {
    logger.info("Starting resize with mode \(mode)")
    resizingMode = mode
    contentWidth = contentResizeWidth
    slideoutWidth = slideoutResizeWidth
  }

  /// Ends a resize drag, committing the in-progress width for the active mode.
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

  /// Cancels any pending auto-open.
  func cancelAutoOpen() {
    autoOpenTask?.cancel()
    autoOpenTask = nil
  }

  /// Re-enables auto-open (after `disableAutoOpen`).
  func enableAutoOpen() {
    autoOpenEnabled = true
  }

  /// Disables auto-open and cancels any pending schedule.
  func disableAutoOpen() {
    autoOpenEnabled = false
    cancelAutoOpen()
  }

  /// Clears the manual-close suppression flag.
  func resetAutoOpenSuppression() {
    autoOpenSuppressed = false
  }
}

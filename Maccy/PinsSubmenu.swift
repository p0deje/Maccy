import AppKit
import Observation
import SwiftUI

// Shows pinned items in a menu-like panel next to the popup when the
// "Pinned" row at the bottom of the history list is hovered.
@MainActor
@Observable
final class PinsSubmenuController {
  static let shared = PinsSubmenuController()

  static let width: CGFloat = 320
  static let rowHeight: CGFloat = 40
  static let padding: CGFloat = Popup.verticalPadding
  // Grace period so the pointer can travel from the row to the submenu.
  private static let hideDelay: TimeInterval = 0.3
  private static let trackingInterval: TimeInterval = 0.05

  private(set) var isVisible = false

  @ObservationIgnored private var panel: PinsSubmenuPanel?
  @ObservationIgnored private weak var anchorView: NSView?
  @ObservationIgnored private var trackingTimer: Timer?
  @ObservationIgnored private var pointerLeftAt: Date?

  func show(anchoredTo view: NSView) {
    guard let parent = view.window, parent.isVisible else { return }

    let itemCount = AppState.shared.history.submenuPinnedItems.count
    guard itemCount > 0 else {
      hide()
      return
    }

    anchorView = view
    let panel = panel ?? makePanel()
    self.panel = panel

    if panel.parent !== parent {
      panel.parent?.removeChildWindow(panel)
      parent.addChildWindow(panel, ordered: .above)
    }
    panel.setFrame(frame(anchoredTo: view, in: parent, itemCount: itemCount), display: true)
    panel.orderFront(nil)

    isVisible = true
    pointerLeftAt = nil
    startTracking()
  }

  // Re-layouts the submenu after its pins changed (e.g. one was unpinned).
  func refresh() {
    guard isVisible, let anchorView else { return }
    show(anchoredTo: anchorView)
  }

  func hide() {
    trackingTimer?.invalidate()
    trackingTimer = nil
    pointerLeftAt = nil

    if let panel {
      panel.parent?.removeChildWindow(panel)
      panel.orderOut(nil)
    }
    isVisible = false
  }

  private func makePanel() -> PinsSubmenuPanel {
    let panel = PinsSubmenuPanel()
    let hostingView = FirstMouseHostingView(
      rootView: PinsSubmenuView().environment(AppState.shared)
    )
    hostingView.wantsLayer = true
    hostingView.layer?.cornerRadius = Popup.cornerRadius + Popup.horizontalPadding
    hostingView.layer?.cornerCurve = .continuous
    hostingView.layer?.masksToBounds = true
    panel.contentView = hostingView
    return panel
  }

  private func frame(anchoredTo view: NSView, in parent: NSWindow, itemCount: Int) -> NSRect {
    let anchorRect = parent.convertToScreen(view.convert(view.bounds, to: nil))
    let visibleFrame = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame

    let contentHeight = CGFloat(itemCount) * Self.rowHeight + 2 * Self.padding
    let height = min(contentHeight, visibleFrame.height)

    // Open next to the visible list like a regular submenu; flip left when there is no room.
    // The anchor row is used instead of the window frame, which also spans the collapsed preview pane.
    let gap = Popup.horizontalPadding
    var originX = anchorRect.maxX + gap
    if originX + Self.width > visibleFrame.maxX {
      originX = anchorRect.minX - gap - Self.width
    }

    // Align the first row with the anchor row, then keep the panel on screen.
    var originY = anchorRect.maxY + Self.padding - height
    originY = max(originY, visibleFrame.minY)
    originY = min(originY, visibleFrame.maxY - height)

    return NSRect(x: originX, y: originY, width: Self.width, height: height)
  }

  // Polling keeps working even though the submenu never becomes the key window.
  // The timer runs in the default run loop mode only, so it pauses while a
  // context menu is being tracked and the submenu stays open behind it.
  private func startTracking() {
    guard trackingTimer == nil else { return }

    let timer = Timer(timeInterval: Self.trackingInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.checkPointer()
      }
    }
    RunLoop.main.add(timer, forMode: .default)
    trackingTimer = timer
  }

  private func checkPointer() {
    guard let panel, let anchorView, let parent = anchorView.window, parent.isVisible else {
      hide()
      return
    }

    let pointer = NSEvent.mouseLocation
    let anchorRect = parent.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
    // The strip between the anchor row and the submenu, so crossing the popup edge does not close it.
    let corridor = NSRect(
      x: min(anchorRect.maxX, panel.frame.minX),
      y: anchorRect.minY,
      width: abs(panel.frame.minX - anchorRect.maxX),
      height: anchorRect.height
    )

    if panel.frame.contains(pointer) || anchorRect.contains(pointer) || corridor.contains(pointer) {
      pointerLeftAt = nil
      return
    }

    guard let pointerLeftAt else {
      pointerLeftAt = Date.now
      return
    }

    if Date.now.timeIntervalSince(pointerLeftAt) >= Self.hideDelay {
      hide()
    }
  }
}

final class PinsSubmenuPanel: NSPanel {
  init() {
    super.init(
      contentRect: .zero,
      styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
      backing: .buffered,
      defer: true
    )

    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
  }

  // Keep the popup as the key window so it does not auto-close.
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// Lets the first click in the non-key submenu select a pin right away.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

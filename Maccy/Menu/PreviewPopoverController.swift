import AppKit

class PreviewPopoverController {
  private static let popoverGap = 5.0
  private static let subsequentPreviewDelay = 0.2

  private var initialPreviewDelay: Double { Double(UserDefaults.standard.previewDelay) / 1000 }
  private lazy var previewThrottle = Throttler(minimumDelay: initialPreviewDelay)

  private var previewPopover: NSPopover?

  func menuWillOpen() {
    previewThrottle.minimumDelay = initialPreviewDelay
  }

  func menuDidClose() {
    cancelPopover()
  }

  func showPopover(for item: HistoryMenuItem, allItems: [Menu.IndexedItem]) {
    previewThrottle.throttle { [self] in
      let popover = NSPopover()
      popover.animates = false
      popover.behavior = .semitransient
      popover.contentViewController = Preview(item: item.item)

      guard let window = NSApp.menuWindow,
            let windowContentView = window.contentView,
            let boundsOfVisibleMenuItem = boundsOfMenuItem(item, windowContentView, allItems) else {
        return
      }

      previewThrottle.minimumDelay = PreviewPopoverController.subsequentPreviewDelay

      popover.show(
        relativeTo: boundsOfVisibleMenuItem,
        of: windowContentView,
        preferredEdge: .maxX
      )
      previewPopover = popover

      if let popoverWindow = popover.contentViewController?.view.window {
        let gap = PreviewPopoverController.popoverGap
        if popoverWindow.frame.maxX <= window.frame.minX {
          popoverWindow.setFrameOrigin(
            NSPoint(x: popoverWindow.frame.minX - gap, y: popoverWindow.frame.minY)
          )
        } else if popoverWindow.frame.minX >= window.frame.maxX {
          popoverWindow.setFrameOrigin(
            NSPoint(x: popoverWindow.frame.minX + gap, y: popoverWindow.frame.minY)
          )
        }
      }
    }
  }

  private func boundsOfMenuItem(
    _ item: NSMenuItem,
    _ windowContentView: NSView,
    _ allItems: [Menu.IndexedItem]
  ) -> NSRect? {
    if #available(macOS 14, *) {
      let windowRectInScreenCoordinates = windowContentView.accessibilityFrame()
      let menuItemRectInScreenCoordinates = item.accessibilityFrame()
      return NSRect(
        origin: NSPoint(
          x: menuItemRectInScreenCoordinates.origin.x - windowRectInScreenCoordinates.origin.x,
          y: menuItemRectInScreenCoordinates.origin.y - windowRectInScreenCoordinates.origin.y),
        size: menuItemRectInScreenCoordinates.size
      )
    } else {
      guard let item = item as? HistoryMenuItem,
            let itemIndex = allItems.firstIndex(where: { $0.menuItems.contains(item) }) else {
        return nil
      }
      let indexedItem = allItems[itemIndex]
      guard let previewView = indexedItem.popoverAnchor!.view else {
        return nil
      }

      func getPrecedingView() -> NSView? {
        for index in (0..<itemIndex).reversed() {
          // PreviewMenuItem always has a view
          // Check if preview item is visible (it may be hidden by the search filter)
          if let view = allItems[index].popoverAnchor?.view,
             view.window != nil {
            return view
          }
        }
        // If the item is the first visible one, the preceding view is the header.
        guard let header = item.menu?.items.first?.view else {
          // Should never happen as we always have a MenuHeader installed.
          return nil
        }
        return header
      }

      guard let precedingView = getPrecedingView() else {
        return nil
      }

      let bottomPoint = previewView.convert(
        NSPoint(x: previewView.bounds.minX, y: previewView.bounds.maxY),
        to: windowContentView
      )
      let topPoint = precedingView.convert(
        NSPoint(x: previewView.bounds.minX, y: precedingView.bounds.minY),
        to: windowContentView
      )

      let heightOfVisibleMenuItem = abs(topPoint.y - bottomPoint.y)
      return NSRect(
        origin: bottomPoint,
        size: NSSize(width: item.menu?.size.width ?? 0, height: heightOfVisibleMenuItem)
      )
    }
  }

  func cancelPopover() {
    previewThrottle.cancel()
    previewPopover?.close()
    previewPopover = nil
  }
}

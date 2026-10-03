import SwiftUI

struct ImageDragModifier: ViewModifier {
  let item: HistoryItemDecorator
  var onClick: (() -> Void)?
  var onHover: ((_ mouseMoved: Bool) -> Void)?

  @ViewBuilder
  func body(content: Content) -> some View {
    if item.hasImage {
      content.overlay {
        ImageDragSource(item: item, onClick: onClick, onHover: onHover)
          .accessibilityHidden(true)
      }
    } else {
      content.onTapGesture { onClick?() }
    }
  }
}

private struct ImageDragSource: NSViewRepresentable {
  let item: HistoryItemDecorator
  var onClick: (() -> Void)?
  var onHover: ((_ mouseMoved: Bool) -> Void)?

  func makeNSView(context: Context) -> ImageDragView {
    let view = ImageDragView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: ImageDragView, context: Context) {
    view.onClick = onClick
    view.onHover = onHover
    view.makeDrag = {
      let originalPNG = item.item.contents.first { $0.type == NSPasteboard.PasteboardType.png.rawValue }?.value
      guard let data = originalPNG ?? item.item.imageData,
            let image = item.item.image else { return nil }
      return (ImageDragPayload(data: data), image)
    }
  }
}

/// Own the native drag session so its image contains only the picture, never the popup's hosting view.
private final class ImageDragView: NSView, NSDraggingSource {
  var onClick: (() -> Void)?
  var onHover: ((_ mouseMoved: Bool) -> Void)?
  var makeDrag: (() -> (ImageDragPayload, NSImage)?)?
  private var hoverTrackingArea: NSTrackingArea?

  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
      owner: self, userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    onHover?(false)
  }

  override func mouseMoved(with event: NSEvent) {
    onHover?(true)
  }

  override func mouseDown(with event: NSEvent) {
    guard let window else { return }
    let start = event.locationInWindow
    // Track until the user either clicks or crosses the drag threshold. This also prevents
    // the hosting view's window-move gesture from picking up the whole floating panel.
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp {
        if bounds.contains(convert(next.locationInWindow, from: nil)) {
          onClick?()
        }
        return
      }
      let distance = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
      guard distance >= 4 else { continue }
      guard let (payload, image) = makeDrag?() else { return }

      let scale = min(1, 240 / max(image.size.width, 1), 160 / max(image.size.height, 1))
      let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
      let point = convert(next.locationInWindow, from: nil)
      let frame = NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                         width: size.width, height: size.height)
      let drag = NSDraggingItem(pasteboardWriter: payload.pasteboardItem())
      drag.setDraggingFrame(frame, contents: image)
      let session = beginDraggingSession(with: [drag], event: next, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = true
      return
    }
  }

  func draggingSession(_ session: NSDraggingSession,
                       sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    .copy
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                       operation: NSDragOperation) {
    // A cancelled or rejected drop must leave the popup available to try again.
    if !operation.isEmpty {
      window?.close()
    }
  }
}

import SwiftUI

extension View {
  /// Installs an `NSTrackingArea`-backed mouse-moved handler on this view.
  func onMouseMove(_ mouseMoved: @escaping () -> Void) -> some View {
    modifier(MouseMovedViewModifier(mouseMoved))
  }
}

/// Bridges SwiftUI mouse movement to an AppKit `NSTrackingArea` so a closure
/// fires whenever the cursor moves over the modified view.
struct MouseMovedViewModifier: ViewModifier {
  let mouseMoved: () -> Void

  init(_ mouseMoved: @escaping () -> Void) {
    self.mouseMoved = mouseMoved
  }

  func body(content: Content) -> some View {
    content.background(
      GeometryReader { geo in
        Representable(
          mouseMoved: mouseMoved,
          frame: geo.frame(in: .global)
        )
      }
    )
  }

  /// AppKit responder that forwards `mouseMoved` events to a closure.
  private class Coordinator: NSResponder {
    var mouseMoved: (() -> Void)?

    override func mouseMoved(with event: NSEvent) {
      mouseMoved?()
    }
  }

  /// `NSViewRepresentable` that owns the `NSTrackingArea` and its coordinator.
  private struct Representable: NSViewRepresentable {
    let mouseMoved: () -> Void
    let frame: NSRect

    func makeCoordinator() -> Coordinator {
      let coordinator = Coordinator()
      coordinator.mouseMoved = mouseMoved
      return coordinator
    }

    func makeNSView(context: Context) -> NSView {
      let view = NSView(frame: frame)

      let options: NSTrackingArea.Options = [
        .activeInKeyWindow,
        .inVisibleRect,
        .mouseMoved
      ]

      let trackingArea = NSTrackingArea(
        rect: frame,
        options: options,
        owner: context.coordinator,
        userInfo: nil
      )

      view.addTrackingArea(trackingArea)

      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
      nsView.trackingAreas.forEach { nsView.removeTrackingArea($0) }
    }
  }
}

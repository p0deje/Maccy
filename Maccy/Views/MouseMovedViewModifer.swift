import SwiftUI

extension View {
  func onMouseMove(_ mouseMoved: @escaping () -> Void) -> some View {
    modifier(MouseMovedViewModifier(mouseMoved))
  }
}

struct MouseMovedViewModifier: ViewModifier {
  let mouseMoved: () -> Void

  init(_ mouseMoved: @escaping () -> Void) {
    self.mouseMoved = mouseMoved
  }

  func body(content: Content) -> some View {
    content.background(
      Representable(mouseMoved: mouseMoved)
    )
  }

  private final class TrackingView: NSView {
    var mouseMoved: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      installTrackingArea()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installTrackingArea()
    }

    override func mouseMoved(with event: NSEvent) {
      mouseMoved?()
    }

    func removeTrackingArea() {
      if let trackingArea {
        removeTrackingArea(trackingArea)
        self.trackingArea = nil
      }
    }

    private func installTrackingArea() {
      removeTrackingArea()

      let options: NSTrackingArea.Options = [
        .activeInKeyWindow,
        .inVisibleRect,
        .mouseMoved
      ]

      let trackingArea = NSTrackingArea(
        rect: bounds,
        options: options,
        owner: self,
        userInfo: nil
      )

      addTrackingArea(trackingArea)
      self.trackingArea = trackingArea
    }
  }

  private struct Representable: NSViewRepresentable {
    let mouseMoved: () -> Void

    func makeNSView(context: Context) -> TrackingView {
      let view = TrackingView()
      view.mouseMoved = mouseMoved
      return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
      nsView.mouseMoved = mouseMoved
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: ()) {
      nsView.removeTrackingArea()
    }
  }
}

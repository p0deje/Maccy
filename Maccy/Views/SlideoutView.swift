import SwiftUI

/// Applies a fixed width only when a condition holds, otherwise leaves the
/// content unconstrained.
private struct ConditionalWidthModifier: ViewModifier {
  var width: CGFloat
  var condition: Bool

  func body(content: Content) -> some View {
    if condition {
      content
        .frame(width: width)
    } else {
      content
    }
  }
}

extension View {
  /// Conditionally constrains this view to a fixed width.
  fileprivate func conditionalWidth(_ width: CGFloat, condition: Bool)
    -> some View {
    self.modifier(
      ConditionalWidthModifier(width: width, condition: condition)
    )
  }
}

/// A two-pane layout with a draggable divider: a fixed content column and a
/// slideout column that opens, closes, and resizes under the control of a
/// `SlideoutController`.
struct SlideoutView<Content, Slideout>: View
where Content: View, Slideout: View {
  @Environment(AppState.self) private var appState

  let controller: SlideoutController

  @ViewBuilder var content: () -> Content
  @ViewBuilder var slideout: () -> Slideout

  /// Whether the slideout opens toward the right.
  var leftToRight: Bool {
    return controller.placement == .right
  }
  /// Whether an open/close animation is currently in progress.
  var isAnimating: Bool {
    return controller.state.isAnimating
  }

  /// Whether the content column is being resized via the divider.
  var isContentResizing: Bool {
    return controller.resizingMode == .content
  }
  /// Whether the slideout column is being resized via the divider.
  var isSlideoutResizing: Bool {
    return controller.resizingMode == .slideout
  }

  /// The draggable divider between the two panes, with hover cursor feedback
  /// and a drag gesture that updates the controller's widths.
  @ViewBuilder
  private func resizeDivider() -> some View {
    Divider()
      .padding(.vertical)
      .padding(.horizontal, Popup.horizontalPadding)
      // macOS 26 broke gestures if no background is present.
      // The slight opcaity white background is a workaround
      .background(Color.white.opacity(0.001))
      .onHover(perform: { inside in
        if let window = appState.appDelegate?.panel {
          window.isMovableByWindowBackground = !inside
        }
        if inside {
          if #available(macOS 15.0, *) {
            NSCursor.columnResize.push()
          } else {
            NSCursor.resizeLeftRight.push()
          }
        } else {
          NSCursor.pop()
        }
      })
      .gesture(
        DragGesture()
          .onChanged({ value in
            if let window = controller.nswindow {
              controller.slideoutWidth = min(
                max(
                  controller.minimumSlideoutWidth,
                  controller.slideoutResizeWidth + (leftToRight ? -1 : 1)
                    * value.translation.width
                ),
                window.frame.width - controller.minimumContentWidth
              )
              controller.contentWidth = window.frame.width - controller.slideoutWidth
            }
          })
          .onEnded({ _ in
            controller.slideoutWidth = controller.slideoutResizeWidth
            controller.contentWidth = controller.contentResizeWidth
          })
      )
      .disabled(controller.state != .open)
      .frame(maxWidth: 0)
      .opacity(controller.state != .closed ? 1 : 0)
  }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        content()
      }
      .environment(\.layoutDirection, .leftToRight)
      .frame(
        minWidth: controller.minimumContentWidth,
        idealWidth: !isContentResizing ? controller.contentWidth.rounded() : nil,
        alignment: .leading
      )
      .frame(
        width: !isContentResizing ? controller.contentWidth.rounded() : nil
      )
      .fixedSize(
        horizontal: isAnimating || isSlideoutResizing,
        vertical: false
      )
      .readWidth(controller, into: \.contentResizeWidth)

      resizeDivider()

      VStack(spacing: 0) {
        slideout()
          .frame(
            minWidth: controller.minimumSlideoutWidth,
            idealWidth: !isSlideoutResizing ? controller.slideoutWidth.rounded() : nil,
            maxWidth: !isSlideoutResizing ? controller.slideoutWidth.rounded() : nil,
            alignment: .leading
          )
          .conditionalWidth(
            controller.slideoutWidth.rounded(),
            condition: isAnimating
          )
          .transition(.identity)
          // The window snaps open via an instant frame change (see
          // `SlideoutController`); the content is faded in here. The opacity
          // animation is scoped to `slideout()` so the outer width-collapse
          // frame below stays un-animated, keeping it to a single layout pass.
          .opacity(controller.state.isOpen ? 1 : 0)
          .animation(.easeOut(duration: 0.15), value: controller.state.isOpen)
      }
      .environment(\.layoutDirection, .leftToRight)
      .fixedSize(
        horizontal: isAnimating || isContentResizing,
        vertical: false
      )
      .frame(
        minWidth: controller.state != .open ? 0 : nil,
        maxWidth: controller.state == .closed ? 0 : nil
      )
      .clipped()
      .readWidth(controller, into: \.slideoutResizeWidth)
    }
    .environment(\.layoutDirection, leftToRight ? .leftToRight : .rightToLeft)
  }
}

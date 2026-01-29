import SwiftUI

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
  fileprivate func conditionalWidth(_ width: CGFloat, condition: Bool)
    -> some View {
    self.modifier(
      ConditionalWidthModifier(width: width, condition: condition)
    )
  }
}

struct SlideoutView<Content, Slideout>: View
where Content: View, Slideout: View {
  @Environment(AppState.self) private var appState

  let controller: SlideoutController

  var content: () -> Content
  var slideout: () -> Slideout

  var leftToRight: Bool {
    return controller.placement == .right
  }
  var isAnimating: Bool {
    return controller.state.isAnimating
  }
  
  var isContentResizing: Bool {
    return controller.resizingMode == .content
  }
  var isSlideoutResizing: Bool {
    return controller.resizingMode == .slideout
  }

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
            controller.slideoutWidth = max(
              controller.minimumSlideoutWidth,
              controller.slideoutResizeWidth + (leftToRight ? -1 : 1)
                * value.translation.width
            )
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
        idealWidth: !(isContentResizing || isDragging) ? controller.contentWidth : nil,
        alignment: .leading
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
            idealWidth: !(isSlideoutResizing || isDragging) ? controller.slideoutWidth : nil,
            maxWidth: !(isSlideoutResizing || isDragging) ? controller.slideoutWidth : nil,
            alignment: .leading
          )
          .conditionalWidth(
            controller.slideoutWidth,
            condition: isAnimating
          )
          .transition(.identity)
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

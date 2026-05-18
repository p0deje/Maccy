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

  @ViewBuilder var content: () -> Content
  @ViewBuilder var slideout: () -> Slideout

  private var slideoutOnLeft: Bool {
    controller.placement == .left
  }

  private var isAnimating: Bool {
    controller.state.isAnimating
  }

  private var isContentResizing: Bool {
    controller.resizingMode == .content
  }

  private var isSlideoutResizing: Bool {
    controller.resizingMode == .slideout
  }

  @ViewBuilder
  private func resizeDivider() -> some View {
    Divider()
      .padding(.vertical)
      .padding(.horizontal, Popup.horizontalPadding)
      .background(Color.white.opacity(0.001))
      .onHover(perform: { inside in
        if let window = appState.activeFloatingPanel {
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
            guard let window = controller.nswindow else { return }

            let growSign: CGFloat = slideoutOnLeft ? 1 : -1
            let newSlideoutWidth = min(
              max(
                controller.minimumSlideoutWidth,
                controller.slideoutResizeWidth + growSign * value.translation.width
              ),
              window.frame.width - controller.minimumContentWidth
            )
            controller.slideoutWidth = newSlideoutWidth

            if appState.activeTab == .todos {
              controller.applyLeftAnchoredFrame(window: window)
            } else {
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

  @ViewBuilder
  private var contentColumn: some View {
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
  }

  @ViewBuilder
  private var slideoutColumn: some View {
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

  var body: some View {
    HStack(spacing: 0) {
      if slideoutOnLeft {
        slideoutColumn
        resizeDivider()
        contentColumn
      } else {
        contentColumn
        resizeDivider()
        slideoutColumn
      }
    }
    .environment(\.layoutDirection, .leftToRight)
  }
}

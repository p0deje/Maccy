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
    -> some View
  {
    self.modifier(
      ConditionalWidthModifier(width: width, condition: condition)
    )
  }
}

struct SlideoutView<Content, Slideout>: View
where Content: View, Slideout: View {
  @Environment(AppState.self) private var appState

  @State var slideoutWidth: CGFloat = 0

  var content: () -> Content
  var slideout: () -> Slideout
  
  private var preview: PreviewController {
    return appState.preview
  }

  var leftToRight: Bool {
    return preview.placement == .right
  }
  var isAnimating: Bool {
    return preview.state.isAnimating
  }

  @ViewBuilder
  private func resizeDivider() -> some View {
    Divider()
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
            preview.previewWidth = max(
              preview.minimumPreviewWidth,
              preview.previewWidth + (leftToRight ? -1 : 1)
                * value.translation.width
            )
          })
          .onEnded({ value in
            preview.previewWidth = preview.previewResizeWidth
          })
      )
      .disabled(preview.state != .open)
      .frame(maxWidth: 0)
      .opacity(preview.state != .closed ? 1 : 0)
  }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        content()
      }
      .environment(\.layoutDirection, .leftToRight)
      .frame(
        maxWidth: isAnimating ? nil : .infinity,
        alignment: .leading
      )
      // Note: Using conditionalWidth() breaks the layout during animation for some reason.
      .frame(
        width: isAnimating ? preview.historyListAnimationWidth : nil,
      )
      .fixedSize(
        horizontal: isAnimating,
        vertical: false
      )
      .readWidth(appState, into: \.preview.historyListWidth)

      resizeDivider()

      VStack(spacing: 0) {
        slideout()
          .frame(
            idealWidth: preview.previewWidth,
            maxWidth: preview.previewWidth,
            alignment: .leading
          )
          .conditionalWidth(
            preview.previewWidth,
            condition: isAnimating
          )
          .transition(.identity)
      }
      .environment(\.layoutDirection, .leftToRight)
      .fixedSize(
        horizontal: isAnimating,
        vertical: false
      )
      .frame(
        minWidth: preview.state != .open ? 0 : nil,
        maxWidth: preview.state == .closed ? 0 : nil
      )
      .clipped()
      .readWidth(appState, into: \.preview.previewResizeWidth)
    }
    .environment(\.layoutDirection, leftToRight ? .leftToRight : .rightToLeft)
  }
}

import SwiftUI

// A text view that properly wraps single-line content without extra horizontal or vertical spaces.
// https://www.reddit.com/r/SwiftUI/comments/1gx1w6v/how_to_wrap_a_text_inside_a_macos_popover/
struct WrappingTextView: View {
  let text: String
  let maxWidth: CGFloat

  private let charHeight: CGFloat = 20
  private let charWidth: CGFloat = 7

  private var approxWidth: CGFloat {
    let width = CGFloat(text.count) * charWidth
    return min(max(width, 50), maxWidth)
  }

  private var approxHeight: CGFloat {
    let width = CGFloat(text.count) * charWidth
    return width / approxWidth * charHeight * 3
  }

  var body: some View {
    Text(text)
      .frame(idealWidth: approxWidth, maxHeight: approxHeight, alignment: .leading)
      .font(.body)
  }
}

import SwiftUI

// A text view that properly wraps single-line content without extra horizontal or vertical spaces.
// https://www.reddit.com/r/SwiftUI/comments/1gx1w6v/how_to_wrap_a_text_inside_a_macos_popover/
struct WrappingTextView: View {
  let text: String
  let maxWidth: CGFloat

  var body: some View {
    let approxSize = spaceNeeded(for: text, maxWidth: maxWidth)
    Text(text)
      .frame(idealWidth: approxSize.width, maxHeight: approxSize.height, alignment: .leading)
      .font(.body)
  }

  private func spaceNeeded(
    for text: String,
    maxWidth: CGFloat,
    targetRatio: CGFloat = 1.2,
    charWidth: CGFloat = 7,
    charHeight: CGFloat = 15
  ) -> NSSize {
    // Split text into lines
    let lines = text.components(separatedBy: .newlines)

    // Calculate total number of wrapped lines
    var totalLines = 0
    var maxLineWidth: CGFloat = 0

    for line in lines {
      let lineWidth = CGFloat(line.count) * charWidth
      maxLineWidth = max(maxLineWidth, lineWidth)

      if lineWidth > maxWidth {
        // Calculate how many lines this will wrap into
        totalLines += Int(ceil(lineWidth / maxWidth))
      } else {
        totalLines += 1
      }
    }

    // Calculate base width and height
    let width = min(maxLineWidth, maxWidth)
    var height = CGFloat(totalLines) * charHeight

    // Adjust dimensions to maintain target ratio
    let currentRatio = width / height
    if currentRatio > targetRatio {
      // Too wide, adjust height
      height = width / targetRatio
    }

    return NSSize(width: width, height: height)
  }
}

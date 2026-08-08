import SwiftUI

struct ListItemTitleView<Title: View>: View {
  var attributedTitle: AttributedString?
  @ViewBuilder var title: () -> Title

  var body: some View {
    if let attributedTitle {
      Text(attributedTitle)
        .accessibilityIdentifier("copy-history-item")
        .lineLimit(1)
        .truncationMode(.middle)
    } else {
      title()
        .accessibilityIdentifier("copy-history-item")
        .lineLimit(1)
        // On macOS 26, .truncationMode(.middle) causes NSCoreTypesetter to
        // enter an infinite truncation loop (__NSCoreTypesetterTruncateLine)
        // when the text is measured with an unconstrained size proposal
        // (e.g. during the SlideoutView preview-panel open/close animation).
        // Use .tail truncation on macOS 26 to avoid this CoreText hang.
        .truncationMode(truncationMode)
        // Workaround for macOS 26 to avoid flipped text
        // https://github.com/p0deje/Maccy/issues/1113
        .drawingGroup()
    }
  }

  private var truncationMode: Text.TruncationMode {
    if #available(macOS 26.0, *) {
      return .tail
    }
    return .middle
  }
}

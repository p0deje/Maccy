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
        .truncationMode(.middle)
        // Workaround for macOS 26 to avoid flipped text
        // https://github.com/p0deje/Maccy/issues/1113
        .drawingGroup()
    }
  }
}

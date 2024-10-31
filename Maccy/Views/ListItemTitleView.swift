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
        .padding(.leading, 5)
    } else {
      title()
        .accessibilityIdentifier("copy-history-item")
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.leading, 5)
    }
  }
}

import SwiftUI

struct ListItemTitleView<Title: View>: View {
  var attributedTitle: AttributedString? = nil
  @ViewBuilder var title: () -> Title

  var body: some View {
    if let attributedTitle {
      Text(attributedTitle)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.leading, 10)
    } else {
      title()
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.leading, 10)
    }
  }
}

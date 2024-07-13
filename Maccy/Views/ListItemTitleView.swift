import SwiftUI

struct ListItemTitleView: View {
  var attributedTitle: AttributedString? = nil
  var title: String

  var body: some View {
    if let attributedTitle {
      Text(attributedTitle)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.leading, 10)
    } else {
      Text(LocalizedStringKey(title))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.leading, 10)
    }
  }
}

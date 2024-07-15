import SwiftUI

struct ListItemTitleView: View {
  var attributedTitle: AttributedString? = nil
  var title: String
  var isSelected: Bool

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
        .tint(isSelected ? .white : .accentColor)
    }
  }
}

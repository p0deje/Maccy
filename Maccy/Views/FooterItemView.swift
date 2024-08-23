import SwiftUI

struct FooterItemView: View {
  @Bindable var item: FooterItem

  var body: some View {
    ConfirmationView(item: item) {
      ListItemView(id: item.id, shortcuts: item.shortcuts, isSelected: item.isSelected) {
        Text(LocalizedStringKey(item.title))
      }
    }
  }
}

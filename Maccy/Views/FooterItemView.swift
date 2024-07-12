import SwiftUI

struct FooterItemView: View {
  @Bindable var item: FooterItem

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    ConfirmationView(item: item) {
      ListItemView(
        id: item.id,
        title: item.title,
        shortcuts: item.shortcuts, 
        isSelected: item.isSelected
      )
    }
  }
}

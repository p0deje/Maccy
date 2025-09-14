import Defaults
import SwiftUI

struct FooterView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Default(.showFooter) private var showFooter
  @State private var clearOpacity: Double = 1
  @State private var clearAllOpacity: Double = 0

  var clearAllModifiersPressed: Bool {
    let clearModifiers = footer.items[0].shortcuts.first?.modifierFlags ?? []
    let clearAllModifiers = footer.items[1].shortcuts.first?.modifierFlags ?? []
    return !modifierFlags.flags.isEmpty
      && !modifierFlags.flags.isSubset(of: clearModifiers)
      && modifierFlags.flags.isSubset(of: clearAllModifiers)
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)

      ZStack {
        FooterItemView(item: footer.items[0])
          .opacity(clearOpacity)
        FooterItemView(item: footer.items[1])
          .opacity(clearAllOpacity)
      }
      .onChange(of: modifierFlags.flags) {
        if clearAllModifiersPressed {
          clearOpacity = 0
          clearAllOpacity = 1
          footer.items[0].isVisible = false
          footer.items[1].isVisible = true
          if appState.footer.selectedItem == footer.items[0] {
            appState.selection = footer.items[1].id
          }
        } else {
          clearOpacity = 1
          clearAllOpacity = 0
          footer.items[0].isVisible = true
          footer.items[1].isVisible = false
          if appState.footer.selectedItem == footer.items[1] {
            appState.selection = footer.items[0].id
          }
        }
      }

      ForEach(footer.items.suffix(from: 2)) { item in
        FooterItemView(item: item)
      }
    }
    .opacity(showFooter ? 1 : 0)
    .frame(maxHeight: showFooter ? nil : 0)
    .padding(.bottom, showFooter ? Popup.verticalPadding : 0)
    .readHeight(appState, into: \.popup.footerHeight)
  }
}

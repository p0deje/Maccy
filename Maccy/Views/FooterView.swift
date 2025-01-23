import Defaults
import SwiftUI

struct FooterView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Default(.showFooter) private var showFooter
  @Default(.popupOrigin) private var popupOrigin

  var isVisible: Bool {
      showFooter || popupOrigin == .statusItem
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

      ForEach(footer.items.suffix(from: 2)) { item in
        FooterItemView(item: item)
      }
    }
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.footerHeight = geo.size.height
          }
      }
    }
    .opacity(isVisible ? 1 : 0)
    .frame(maxHeight: isVisible ? nil : 0)
  }
}

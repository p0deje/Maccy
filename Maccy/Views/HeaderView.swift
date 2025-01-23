import Defaults
import SwiftUI

struct HeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase
  @Environment(ModifierFlags.self) private var modifierFlags
  @State private var clearOpacity: Double = 1
  @State private var clearAllOpacity: Double = 0

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack(spacing: 5) {
      if showTitle {
        Text("Maccy")
          .foregroundStyle(.secondary)
          .layoutPriority(1.5)
          .frame(width: 40)
      }

      SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
        .focused($searchFocused)
        .frame(maxWidth: .infinity)
        .layoutPriority(3)

      // Add Clear buttons
      ZStack {
        HeaderItemView(item: appState.footer.items[0])
          .opacity(clearOpacity)
        HeaderItemView(item: appState.footer.items[1])
          .opacity(clearAllOpacity)
      }
      .layoutPriority(1.5)
      .frame(width: 130)
      .onChange(of: modifierFlags.flags) {
        if clearAllModifiersPressed {
          clearOpacity = 0
          clearAllOpacity = 1
          appState.footer.items[0].isVisible = false
          appState.footer.items[1].isVisible = true
        } else {
          clearOpacity = 1
          clearAllOpacity = 0
          appState.footer.items[0].isVisible = true
          appState.footer.items[1].isVisible = false
        }
      }
    }
    .frame(height: appState.searchVisible ? 25 : 0)
    .opacity(appState.searchVisible ? 1 : 0)
    .padding(.horizontal, 10)
    // 2px is needed to prevent items from showing behind top pinned items during scrolling
    // https://github.com/p0deje/Maccy/issues/832
    .padding(.bottom, appState.searchVisible ? 5 : 2)
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.headerHeight = geo.size.height
          }
      }
    }
  }

  var clearAllModifiersPressed: Bool {
    let clearModifiers = appState.footer.items[0].shortcuts.first?.modifierFlags ?? []
    let clearAllModifiers = appState.footer.items[1].shortcuts.first?.modifierFlags ?? []
    return !modifierFlags.flags.isEmpty
      && !modifierFlags.flags.isSubset(of: clearModifiers)
      && modifierFlags.flags.isSubset(of: clearAllModifiers)
  }
}

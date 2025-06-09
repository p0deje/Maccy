import Defaults
import SwiftUI

struct HeaderView: View {
    @FocusState.Binding var searchFocused: Bool
    @Binding var searchQuery: String

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ThemeManager.self) private var themeManager

    @Default(.showTitle) private var showTitle

    var body: some View {
        HStack {
            if showTitle {
                Text("Maccy")
                    .foregroundStyle(.secondary)
            }

            SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
                .focused($searchFocused)
                .frame(maxWidth: .infinity)
                .onChange(of: scenePhase) {
                    if scenePhase == .background && !searchQuery.isEmpty {
                        searchQuery = ""
                    }
                }

            // Theme toggle button
            Button(action: toggleTheme) {
                Image(systemName: themeIconName)
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .animation(.easeInOut(duration: 0.2), value: themeIconName)
            }
            .buttonStyle(.plain)
            .help("Toggle theme (⇧⌘T)")
            .transition(.opacity)
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

    private var themeIconName: String {
        switch themeManager.currentTheme {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    private func toggleTheme() {
        switch themeManager.currentTheme {
        case .system:
            themeManager.currentTheme = .light
        case .light:
            themeManager.currentTheme = .dark
        case .dark:
            themeManager.currentTheme = .system
        }
    }
}

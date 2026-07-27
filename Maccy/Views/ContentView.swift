import Defaults
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      KeyHandlingView(searchQuery: searchBinding, searchFocused: $searchFocused) {
        VStack(spacing: 0) {
          TodosTabBarView()

          SlideoutView(controller: appState.preview) {
            popupMainContent
          } slideout: {
            if appState.activeTab == .clipboard {
              SlideoutContentView()
            } else {
              TodosSlideoutContentView()
            }
          }
          .frame(minHeight: 0)
          .layoutPriority(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .task {
        try? await appState.history.load()
        try? appState.todos.load()
        if let tab = AppTab(rawValue: Defaults[.defaultAppTab]) {
          appState.setActiveTab(tab)
        }
      }
    }
    .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
    .animation(.easeInOut(duration: 0.2), value: appState.activeTab)
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .background
      }
    }
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: {
        appState.activeTab == .clipboard ? appState.history.searchQuery : appState.todos.searchQuery
      },
      set: { value in
        if appState.activeTab == .clipboard {
          appState.history.searchQuery = value
        } else {
          appState.todos.searchQuery = value
        }
      }
    )
  }

  @ViewBuilder
  private var popupMainContent: some View {
    if appState.activeTab == .clipboard {
      PopupSearchHeaderView(
        searchFocused: $searchFocused,
        searchQuery: $appState.history.searchQuery,
        placeholder: "search_placeholder",
        controller: appState.preview
      )

      VStack(alignment: .leading, spacing: 0) {
        HistoryListView(
          searchQuery: $appState.history.searchQuery,
          searchFocused: $searchFocused
        )

        FooterView(footer: appState.footer)
      }
      .animation(.default.speed(3), value: appState.history.items)
      .animation(.default.speed(3), value: appState.history.pasteStack?.id)
      .padding(.horizontal, Popup.horizontalPadding)
      .onAppear {
        searchFocused = true
      }
      .onMouseMove {
        appState.navigator.isKeyboardNavigating = false
      }
    } else {
      PopupSearchHeaderView(
        searchFocused: $searchFocused,
        searchQuery: $appState.todos.searchQuery,
        placeholder: LocalizedStringKey(
          String(localized: "SearchTodos", table: "Todos")
        ),
        controller: appState.preview
      )

      VStack(alignment: .leading, spacing: 0) {
        TodosToolbarView()
        TodosListView(searchFocused: $searchFocused)
          .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
      }
      .padding(.horizontal, Popup.horizontalPadding)
      .onAppear {
        appState.prepareTodosTab()
        searchFocused = true
      }
      .onMouseMove {
        appState.todos.isKeyboardNavigating = false
      }
    }
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}

import Defaults
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var scenePhase: ScenePhase = .background
  
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()

  @FocusState private var searchFocused: Bool
  @Default(.previewDelay) private var previewDelay

  var body: some View {
    ZStack {
      VisualEffectView(material: .popover, blendingMode: .behindWindow)

      VStack(alignment: .leading) {
        KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
          HeaderView(
            searchFocused: $searchFocused,
            searchQuery: $appState.history.searchQuery
          )

          ScrollView {
            ScrollViewReader { proxy in
              HistoryListView(
                searchQuery: $appState.history.searchQuery,
                searchFocused: $searchFocused
              )
              .onChange(of: appState.selection) {
                if let selection = appState.selection {
                  proxy.scrollTo(selection)
                }
              }
              .onChange(of: scenePhase) {
                if scenePhase == .active {
                  searchFocused = true
                  appState.selection = appState.history.firstUnpinnedItem?.id
                  Task {
                    proxy.scrollTo(appState.history.items.first?.id)
                  }
                } else {
                  HistoryItemDecorator.previewThrottler.minimumDelay = Double(previewDelay) / 1000
                  modifierFlags.flags = []
                }
              }
            }
          }
          .contentMargins(.leading, 10, for: .scrollIndicators)

          FooterView(footer: appState.footer)
        }
      }
      .animation(.default, value: appState.history.items)
      .padding([.bottom, .horizontal], 5)
      .task { try? await appState.history.load() }
    }
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if ($0.object as? NSWindow)?.title == Bundle.main.bundleIdentifier {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if ($0.object as? NSWindow)?.title == Bundle.main.bundleIdentifier {
        scenePhase = .background
      }
    }
  }
}

#Preview {
  let config = ModelConfiguration(
    url: URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  )
  let container = try! ModelContainer(for: HistoryItem.self, configurations: config)

  return ContentView()
    .modelContainer(container)
}

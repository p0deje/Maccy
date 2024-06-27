import SwiftData
import SwiftUI
import Settings

@main
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
//    NSApp.setActivationPolicy(.accessory)

    Clipboard.shared.onNewCopy(HistoryItemsViewModel.shared.add)
  }

  var body: some Scene {
    Window("Maccy", id: "org.p0deje.Maccy") {
      ContentView1()
    }
    .defaultSize(.init(width: 300, height: 50))
    .windowStyle(.hiddenTitleBar)
    
  }
}


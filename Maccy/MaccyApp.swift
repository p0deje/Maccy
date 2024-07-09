import Defaults
import KeyboardShortcuts
import Settings
import SwiftData
import SwiftUI

//@MainActor
//final class AppState: ObservableObject {
//  @Published var popupShown = true
//
//  init() {
//    KeyboardShortcuts.onKeyUp(for: .popup) { [self] in
//      if !popupShown {
//        NSApp.  activate()
//      }
//      popupShown.toggle()
//    }
//  }
//}

@main
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.scenePhase) private var scenePhase

//  @StateObject var appState = AppState()

  init() {
    //    NSApp.setActivationPolicy(.accessory)

//    Task { [self]
//      KeyboardShortcuts.onKeyUp(for: .popup) {
//        self.popupShown.toggle()
//      }
//    }
    Clipboard.shared.onNewCopy(HistoryItemsViewModel.shared.add)
  }

  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showMenuIcon
  @Default(.showRecentCopyInMenuBar) private var showRecentCopyInMenuBar

  var body: some Scene {
//    Window("maccy", id: "org.p0deje.Maccy") {
//      Text("")
//      .floatingPanel(isPresented: $appState.popupShown) {
//        ContentView1()
//      }
//    }
//    .defaultSize(width: 0, height: 0)
    MenuBarExtra(isInserted: $showMenuIcon) {
      Text("")
//        .floatingPanel(isPresented: $appState.popupShown) {
//          ContentView1()
//        }
    } label: {
      HStack {
        if showRecentCopyInMenuBar {
          Text(HistoryItemsViewModel.shared.historyItems.first?.title ?? "")
            .frame(maxWidth: 50)
        }
        Image(nsImage: menuIcon.image)
      }
    }
  }
}

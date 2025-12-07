import SwiftUI
import SwiftData

@main
struct MaccyiOSApp: App {
  var body: some Scene {
    WindowGroup {
      iOSContentView()
        .modelContainer(Storage.shared.container)
    }
  }
}

import SwiftUI

/// The SwiftUI app entry point.
///
/// All real UI is presented through `NSPanel` windows owned by `AppDelegate`,
/// not SwiftUI scenes. SwiftUI requires at least one scene, so a hidden
/// `MenuBarExtra` is used to satisfy that requirement without contributing UI.
@main
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  /// Drives the always-hidden `MenuBarExtra` that exists only to satisfy the
  /// scene requirement.
  @State private var hiddenMenu: Bool = false

  var body: some Scene {
    MenuBarExtra("", isInserted: $hiddenMenu) {
      EmptyView()
    }
  }
}

import SwiftUI

private struct ExcludeFromWindowMovableByBackgroundModifier: ViewModifier {
  @Environment(AppState.self) private var appState

  func body(content: Content) -> some View {
    content
      .onHover { inside in
        if let window = appState.appDelegate?.panel {
          window.isMovableByWindowBackground = !inside
        }
      }
      .onDisappear {
        appState.appDelegate?.panel?.isMovableByWindowBackground = true
      }
  }
}

extension View {
  func excludeFromWindowMovableByBackground() -> some View {
    self.modifier(
      ExcludeFromWindowMovableByBackgroundModifier()
    )
  }
}

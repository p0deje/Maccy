import SwiftUI

private struct HoverSelectionModifier: ViewModifier {
  @Environment(AppState.self) private var appState
  var id: UUID

  func body(content: Content) -> some View {
    content.onHover { hovering in
      if hovering {
        if !appState.isKeyboardNavigating && !appState.isMultiSelectInProgress {
          appState.selectWithoutScrolling(id: id)
        } else {
          appState.hoverSelectionWhileKeyboardNavigating = id
        }
      }
    }
  }
}

extension View {
  func hoverSelectionId(_ id: UUID) -> some View {
    modifier(HoverSelectionModifier(id: id))
  }
}

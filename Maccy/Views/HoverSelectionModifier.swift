import SwiftUI

private struct HoverSelectionModifier: ViewModifier {
  @Environment(AppState.self) private var appState
  var id: UUID

  func body(content: Content) -> some View {
    content.onHover { hovering in
      guard hovering else { return }
      if appState.navigator.leadSelection == id {
        if appState.navigator.hoverSelectionWhileKeyboardNavigating != nil {
          appState.navigator.hoverSelectionWhileKeyboardNavigating = nil
        }
        return
      }

      if !appState.navigator.isKeyboardNavigating && !appState.navigator.isMultiSelectInProgress {
        appState.navigator.selectWithoutScrolling(id: id)
      } else if appState.navigator.hoverSelectionWhileKeyboardNavigating != id {
        appState.navigator.hoverSelectionWhileKeyboardNavigating = id
      }
    }
  }
}

extension View {
  func hoverSelectionId(_ id: UUID) -> some View {
    modifier(HoverSelectionModifier(id: id))
  }
}

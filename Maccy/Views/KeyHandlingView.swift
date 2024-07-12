import Sauce
import SwiftUI

struct KeyHandlingView<Content: View>: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool
  @ViewBuilder let content: () -> Content

  @Environment(AppState.self) private var appState

  var body: some View {
    content()
      .onKeyPress { press in
        switch KeyChord(press.key, press.modifiers) {
        case .clearHistory:
          // TODO: Confirmation
          appState.history.clear()
          return .handled
        case .clearHistoryAll:
          // TODO: Confirmation
          appState.history.clearAll()
          return .handled
        case .clearSearch:
          searchQuery = ""
          return .handled
        case .deleteCurrentItem:
          if let item = appState.history.selectedItem {
            appState.highlightNext()
            appState.history.delete(item)
          }
          return .handled
        case .deleteOneCharFromSearch:
          searchFocused = true
          let _ = searchQuery.popLast()
          return .handled
        case .deleteLastWordFromSearch:
          searchFocused = true
          searchQuery =
          searchQuery
            .split(separator: " ")
            .dropLast()
            .joined(separator: " ")
          return .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightNext()
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightPrevious()
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          appState.history.togglePin(appState.history.selectedItem)
          return .handled
        case .selectCurrentItem:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          if appState.history.selectedItem != nil {
            appState.history.select(appState.history.selectedItem)
          } else if let item = appState.footer.selectedItem {
            if item.confirmation != nil {
              item.showConfirmation = true
            } else {
              item.action()
            }
          } else {
            Clipboard.shared.copy(searchQuery)
            searchQuery = ""
          }
          return .handled
        default:
          ()
        }

        if let item = appState.history.pressedShortcutItem {
          appState.selection = item.id
          Task {
            try! await Task.sleep(for: .milliseconds(50))
            appState.history.select(item)
          }
          return .handled
        }

        if let event = NSApp.currentEvent, !searchFocused {
          if let key = Sauce.shared.key(for: Int(event.keyCode)),
             KeyChord.keysToSkip.contains(key) {
            return .ignored
          }

          if let character = Sauce.shared.character(for: Int(event.keyCode), cocoaModifiers: event.modifierFlags) {
            searchFocused = true
            Task {
              try! await Task.sleep(for: .milliseconds(5))
              searchQuery.append(character)
            }
            return .handled
          }
        }

        return .ignored
      }
  }
}

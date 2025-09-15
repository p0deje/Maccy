import Sauce
import SwiftUI

struct KeyHandlingView<Content: View>: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool
  @ViewBuilder let content: () -> Content

  @Environment(AppState.self) private var appState

  var body: some View {
    content()
      .onKeyPress { _ in
        // Unfortunately, key presses don't allow access to
        // key code and don't properly work with multiple inputs,
        // so pressing ⌘, on non-English layout doesn't open
        // preferences. Stick to NSEvent to fix this behavior.
        switch KeyChord(NSApp.currentEvent) {
        case .clearHistory:
          if let item = appState.footer.items.first(where: { $0.title == "clear" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearHistoryAll:
          if let item = appState.footer.items.first(where: { $0.title == "clear_all" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearSearch:
          searchQuery = ""
          return .handled
        case .deleteCurrentItem:
          if appState.navigator.pasteStackSelected {
            appState.history.interruptPasteStack()
            appState.navigator.highlightFirst()
          } else if let leadItem = appState.navigator.leadHistoryItem,
            let item = appState.history.visibleItems.nearest(
              to: leadItem,
              where: { !$0.isSelected }
            ) {
            withTransaction(Transaction()) {
              appState.navigator.selection.forEach { _, item in
                appState.history.delete(item)
              }
              appState.navigator.select(item: item)
            }
          }
          return .handled
        case .deleteOneCharFromSearch:
          searchFocused = true
          _ = searchQuery.popLast()
          return .handled
        case .deleteLastWordFromSearch:
          searchFocused = true
          let newQuery = searchQuery.split(separator: " ").dropLast().joined(separator: " ")
          if newQuery.isEmpty {
            searchQuery = ""
          } else {
            searchQuery = "\(newQuery) "
          }

          return .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightNext()
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightPrevious()
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.navigator.highlightFirst()
          return .handled
        case .extendToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          appState.navigator.extendHighlightToNext()
          return .handled
        case .extendToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          appState.navigator.extendHighlightToLast()
          return .handled
        case .extendToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          appState.navigator.extendHighlightToPrevious()
          return .handled
        case .extendToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          appState.navigator.extendHighlightToFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          withTransaction(Transaction()) {
            appState.navigator.selection.forEach { _, item in
              appState.history.togglePin(item)
            }
          }
          return .handled
        case .selectCurrentItem:
          appState.select()
          return .handled
        case .close:
          appState.popup.close()
          return .handled
        default:
          ()
        }

        if let item = appState.history.pressedShortcutItem {
          appState.navigator.select(item: item)
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            appState.history.select(item)
          }
          return .handled
        }

        return .ignored
      }
  }
}

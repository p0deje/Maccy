import Sauce
import Defaults
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

        if searchFocused {
          // Ignore input when candidate window is open
          // https://stackoverflow.com/questions/73677444/how-to-detect-the-candidate-window-when-using-japanese-keyboard
          if let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient,
             inputClient.hasMarkedText() {
            return .ignored
          }
        }

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
            appState.removePasteStack()
          } else {
            appState.deleteSelection()
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

          // ⌃K also maps to moveToPrevious (vim-style). When already at the first
          // item — or when there are no items to move to — keep macOS kill-to-end-of-line.
          // https://github.com/p0deje/Maccy/issues/1055
          if isControlK(NSApp.currentEvent), shouldUseControlKForKillToEnd {
            searchFocused = true
            deleteSearchTextToEndOfLine()
            return .handled
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
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToNext()
          return .handled
        case .extendToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToLast()
          return .handled
        case .extendToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToPrevious()
          return .handled
        case .extendToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }
          guard AppState.shared.multiSelectionEnabled else {
            return .ignored
          }
          appState.navigator.extendHighlightToFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          appState.togglePin()
          return .handled
        case .selectCurrentItem:
          appState.select()
          return .handled
        case .close:
          appState.popup.close()
          return .handled
        case .togglePreview:
          appState.preview.togglePreview()
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

  private var shouldUseControlKForKillToEnd: Bool {
    // No visible results: navigation is a no-op, so prefer kill-to-end in search.
    guard let first = appState.history.firstVisibleItem else {
      return true
    }

    return appState.navigator.leadHistoryItem?.id == first.id
  }

  private func isControlK(_ event: NSEvent?) -> Bool {
    guard let event else {
      return false
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    guard modifierFlags == .control else {
      return false
    }

    return Sauce.shared.key(for: Int(event.keyCode)) == .k
  }

  // Mutate `searchQuery` directly (like ⌃H/⌃W). Editing the field editor alone is
  // overwritten by SwiftUI from the unchanged binding.
  private func deleteSearchTextToEndOfLine() {
    guard let text = searchFieldEditor() else {
      return
    }

    let string = text.string as NSString
    let cursor = min(text.selectedRange.location, string.length)
    searchQuery = string.substring(to: cursor)
  }

  private func searchFieldEditor() -> NSText? {
    if let text = NSApp.keyWindow?.firstResponder as? NSText {
      return text
    }

    for window in NSApp.windows where window.isVisible {
      if let text = window.firstResponder as? NSText {
        return text
      }

      guard let contentView = window.contentView,
            let field = findTextField(in: contentView) else {
        continue
      }

      window.makeFirstResponder(field)
      return window.fieldEditor(true, for: field)
    }

    return nil
  }

  private func findTextField(in view: NSView) -> NSTextField? {
    if let textField = view as? NSTextField {
      return textField
    }

    for subview in view.subviews {
      if let textField = findTextField(in: subview) {
        return textField
      }
    }

    return nil
  }
}

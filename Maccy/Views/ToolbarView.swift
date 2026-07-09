import Defaults
import KeyboardShortcuts
import SwiftUI

private struct KeyboardShortcutHelpModifier: ViewModifier {
  // nil for buttons with no keyboard shortcut (e.g. CopyExtractedText) - they still get
  // help + accessibilityLabel from `key`, just without a shortcut description substituted in.
  let name: KeyboardShortcuts.Name?
  let key: String
  let tableName: String
  let comment: String = ""
  let replacementKey: String

  // Also used as the accessibilityLabel below: without this, several buttons across the app
  // (Pin, Delete, toggle preview, copy extracted text) were relying on the bare SF Symbol's
  // own generic system description, which says nothing about what the button actually does.
  private var resolvedText: Text? {
    let localized = NSLocalizedString(key, tableName: tableName, comment: comment)
    guard let name else {
      return Text(localized)
    }
    guard let shortcut = KeyboardShortcuts.Shortcut(name: name) else {
      return nil
    }
    return Text(localized.replacingOccurrences(of: "{\(replacementKey)}", with: shortcut.description))
  }

  func body(content: Content) -> some View {
    if let resolvedText {
      content
        .help(resolvedText)
        .accessibilityLabel(resolvedText)
    } else {
      content
    }
  }
}

struct ToolbarButton<Label: View>: View {
  @Environment(AppState.self) private var appState

  let action: @MainActor () -> Void
  let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
    }
    .buttonStyle(.plain)
    .frame(height: 23)
    .onHover(perform: { inside in
      if let window = appState.appDelegate?.panel {
        window.isMovableByWindowBackground = !inside
      }
    })
  }

  func shortcutKeyHelp(
    name: KeyboardShortcuts.Name? = nil,
    key: String,
    tableName: String,
    replacementKey: String = ""
  ) -> some View {
    self.modifier(
      KeyboardShortcutHelpModifier(
        name: name,
        key: key,
        tableName: tableName,
        replacementKey: replacementKey
      )
    )
  }

}

struct ToolbarView: View {
  @State private var appState = AppState.shared

  @Namespace var unionNamespace

  enum Section: Hashable {
    case itemOptions
  }

  private var shouldUnpin: Bool {
    return appState.navigator.selection.items.allSatisfy { $0.isPinned }
  }

  private var pinActionDisabled: Bool {
    return appState.navigator.selection.items.contains { $0.isPinned }
      && appState.navigator.selection.items.contains { !$0.isPinned }
  }

  private var selectedImageItem: HistoryItemDecorator? {
    guard appState.navigator.selection.count == 1,
          let item = appState.navigator.selection.first,
          item.hasImage else {
      return nil
    }

    return item
  }

  private var selectedImageText: String? {
    guard let item = selectedImageItem else {
      return nil
    }

    let text = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : item.title
  }

  var body: some View {
    HStack {
      if !appState.navigator.selection.isEmpty {
        Spacer()

        if selectedImageItem != nil {
          ToolbarButton {
            guard let selectedImageText else { return }
            Clipboard.shared.copyInMaccy(selectedImageText)
          } label: {
            Image(systemName: "text.viewfinder")
          }
          // Icon-only button that used to rely on the SF Symbol's own generic system
          // description ("text.viewfinder") - said nothing about what it actually does.
          .shortcutKeyHelp(key: "CopyExtractedText", tableName: "PreviewItemView")
          .disabled(selectedImageText == nil)
        }

        ToolbarButton {
          withAnimation {
            appState.togglePin()
          }
        } label: {
          if (appState.navigator.selection.items.allSatisfy { $0.isPinned }) {
            Image(systemName: "pin.slash")
          } else {
            Image(systemName: "pin")
          }
        }
        // Same bug as above: bare "pin"/"pin.slash" SF Symbols read as generic system
        // descriptions ("pin marker"/"slashed pin") instead of the actual toggle action.
        .shortcutKeyHelp(
          name: .pin,
          key: shouldUnpin ? "UnpinKey" : "PinKey",
          tableName: "PreviewItemView",
          replacementKey: "pinKey"
        )
        .disabled(pinActionDisabled)

        ToolbarButton {
          appState.deleteSelection()
        } label: {
          Image(systemName: "trash")
        }
        .shortcutKeyHelp(
          name: .delete,
          key: "DeleteKey",
          tableName: "PreviewItemView",
          replacementKey: "deleteKey"
        )
      }

      if appState.navigator.pasteStackSelected {
        ToolbarButton {
          appState.removePasteStack()
        } label: {
          Image(systemName: "stop")
        }
        .accessibilityLabel(Text("toolbar_remove_paste_stack_action"))
      }
    }
  }
}

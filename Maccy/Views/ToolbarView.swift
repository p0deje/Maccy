import KeyboardShortcuts
import SwiftUI

/// Attaches a tooltip that names the currently bound keyboard shortcut, if any
/// is registered for the given `KeyboardShortcuts.Name`.
private struct KeyboardShortcutHelpModifier: ViewModifier {
  let name: KeyboardShortcuts.Name
  let key: String
  let tableName: String
  let comment: String = ""
  let replacementKey: String

  func body(content: Content) -> some View {
    if let shortcut = KeyboardShortcuts.Shortcut(name: name) {
      content
        .help(
          Text(
            NSLocalizedString(key, tableName: tableName, comment: comment)
              .replacingOccurrences(
                of: "{\(replacementKey)}",
                with: shortcut.description
              )
          )
        )
    } else {
      content
    }
  }
}

/// A plain-styled toolbar button of fixed height that releases window dragging
/// while hovered.
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

  /// Attaches a keyboard-shortcut tooltip to this button.
  func shortcutKeyHelp(
    name: KeyboardShortcuts.Name,
    key: String,
    tableName: String,
    replacementKey: String
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

/// The slideout toolbar: context-sensitive pin/delete actions for the current
/// selection, plus a remove-paste-stack action when a paste stack is selected.
struct ToolbarView: View {
  @State private var appState = AppState.shared

  @Namespace var unionNamespace

  /// Matched-transition namespaces grouped under the toolbar.
  enum Section: Hashable {
    case itemOptions
  }

  /// Whether every selected item is already pinned (so the action would unpin).
  private var shouldUnpin: Bool {
    return appState.navigator.selection.items.allSatisfy { $0.isPinned }
  }

  /// Whether the pin action is unavailable because the selection mixes pinned
  /// and unpinned items.
  private var pinActionDisabled: Bool {
    return appState.navigator.selection.items.contains { $0.isPinned }
      && appState.navigator.selection.items.contains { !$0.isPinned }
  }

  var body: some View {
    HStack {
      if !appState.navigator.selection.isEmpty {
        Spacer()

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
      }
    }
  }
}

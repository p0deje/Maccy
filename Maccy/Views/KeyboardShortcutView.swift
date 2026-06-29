import SwiftUI

/// Renders a keyboard shortcut as separate modifier glyphs followed by the key character.
struct KeyboardShortcutView: View {
  var shortcut: KeyShortcut?

  /// The modifier portion of the shortcut description, excluding the trailing key character.
  var modifiers: String {
    if var shortcut = shortcut?.description {
      _ = shortcut.popLast()
      return shortcut
    }
    return ""
  }

  /// The final key character of the shortcut, or an empty string when absent.
  var character: String {
    return shortcut?.description.last?.description ?? ""
  }

  var body: some View {
    HStack(spacing: 1) {
      ForEach(Array(modifiers.unicodeScalars), id: \.self) { scalar in
          Text(String(scalar))
      }
      Text(character).frame(width: 12, alignment: .center)
    }
    .lineLimit(1)
    .opacity(character.isEmpty ? 0 : 0.7)
  }
}

#Preview {
  List {
    KeyboardShortcutView(shortcut: KeyShortcut(key: .a, modifierFlags: [.command]))
    KeyboardShortcutView(shortcut: KeyShortcut(key: .w))
    KeyboardShortcutView(shortcut: KeyShortcut(key: .one, modifierFlags: [.command]))
    KeyboardShortcutView(shortcut: KeyShortcut(key: .two, modifierFlags: [.command]))
    KeyboardShortcutView()

    KeyboardShortcutView(shortcut: KeyShortcut(key: .delete, modifierFlags: [.command, .option, .control, .shift]))
    KeyboardShortcutView(shortcut: KeyShortcut(key: .c, modifierFlags: [.command, .option]))
  }
}

import Defaults
import SwiftUI

struct ListItemView<Title: View>: View {
  var id: UUID
  var image: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var help: LocalizedStringKey?
  @ViewBuilder var title: () -> Title

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    HStack(spacing: 0) {
      if let image {
        Image(nsImage: image)
          .accessibilityIdentifier("copy-history-item")
          .padding(.leading, 10)
          .padding(.vertical, 5)
      }
      ListItemTitleView(attributedTitle: attributedTitle, title: title)
      Spacer()
      if !shortcuts.isEmpty {
        ZStack {
          ForEach(shortcuts) { shortcut in
            KeyboardShortcutView(shortcut: shortcut)
              .opacity(shortcut.isVisible(shortcuts, modifierFlags.flags) ? 1 : 0)
          }
        }
        .padding(.trailing, 10)
      } else {
        Spacer()
          .frame(width: 50)
      }
    }
    .frame(minHeight: 22)
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    .background(isSelected ? Color.accentColor.opacity(0.8) : .clear)
    .clipShape(.rect(cornerRadius: 4))
    .onHover { hovering in
      if hovering {
        if !appState.isKeyboardNavigating {
          appState.selection = id
        } else {
          appState.hoverSelectionWhileKeyboardNavigating = id
        }
      }
    }
    .help(help ?? "")
  }
}

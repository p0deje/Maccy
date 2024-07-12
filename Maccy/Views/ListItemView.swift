import Defaults
import SwiftUI

struct ListItemView: View {
  var id: UUID
  var image: NSImage? = nil
  var attributedTitle: AttributedString? = nil
  var title: String
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var help: LocalizedStringKey? = nil

  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Default(.imageMaxHeight) private var imageMaxHeight

  var body: some View {
    HStack {
      if let image {
        Image
          .thumbnailImage(image, maxHeight: imageMaxHeight)
          .padding(.leading, 10)
          .padding(.vertical, 5)
      } else {
        if let attributedTitle {
          Text(attributedTitle)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 10)
        } else {
          Text(LocalizedStringKey(title))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 10)
        }
      }
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
        appState.selection = id
      }
    }
    .help(help ?? "")
  }
}

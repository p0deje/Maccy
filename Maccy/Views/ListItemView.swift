import Defaults
import SwiftUI

struct ListItemView<Title: View>: View {
  var id: UUID
  var appIcon: ApplicationImage?
  var image: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var help: LocalizedStringKey?
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  var body: some View {
    HStack(spacing: 0) {
      if showIcons, let appIcon {
        VStack {
          Spacer(minLength: 0)
          Image(nsImage: appIcon.nsImage)
            .resizable()
            .frame(width: 15, height: 15)
          Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.vertical, 5)
      }

      if let image {
        Image(nsImage: image)
          .accessibilityIdentifier("copy-history-item")
          .padding(.leading, showIcons ? 5 : 10)
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      } else {
        ListItemTitleView(attributedTitle: attributedTitle, title: title)
          .padding(.leading, showIcons ? 0 : 5)
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
        if !appState.isKeyboardNavigating {
          appState.selectWithoutScrolling(id)
        } else {
          appState.hoverSelectionWhileKeyboardNavigating = id
        }
      }
    }
    .help(help ?? "")
  }
}

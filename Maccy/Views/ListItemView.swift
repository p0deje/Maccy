import Defaults
import SwiftUI

struct ListItemView<Title: View>: View {
  var id: UUID
  #if os(macOS)
  var appIcon: ApplicationImage?
  #endif
  var image: PlatformImage?
  var accessoryImage: PlatformImage?
  var attributedTitle: AttributedString?
  #if os(macOS)
  var shortcuts: [KeyShortcut]
  #endif
  var isSelected: Bool
  var help: LocalizedStringKey?
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Environment(AppState.self) private var appState
  #if os(macOS)
  @Environment(ModifierFlags.self) private var modifierFlags
  #endif

  var body: some View {
    HStack(spacing: 0) {
      #if os(macOS)
      if showIcons, let appIcon {
        VStack {
          Spacer(minLength: 0)
          Image(nsImage: appIcon.nsImage)
            .resizable()
            .frame(width: 15, height: 15)
          Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
      }
      #endif

      Spacer()
        .frame(width: showIcons ? 5 : 10)

      if let accessoryImage {
        #if os(macOS)
        Image(nsImage: accessoryImage)
        #else
        Image(uiImage: accessoryImage)
        #endif
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      }

      if let image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
          .accessibilityIdentifier("copy-history-item")
          .padding(.trailing, 5)
          .padding(.vertical, 5)
      } else {
        ListItemTitleView(attributedTitle: attributedTitle, title: title)
          .padding(.trailing, 5)
      }

      Spacer()

      #if os(macOS)
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
      #else
      Spacer()
        .frame(width: 10)
      #endif
    }
    #if os(macOS)
    .frame(minHeight: Popup.itemHeight)
    #else
    .frame(minHeight: 44)
    #endif
    .id(id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isSelected ? Color.white : .primary)
    // macOS 26 broke hovering if no background is present.
    // The slight opcaity white background is a workaround
    #if os(macOS)
    .background(isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001))
    .clipShape(.rect(cornerRadius: Popup.cornerRadius))
    .onHover { hovering in
      if hovering {
        if !appState.isKeyboardNavigating {
          appState.selectWithoutScrolling(id)
        } else {
          appState.hoverSelectionWhileKeyboardNavigating = id
        }
      }
    }
    #else
    .background(isSelected ? Color.accentColor.opacity(0.8) : .clear)
    .clipShape(.rect(cornerRadius: 8))
    #endif
    .help(help ?? "")
  }
}

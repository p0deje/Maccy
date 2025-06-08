import Defaults
import SwiftUI

struct ListItemView<Title: View>: View {
  var id: UUID
  var appIcon: ApplicationImage?
  var image: NSImage?
  var accessoryImage: NSImage?
  var attributedTitle: AttributedString?
  var shortcuts: [KeyShortcut]
  var isSelected: Bool
  var help: LocalizedStringKey?
  @ViewBuilder var title: () -> Title

  @Default(.showApplicationIcons) private var showIcons
  @Default(.showDeleteButton) private var showDeleteButton
  @Default(.showPreviewButton) private var showPreviewButton
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags

  private var currentItemHeight: CGFloat {
    if image != nil || accessoryImage != nil {
      return 50 
    } else {
     return 50 
    }
  }

  private var imageDimension: CGFloat {
    return currentItemHeight - 10 // Results in 5px margin on each side
  }

  var body: some View {
    HStack(spacing: 0) {
      if showIcons, let appIcon, image == nil, accessoryImage == nil { // <-- Add conditions here
        VStack {
          Spacer(minLength: 0)
          Image(nsImage: appIcon.nsImage)
            .resizable()
            .frame(width: imageDimension, height: imageDimension)
          Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.vertical, 5)
      }

      Spacer()
        .frame(width: showIcons ? 5 : 10)

      if let accessoryImage {
        VStack {
          Spacer(minLength: 0)
          Image(nsImage: accessoryImage)
            .accessibilityIdentifier("copy-history-item")
            .frame(width: imageDimension, height: imageDimension)
          Spacer(minLength: 0)
        }
        .padding(.trailing, 5)
      }

      // Display file icon if available
      if let image {
        VStack {
          Spacer(minLength: 0)
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageDimension, height: imageDimension)
            .accessibilityIdentifier("copy-history-item")
          Spacer(minLength: 0)
        }
        .padding(.trailing, 5)
      }
      
      // Always display title/text (alongside icon if present)
      ListItemTitleView(attributedTitle: attributedTitle, title: title)
        .padding(.trailing, 5)
      Spacer()

      if !shortcuts.isEmpty {
        VStack {
          Spacer(minLength: 0)
          ZStack {
            ForEach(shortcuts) { shortcut in
              KeyboardShortcutView(shortcut: shortcut)
                .opacity(shortcut.isVisible(shortcuts, modifierFlags.flags) ? 1 : 0)
            }
          }
          Spacer(minLength: 0)
        }
        .padding(.trailing, 10)
      } else {
        Spacer()
          .frame(width: 50)
      }

      if showPreviewButton {
        Button {
          if let itemDecorator = appState.history.items.first(where: { $0.id == id }) {
            itemDecorator.showPreview.toggle()
          }
        } label: {
          Image(systemName: "eye")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 5) // Adjusted padding to make space for the new button
      }

      if showDeleteButton {
        Button {
          if let itemToDelete = appState.history.items.first(where: { $0.id == id }) {
            appState.history.delete(itemToDelete)
          }
        } label: {
          Image(systemName: "trash")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 10)
      }

    }
    .frame(height: currentItemHeight)
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

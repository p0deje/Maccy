import Defaults
import SwiftUI

struct HistoryItemView: View {
    var item: HistoryItemDecorator

    @Default(.showApplicationIcons) private var showIcons
    @Default(.showDeleteButton) private var showDeleteButton
    @Default(.showPreviewButton) private var showPreviewButton
    @Environment(AppState.self) private var appState

    private var imageDimension: CGFloat {
        return 40  // 50 - 10 padding
    }

    var body: some View {
        BaseItemView(
            id: item.id,
            shortcuts: item.shortcuts,
            isSelected: item.isSelected,
            help: LocalizedStringKey(item.title)
        ) {
            HStack(spacing: 0) {
                // App Icon
                if showIcons, item.thumbnailImage == nil, item.fileIcon == nil {
                    VStack {
                        Spacer(minLength: 0)
                        Image(nsImage: item.applicationImage.nsImage)
                            .resizable()
                            .frame(width: imageDimension, height: imageDimension)
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, 5)
                }

                // File Icon (for files)
                if let fileIcon = item.fileIcon {
                    VStack {
                        Spacer(minLength: 0)
                        Image(nsImage: fileIcon)
                            .accessibilityIdentifier("copy-history-item")
                            .frame(width: imageDimension, height: imageDimension)
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, 5)
                }

                // Content Image (thumbnails)
                if let image = item.thumbnailImage {
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

                // Title/Text Content
                ListItemTitleView(attributedTitle: item.attributedTitle) {
                    Text(item.title)
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 5) {
                    if showPreviewButton {
                        Button {
                            item.showPreview.toggle()
                        } label: {
                            Image(systemName: "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if showDeleteButton {
                        Button {
                            appState.history.delete(item)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, showDeleteButton || showPreviewButton ? 5 : 0)
            }
        }
        .onTapGesture {
            appState.history.select(item)
        }
        .popover(isPresented: .constant(item.showPreview), arrowEdge: .trailing) {
            PreviewItemView(item: item)
                .frame(idealWidth: 520, idealHeight: 750)
        }
        .onHover { hovering in
            if hovering {
                if !appState.isKeyboardNavigating {
                    appState.selectWithoutScrolling(item.id)
                } else {
                    appState.hoverSelectionWhileKeyboardNavigating = item.id
                }
            }
        }
    }
}

// MARK: - BaseItemView
struct BaseItemView<Content: View>: View {
    var id: UUID
    var shortcuts: [KeyShortcut]
    var isSelected: Bool
    var help: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    @Environment(ModifierFlags.self) private var modifierFlags

    private let itemHeight: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            content()
                .padding(.leading, 10)
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
        }
        .frame(height: itemHeight)
        .id(id)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? ThemeColors.selectedTextColor : ThemeColors.primaryTextColor)
        .background {
            if isSelected {
                ThemeColors.selectedBackgroundColor
            } else {
                Color.clear
            }
        }
        .clipShape(.rect(cornerRadius: 4))
        .help(help ?? "")
    }
}

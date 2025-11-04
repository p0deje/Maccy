import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator

  @Environment(AppState.self) private var appState
  @State private var isHovering: Bool = false

  var body: some View {
    ZStack(alignment: .trailing) {
      ListItemView(
        id: item.id,
        appIcon: item.applicationImage,
        image: item.thumbnailImage,
        accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
        attributedTitle: item.attributedTitle,
        shortcuts: item.shortcuts,
        isSelected: item.isSelected
      ) {
        Text(verbatim: item.title)
      }

      if item.isUnpinned {
        HStack(spacing: 6) {
          // Pin quick action
          Button(action: { appState.history.togglePin(item) }) {
            Image(systemName: "pin")
          }
          .help("Pin")
          .buttonStyle(.borderless)
          .controlSize(.small)

          // Separator only if numeric shortcuts are present (first 9 visible unpinned items)
          if !item.shortcuts.isEmpty {
            Rectangle()
              .frame(width: 1, height: 14)
              .foregroundStyle(.separator)
              .padding(.leading, 4)
          }
        }
        .opacity(isHovering ? 1 : 0)
        .padding(.trailing, 50) // leave room for shortcut badges on the far right
      }
    }
    .onTapGesture { appState.history.select(item) }
    .onHover { hovering in isHovering = hovering }
    .popover(isPresented: $item.showPreview, arrowEdge: .trailing) { PreviewItemView(item: item) }
  }
}

import Defaults
import SwiftUI

struct HistoryItemView: View {
    @Bindable var item: HistoryItemDecorator

    @Environment(AppState.self) private var appState

    var body: some View {
        ListItemView(
            id: item.id,
            appIcon: item.applicationImage,
            image: item.thumbnailImage ?? item.fileIcon,
            accessoryImage: (item.thumbnailImage != nil || item.fileIcon != nil)
                ? nil : ColorImage.from(item.title),
            attributedTitle: item.attributedTitle,
            shortcuts: item.shortcuts,
            isSelected: item.isSelected
        ) {
            Text(verbatim: item.text.isEmpty ? item.title : item.text)
        }
        .onTapGesture {
            appState.history.select(item)
        }
        .popover(isPresented: $item.showPreview, arrowEdge: .trailing) {
            PreviewItemView(item: item)
                .frame(idealWidth: 520, idealHeight: 750)  // Set ideal size for popover content
        }
    }
}

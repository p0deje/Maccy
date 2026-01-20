import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState

  private var selectionCount: Int {
    return appState.navigator.selection.count
  }

  @ViewBuilder
  private func cardView(
    for item: HistoryItemDecorator,
    leadItem: HistoryItemDecorator
  ) -> some View {
    if item == leadItem {
      PreviewItemView(item: leadItem)
        .onAppear {
          leadItem.ensurePreviewImage()
        }
        .padding()
    } else {
      Color.clear
    }
  }

  var body: some View {
    VStack(alignment: .center) {
      ToolbarView()
      if let leadItem = appState.navigator.leadHistoryItem {
        if selectionCount > 1 {
          StackedCardsView(
            items: appState.navigator.selection.items,
            maxCount: 5
          ) { item in
            cardView(for: item, leadItem: leadItem)
          }
        } else {
          PreviewItemView(item: leadItem)
        }
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected
      {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }

}

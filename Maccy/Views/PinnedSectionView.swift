import SwiftUI

struct PinnedSectionView: View {
  @Environment(AppState.self) private var appState

  private var pinnedItems: [HistoryItemDecorator] {
    appState.history.pinnedItems.filter(\.isVisible)
  }
  private var unpinnedItemsVisible: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }
  private var showPinsSeparator: Bool {
    !pinnedItems.isEmpty && !unpinnedItemsVisible.isEmpty && appState.history.searchQuery.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Pinned")
          .foregroundStyle(.secondary)
        Spacer()
        Button(appState.pinnedManageMode ? "Done" : "Manage") {
          appState.pinnedManageMode.toggle()
        }
        .controlSize(.small)
        .buttonStyle(.link)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(.clear)

      // Pinned items content
      LazyVStack(spacing: 0) {
        ForEach(pinnedItems) { item in
          if appState.pinnedManageMode {
            PinnedManageRow(item: item)
          } else {
            HistoryItemView(item: item)
          }
        }

        if showPinsSeparator {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
      }
    }
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.pinnedItemsHeight = geo.size.height
          }
      }
    }
  }
}

struct PinnedManageRow: View {
  @Bindable var item: HistoryItemDecorator
  @Environment(AppState.self) private var appState

  var body: some View {
    ZStack(alignment: .trailing) {
      HistoryItemView(item: item)

      HStack(spacing: 6) {
        Button(action: { moveUp() }) {
          Image(systemName: "chevron.up")
        }
        .help("Move Up")
        .buttonStyle(.borderless)
        .controlSize(.small)

        Button(action: { moveDown() }) {
          Image(systemName: "chevron.down")
        }
        .help("Move Down")
        .buttonStyle(.borderless)
        .controlSize(.small)

        Button(action: { unpin() }) {
          Image(systemName: "pin.slash")
        }
        .help("Unpin")
        .buttonStyle(.borderless)
        .controlSize(.small)
      }
      .padding(.trailing, 60)
    }
  }

  private func unpin() {
    appState.history.togglePin(item)
  }

  private func moveUp() {
    Task { @MainActor in
      appState.history.movePinnedUp(item)
    }
  }

  private func moveDown() {
    Task { @MainActor in
      appState.history.movePinnedDown(item)
    }
  }
}

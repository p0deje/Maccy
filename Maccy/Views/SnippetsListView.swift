import SwiftUI

struct SnippetsListView: View {
  @FocusState.Binding var searchFocused: Bool
  @Environment(AppState.self) private var appState
  @Environment(ModifierFlags.self) private var modifierFlags
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Button {
            appState.showHistory()
          } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
          }
          .buttonStyle(.plain)

          if let folder = appState.snippets.currentFolder, appState.snippets.searchQuery.isEmpty {
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
            Button(folder.name) { _ = appState.snippets.goBack() }.buttonStyle(.plain)
          }

          SearchFieldView(
            placeholder: "Search snippets…",
            query: Binding(
              get: { appState.snippets.searchQuery },
              set: { appState.snippets.searchQuery = $0 }
            )
          )
          .focused($searchFocused)
        }
        .padding(Popup.horizontalPadding)

        Divider().padding(.horizontal, Popup.horizontalSeparatorPadding)
      }
      .readHeight(appState, into: \.popup.headerHeight)

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(appState.snippets.visibleRows.enumerated()), id: \.element.id) { index, row in
              HStack(spacing: 8) {
                Image(systemName: rowIcon(row))
                  .foregroundStyle(.secondary)
                  .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                  Text(row.name).lineLimit(1)
                  if case .snippet(let snippet) = row, !snippet.content.isEmpty {
                    Text(snippet.content.replacingOccurrences(of: "\n", with: " "))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                Spacer()
                if index < 9 {
                  Text("⌘\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(appState.snippets.selectedID == row.id ? Color.white : .secondary)
                }
                if case .folder = row { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
              }
              .padding(.horizontal, 10)
              .frame(minHeight: Popup.itemHeight)
              .foregroundStyle(appState.snippets.selectedID == row.id ? Color.white : .primary)
              .background(appState.snippets.selectedID == row.id ? Color.accentColor.opacity(0.8) : .clear)
              .clipShape(.rect(cornerRadius: Popup.cornerRadius))
              .contentShape(Rectangle())
              .id(row.id)
              .onHover { if $0 { appState.snippets.select(row.id) } }
              .onTapGesture {
                appState.snippets.select(row.id)
                appState.snippets.activate(flags: modifierFlags.flags)
              }
            }
          }
          .padding(.vertical, Popup.verticalSeparatorPadding)
          .padding(.horizontal, 10)
          .background {
            GeometryReader { geometry in
              Color.clear.task(id: appState.popup.needsResize) {
                try? await Task.sleep(for: .milliseconds(10))
                guard appState.popup.needsResize else { return }
                appState.popup.resize(height: geometry.size.height)
              }
            }
          }
        }
        .onChange(of: appState.snippets.selectedID) { _, id in
          if let id { proxy.scrollTo(id) }
        }
      }
      .accessibilityIdentifier("snippets-scroll-view")
    }
    .onAppear {
      Task { @MainActor in
        await Task.yield()
        searchFocused = true
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        appState.snippets.reload()
        appState.snippets.highlightFirst()
        searchFocused = true
      } else {
        modifierFlags.flags = []
      }
    }
  }

  private func rowIcon(_ row: SnippetRow) -> String {
    switch row {
    case .folder: "folder"
    case .snippet: "text.quote"
    }
  }
}

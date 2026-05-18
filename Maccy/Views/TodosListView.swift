import Defaults
import SwiftUI

struct TodosListView: View {
  @Environment(AppState.self) private var appState
  @FocusState.Binding var searchFocused: Bool
  @Default(.showCompletedTodos) private var showCompletedTodos

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if appState.todos.isSearching {
          ForEach(appState.todos.searchMatches) { item in
            TodoItemView(item: item)
          }
        } else {
          sectionedList
        }

        if appState.todos.pinnedItems.isEmpty
            && appState.todos.activeItems.isEmpty
            && appState.todos.completedItems.isEmpty
            && !appState.todos.isSearching {
          Text(NSLocalizedString("EmptyTodos", tableName: "Todos", comment: ""))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }

        if appState.todos.isSearching, appState.todos.searchMatches.isEmpty {
          Text(NSLocalizedString("EmptySearch", tableName: "Localizable", comment: ""))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
      }
      .padding(.horizontal, Popup.horizontalPadding)
    }
  }

  @ViewBuilder
  private var sectionedList: some View {
    if !appState.todos.pinnedItems.isEmpty {
      sectionHeader(NSLocalizedString("Pinned", tableName: "Todos", comment: ""))
      ForEach(appState.todos.pinnedItems) { item in
        TodoItemView(item: item)
      }
    }

    if !appState.todos.activeItems.isEmpty {
      sectionHeader(NSLocalizedString("Active", tableName: "Todos", comment: ""))
      ForEach(appState.todos.activeItems) { item in
        TodoItemView(item: item)
      }
    }

    if showCompletedTodos, !appState.todos.completedItems.isEmpty {
      Button {
        appState.todos.showCompletedSection.toggle()
      } label: {
        HStack {
          sectionHeader(
            String(
              format: NSLocalizedString("CompletedCount", tableName: "Todos", comment: ""),
              appState.todos.completedItems.count
            )
          )
          Spacer()
          Image(systemName: appState.todos.showCompletedSection ? "chevron.down" : "chevron.right")
            .font(.caption2)
        }
      }
      .buttonStyle(.plain)

      if appState.todos.showCompletedSection {
        ForEach(appState.todos.completedItems) { item in
          TodoItemView(item: item)
        }
      }
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.caption2)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .padding(.top, 4)
      .padding(.bottom, 2)
  }
}

import Defaults
import SwiftUI

struct TodosListView: View {
  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase
  @FocusState.Binding var searchFocused: Bool
  @Default(.showCompletedTodos) private var showCompletedTodos

  private var topPadding: CGFloat {
    Popup.verticalSeparatorPadding
  }

  private var bottomPadding: CGFloat {
    Popup.verticalSeparatorPadding - 1
  }

  var body: some View {
    ScrollViewReader { proxy in
      List {
        if appState.todos.isSearching {
          ForEach(appState.todos.searchMatches) { item in
            todoRow(item)
          }
        } else {
          sectionedList
        }

        if appState.todos.pinnedItems.isEmpty
            && appState.todos.activeItems.isEmpty
            && appState.todos.completedItems.isEmpty
            && !appState.todos.isSearching {
          TodoEmptyStateView(
            systemImage: "checklist",
            message: NSLocalizedString("EmptyTodos", tableName: "Todos", comment: "")
          )
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

          Text(NSLocalizedString("EmptyTodosHint", tableName: "Todos", comment: ""))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }

        if appState.todos.isSearching, appState.todos.searchMatches.isEmpty {
          TodoEmptyStateView(
            systemImage: "magnifyingglass",
            message: NSLocalizedString("EmptySearch", tableName: "Localizable", comment: "")
          )
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .scrollIndicators(.automatic)
      .padding(.top, topPadding)
      .padding(.bottom, bottomPadding)
      .animation(
        .easeInOut(duration: 0.18),
        value: appState.todos.activeItems.map(\.id) + appState.todos.pinnedItems.map(\.id)
      )
      .task(id: appState.todos.scrollTarget) {
        guard appState.todos.scrollTarget != nil else { return }

        try? await Task.sleep(for: .milliseconds(10))
        guard !Task.isCancelled else { return }

        if let selection = appState.todos.scrollTarget {
          withAnimation {
            proxy.scrollTo(selection, anchor: .center)
          }
          appState.todos.scrollTarget = nil
        }
      }
      .onChange(of: scenePhase) {
        if scenePhase == .active {
          searchFocused = true
          appState.todos.isKeyboardNavigating = true
          if appState.todos.selectedId == nil,
             let id = appState.todos.activeItems.first?.id
               ?? appState.todos.pinnedItems.first?.id {
            appState.todos.select(id: id)
          }
          if appState.activeTab == .todos, appState.todos.selectedId != nil {
            appState.preview.enableAutoOpen()
            appState.preview.resetAutoOpenSuppression()
            appState.preview.startAutoOpen()
          }
        } else {
          appState.todos.isKeyboardNavigating = true
          appState.preview.cancelAutoOpen()
        }
      }
      .background {
        GeometryReader { geo in
          Color.clear
            .task(id: appState.popup.needsResize) {
              try? await Task.sleep(for: .milliseconds(10))
              guard !Task.isCancelled else { return }

              if appState.popup.needsResize {
                appState.popup.resize(height: geo.size.height)
              }
            }
        }
      }
    }
    .contentMargins(.leading, 10, for: .scrollIndicators)
    .contentMargins(.top, topPadding, for: .scrollIndicators)
    .contentMargins(.bottom, bottomPadding, for: .scrollIndicators)
  }

  @ViewBuilder
  private var sectionedList: some View {
    if !appState.todos.pinnedItems.isEmpty {
      Section {
        ForEach(appState.todos.pinnedItems) { item in
          todoRow(item)
        }
        .onMove { source, destination in
          appState.todos.movePinnedItems(from: source, to: destination)
        }
      } header: {
        TodoSectionHeaderView(
          title: NSLocalizedString("Pinned", tableName: "Todos", comment: "")
        )
        .textCase(nil)
      }
    }

    if !appState.todos.activeItems.isEmpty {
      Section {
        ForEach(appState.todos.activeItems) { item in
          todoRow(item)
        }
        .onMove { source, destination in
          appState.todos.moveActiveItems(from: source, to: destination)
        }
      } header: {
        TodoSectionHeaderView(
          title: NSLocalizedString("Active", tableName: "Todos", comment: "")
        )
        .textCase(nil)
      }
    }

    if showCompletedTodos, !appState.todos.completedItems.isEmpty {
      Section {
        if appState.todos.showCompletedSection {
          ForEach(appState.todos.completedItems) { item in
            todoRow(item)
          }
        }
      } header: {
        completedSectionHeader
          .textCase(nil)
      }
    }
  }

  private func todoRow(_ item: TodoItemDecorator) -> some View {
    TodoItemView(item: item)
      .id(item.id)
      .listRowInsets(
        EdgeInsets(
          top: TodoDesign.rowSpacing / 2,
          leading: 0,
          bottom: TodoDesign.rowSpacing / 2,
          trailing: 0
        )
      )
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
  }

  private var completedSectionHeader: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18)) {
        appState.todos.showCompletedSection.toggle()
      }
    } label: {
      HStack(spacing: 6) {
        Text(
          String(
            format: NSLocalizedString("CompletedCount", tableName: "Todos", comment: ""),
            appState.todos.completedItems.count
          )
        )
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .tracking(0.35)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
          .rotationEffect(.degrees(appState.todos.showCompletedSection ? 90 : 0))
      }
      .padding(.top, TodoDesign.sectionHeaderTopPadding)
      .padding(.bottom, 4)
      .padding(.horizontal, 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

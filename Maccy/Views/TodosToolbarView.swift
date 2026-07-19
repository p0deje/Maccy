import AppKit
import SwiftUI

struct TodosToolbarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)

      HStack(spacing: 6) {
        listFilterPicker

        Button {
          promptAndAddList()
        } label: {
          Image(systemName: "folder.badge.plus")
            .font(.callout.weight(.medium))
        }
        .buttonStyle(.plain)
        .frame(height: 23)
        .help(NSLocalizedString("AddList", tableName: "Todos", comment: ""))

        Spacer(minLength: 4)

        Button {
          _ = appState.todos.add()
        } label: {
          Label(
            NSLocalizedString("NewTodo", tableName: "Todos", comment: ""),
            systemImage: "plus.circle.fill"
          )
          .labelStyle(.titleAndIcon)
          .font(.callout.weight(.medium))
        }
        .buttonStyle(.plain)
        .frame(height: 23)
        .help(NSLocalizedString("NewTodo", tableName: "Todos", comment: ""))
      }
      .padding(.horizontal, 10)
    }
    .readHeight(appState, into: \.popup.extraTopHeight)
  }

  private var listFilterPicker: some View {
    Picker(
      NSLocalizedString("ListFilter", tableName: "Todos", comment: ""),
      selection: Binding(
        get: { appState.todos.selectedListFilter },
        set: { appState.todos.selectedListFilter = $0 }
      )
    ) {
      Text(NSLocalizedString("FilterToday", tableName: "Todos", comment: ""))
        .tag(TodoListFilter.today)
      Text(NSLocalizedString("FilterUpcoming", tableName: "Todos", comment: ""))
        .tag(TodoListFilter.upcoming)
      Text(NSLocalizedString("FilterAll", tableName: "Todos", comment: ""))
        .tag(TodoListFilter.all)

      Divider()

      ForEach(appState.todos.lists, id: \.id) { list in
        Text(list.name)
          .tag(TodoListFilter.list(list.id))
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .frame(maxWidth: 160, alignment: .leading)
  }

  private func promptAndAddList() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("AddListTitle", tableName: "Todos", comment: "")
    alert.informativeText = NSLocalizedString("AddListMessage", tableName: "Todos", comment: "")
    alert.addButton(withTitle: NSLocalizedString("AddListConfirm", tableName: "Todos", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("AddListCancel", tableName: "Todos", comment: ""))

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.placeholderString = NSLocalizedString("ListNamePlaceholder", tableName: "Todos", comment: "")
    alert.accessoryView = field
    alert.window.initialFirstResponder = field

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    _ = appState.todos.addList(name: field.stringValue)
  }
}

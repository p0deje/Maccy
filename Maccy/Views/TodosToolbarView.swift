import SwiftUI

struct TodosToolbarView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)

      HStack(spacing: 6) {
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
}

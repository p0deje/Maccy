import SwiftUI
import Settings

struct WorkspaceSettingsPane: View {
  @Environment(AppState.self) private var appState

  @State private var newWorkspaceName = ""
  @State private var selectedWorkspace: Workspace?
  @State private var editingName = ""
  @State private var isEditing = false

  private var workspaceManager: WorkspaceManager {
    appState.workspaceManager
  }

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        label: { Text("Workspaces", tableName: "WorkspaceSettings") }
      ) {
        VStack(alignment: .leading, spacing: 8) {
          List(workspaceManager.workspaces, id: \.id, selection: $selectedWorkspace) { workspace in
            HStack {
              if isEditing && selectedWorkspace == workspace {
                TextField("Name", text: $editingName)
                  .onSubmit {
                    let name = editingName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                      workspaceManager.rename(workspace, to: name)
                    }
                    isEditing = false
                  }
                  .textFieldStyle(.roundedBorder)
              } else {
                Text(workspace.name)
                  .frame(maxWidth: .infinity, alignment: .leading)

                if workspace == workspaceManager.activeWorkspace {
                  Text("Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                      RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                    )
                }
              }
            }
            .tag(workspace)
            .contentShape(Rectangle())
          }
          .listStyle(.bordered)
          .frame(height: 200)

          HStack(spacing: 4) {
            TextField("New workspace name", text: $newWorkspaceName)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 200)
              .onSubmit {
                addWorkspace()
              }

            Button(action: addWorkspace) {
              Image(systemName: "plus")
            }
            .disabled(
              newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty
                || workspaceManager.workspaces.count >= WorkspaceManager.maxWorkspaces
            )

            Button(action: {
              if let workspace = selectedWorkspace {
                editingName = workspace.name
                isEditing = true
              }
            }) {
              Image(systemName: "pencil")
            }
            .disabled(selectedWorkspace == nil)

            Button(action: {
              if let workspace = selectedWorkspace {
                workspaceManager.delete(workspace)
                selectedWorkspace = nil
              }
            }) {
              Image(systemName: "minus")
            }
            .disabled(selectedWorkspace == nil || workspaceManager.workspaces.count <= 1)
          }

          Text("WorkspaceDescription", tableName: "WorkspaceSettings")
            .controlSize(.small)
            .foregroundStyle(.gray)
        }
      }
    }
  }

  private func addWorkspace() {
    let name = newWorkspaceName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    if let workspace = workspaceManager.create(name: name) {
      selectedWorkspace = workspace
    }
    newWorkspaceName = ""
  }
}

#Preview {
  WorkspaceSettingsPane()
    .environment(AppState.shared)
    .environment(\.locale, .init(identifier: "en"))
}

import SwiftUI

struct WorkspaceTabsView: View {
  @Environment(AppState.self) private var appState

  @State private var renamingWorkspace: Workspace?
  @State private var renameText = ""
  @State private var showRenamePopover = false

  private var workspaceManager: WorkspaceManager {
    appState.workspaceManager
  }

  var body: some View {
    HStack(spacing: 4) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(workspaceManager.workspaces, id: \.id) { workspace in
            workspaceTab(workspace)
          }
        }
      }

      Button(action: addWorkspace) {
        Image(systemName: "plus")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Color.secondary)
          .frame(width: 22, height: 22)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(Color.primary.opacity(0.08))
          )
      }
      .buttonStyle(.plain)
      .disabled(workspaceManager.workspaces.count >= WorkspaceManager.maxWorkspaces)
      .help(Text("workspace_add_tooltip"))
    }
    .padding(.horizontal, Popup.horizontalPadding + 5)
    .padding(.vertical, 4)
    .readHeight(appState, into: \.popup.workspaceTabsHeight)
    .accessibilityHidden(true)
    .onChange(of: showRenamePopover) { _, newValue in
      appState.isPopoverEditing = newValue
    }
  }

  @ViewBuilder
  private func workspaceTab(_ workspace: Workspace) -> some View {
    let isActive = workspace == workspaceManager.activeWorkspace

    Text(workspace.name)
      .font(.system(size: 11, weight: isActive ? .semibold : .regular))
      .foregroundStyle(isActive ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isActive ? Color.accentColor : Color.primary.opacity(0.08))
      )
      .onTapGesture(count: 2) {
        startRename(workspace)
      }
      .onTapGesture(count: 1) {
        workspaceManager.switchTo(workspace)
        Task {
          try? await appState.history.load()
        }
      }
      .popover(isPresented: Binding(
        get: { renamingWorkspace == workspace && showRenamePopover },
        set: { if !$0 { endRename() } }
      )) {
        renamePopover()
      }
      .contextMenu {
        workspaceContextMenu(for: workspace)
      }
  }

  @ViewBuilder
  private func renamePopover() -> some View {
    VStack(spacing: 8) {
      Text("workspace_rename_title")
        .font(.headline)
      TextField("workspace_rename_name", text: $renameText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 180)
        .onSubmit {
          commitRename()
        }
      HStack {
        Button("workspace_rename_cancel") {
          endRename()
        }
        Button("workspace_rename_confirm") {
          commitRename()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding()
  }

  @ViewBuilder
  private func workspaceContextMenu(for workspace: Workspace) -> some View {
    Button("workspace_rename") {
      startRename(workspace)
    }
    Button("workspace_delete", role: .destructive) {
      let wasActive = (workspace == workspaceManager.activeWorkspace)
      workspaceManager.delete(workspace)
      if wasActive {
        Task {
          try? await appState.history.load()
        }
      }
    }
    .disabled(workspaceManager.workspaces.count <= 1)
  }

  private func startRename(_ workspace: Workspace) {
    renameText = workspace.name
    renamingWorkspace = workspace
    showRenamePopover = true
  }

  private func endRename() {
    showRenamePopover = false
    renamingWorkspace = nil
  }

  private func addWorkspace() {
    let baseName = "Workspace"
    var counter = 1
    var name = "\(baseName) \(counter)"
    let existingNames = Set(workspaceManager.workspaces.map { $0.name.lowercased() })
    while existingNames.contains(name.lowercased()) {
      counter += 1
      name = "\(baseName) \(counter)"
    }

    if let workspace = workspaceManager.create(name: name) {
      workspaceManager.switchTo(workspace)
      Task {
        try? await appState.history.load()
      }
    }
  }

  private func commitRename() {
    if let workspace = renamingWorkspace {
      let name = renameText.trimmingCharacters(in: .whitespaces)
      if !name.isEmpty {
        workspaceManager.rename(workspace, to: name)
      }
    }
    endRename()
  }
}

import Defaults
import Foundation
import Observation
import SwiftData

@Observable
class WorkspaceManager {
  static let maxWorkspaces = 10
  static let shared = WorkspaceManager()

  var workspaces: [Workspace] = []

  var activeWorkspace: Workspace? {
    didSet {
      if let workspace = activeWorkspace {
        Defaults[.activeWorkspaceId] = workspace.id.uuidString
      }
    }
  }

  @MainActor
  func load() {
    let descriptor = FetchDescriptor<Workspace>(
      sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
    )
    workspaces = (try? Storage.shared.context.fetch(descriptor)) ?? []

    // Restore active workspace from persisted UUID, or fall back to the first one.
    if let savedId = Defaults[.activeWorkspaceId],
       let uuid = UUID(uuidString: savedId) {
      activeWorkspace = workspaces.first(where: { $0.id == uuid }) ?? workspaces.first
    } else {
      activeWorkspace = workspaces.first
    }
  }

  @discardableResult
  @MainActor
  func create(name: String) -> Workspace? {
    // Prevent duplicate workspace names.
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { return nil }
    guard workspaces.count < Self.maxWorkspaces else { return nil }
    guard !workspaces.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) else { return nil }

    let maxOrder = workspaces.map(\.sortOrder).max() ?? -1
    let workspace = Workspace(name: trimmedName, sortOrder: maxOrder + 1)
    Storage.shared.context.insert(workspace)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()

    workspaces.append(workspace)
    return workspace
  }

  @MainActor
  func rename(_ workspace: Workspace, to newName: String) {
    let trimmedName = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { return }
    // Prevent renaming to an existing name.
    guard !workspaces.contains(where: { $0 != workspace && $0.name.lowercased() == trimmedName.lowercased() }) else {
      return
    }

    workspace.name = trimmedName
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
  }

  @MainActor
  func delete(_ workspace: Workspace) {
    // Prevent deleting the last workspace.
    guard workspaces.count > 1 else { return }

    let wasActive = (workspace == activeWorkspace)

    // Move items from the deleted workspace to the first remaining workspace.
    let fallback = workspaces.first(where: { $0 != workspace })
    for item in workspace.items {
      item.workspace = fallback
    }

    Storage.shared.context.delete(workspace)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()

    workspaces.removeAll(where: { $0 == workspace })

    if wasActive {
      activeWorkspace = workspaces.first
    }
  }

  func switchTo(_ workspace: Workspace) {
    activeWorkspace = workspace
  }
}

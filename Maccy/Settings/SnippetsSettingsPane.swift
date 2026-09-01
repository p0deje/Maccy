import SwiftData
import SwiftUI

struct SnippetsSettingsPane: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \SnippetFolder.order) private var folders: [SnippetFolder]

  @State private var selectedFolderID: UUID?
  @State private var selectedSnippetID: UUID?
  @State private var pendingDeletion: Deletion?

  private enum Deletion {
    case folder(SnippetFolder)
    case snippet(Snippet)
  }

  private var selectedFolder: SnippetFolder? {
    folders.first { $0.id == selectedFolderID }
  }

  private var snippets: [Snippet] {
    selectedFolder?.snippets.sorted { $0.order < $1.order } ?? []
  }

  private var selectedSnippet: Snippet? {
    snippets.first { $0.id == selectedSnippetID }
  }

  var body: some View {
    HSplitView {
      collection(title: "Folders", items: folders, selection: $selectedFolderID) { folder in
        SnippetFolderName(folder: folder, save: save)
      } controls: {
        controls(
          add: addFolder,
          delete: selectedFolder.map { folder in { pendingDeletion = .folder(folder) } },
          moveUp: { moveFolder(by: -1) },
          moveDown: { moveFolder(by: 1) }
        )
      }
      .frame(minWidth: 150)

      collection(title: "Snippets", items: snippets, selection: $selectedSnippetID) { snippet in
        Text(snippet.name)
      } controls: {
        controls(
          add: addSnippet,
          delete: selectedSnippet.map { snippet in { pendingDeletion = .snippet(snippet) } },
          moveUp: { moveSnippet(by: -1) },
          moveDown: { moveSnippet(by: 1) }
        )
      }
      .frame(minWidth: 170)

      Group {
        if let selectedSnippet {
          SnippetEditor(snippet: selectedSnippet, save: save)
        } else {
          ContentUnavailableView("Select a snippet", systemImage: "text.quote")
        }
      }
      .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 650, minHeight: 420)
    .padding()
    .onAppear { selectedFolderID = folders.first?.id }
    .onChange(of: selectedFolderID) { selectedSnippetID = snippets.first?.id }
    .confirmationDialog("Delete this item?", isPresented: deletionPresented, titleVisibility: .visible) {
      Button("Delete", role: .destructive, action: deletePending)
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
    }
  }

  private var deletionPresented: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }

  private func collection<Item: Identifiable, Row: View, Controls: View>(
    title: String,
    items: [Item],
    selection: Binding<UUID?>,
    @ViewBuilder row: @escaping (Item) -> Row,
    @ViewBuilder controls: () -> Controls
  ) -> some View where Item.ID == UUID {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      List(items, selection: selection) { item in row(item).tag(item.id) }
      controls()
    }
  }

  private func controls(
    add: @escaping () -> Void,
    delete: (() -> Void)?,
    moveUp: @escaping () -> Void,
    moveDown: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 6) {
      Button(action: add) { Image(systemName: "plus") }
      Button(action: delete ?? {}) { Image(systemName: "minus") }.disabled(delete == nil)
      Spacer()
      Button(action: moveUp) { Image(systemName: "arrow.up") }.disabled(delete == nil)
      Button(action: moveDown) { Image(systemName: "arrow.down") }.disabled(delete == nil)
    }
    .buttonStyle(.borderless)
  }

  private func addFolder() {
    let folder = SnippetFolder(name: "New Folder", order: (folders.map(\.order).max() ?? -1) + 1)
    modelContext.insert(folder)
    selectedFolderID = folder.id
    save()
  }

  private func addSnippet() {
    guard let selectedFolder else { return }
    let snippet = Snippet(name: "New Snippet", order: (snippets.map(\.order).max() ?? -1) + 1, folder: selectedFolder)
    modelContext.insert(snippet)
    selectedSnippetID = snippet.id
    save()
  }

  private func deletePending() {
    let deletingFolder = if case .folder = pendingDeletion { true } else { false }
    switch pendingDeletion {
    case .folder(let folder): modelContext.delete(folder)
    case .snippet(let snippet): modelContext.delete(snippet)
    case nil: return
    }
    pendingDeletion = nil
    selectedSnippetID = nil
    if deletingFolder {
      selectedFolderID = folders.first { $0.id != selectedFolderID }?.id
    }
    save()
  }

  private func moveFolder(by offset: Int) {
    guard let folder = selectedFolder, let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
    reorder(folders, index: index, offset: offset)
  }

  private func moveSnippet(by offset: Int) {
    guard let snippet = selectedSnippet, let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
    reorder(snippets, index: index, offset: offset)
  }

  private func reorder<T>(_ items: [T], index: Int, offset: Int) where T: AnyObject {
    let destination = index + offset
    guard items.indices.contains(destination) else { return }
    if let folders = items as? [SnippetFolder] {
      folders[index].order = destination
      folders[destination].order = index
    } else if let snippets = items as? [Snippet] {
      snippets[index].order = destination
      snippets[destination].order = index
    }
    save()
  }

  private func save() {
    modelContext.processPendingChanges()
    try? modelContext.save()
    AppState.shared.snippets.reload()
  }
}

private struct SnippetEditor: View {
  @Bindable var snippet: Snippet
  let save: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Name").font(.headline)
      TextField("Snippet name", text: $snippet.name).onChange(of: snippet.name) { save() }
      Text("Content").font(.headline)
      TextEditor(text: $snippet.content)
        .font(.body.monospaced())
        .border(Color.secondary.opacity(0.25))
        .onChange(of: snippet.content) { save() }
    }
    .padding(.leading)
  }
}

private struct SnippetFolderName: View {
  @Bindable var folder: SnippetFolder
  let save: () -> Void

  var body: some View {
    TextField("Folder name", text: $folder.name)
      .textFieldStyle(.plain)
      .onChange(of: folder.name) { save() }
  }
}

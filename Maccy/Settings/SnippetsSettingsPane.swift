import SwiftUI

struct SnippetsSettingsPane: View {
  @State private var snippetsStore = SnippetsStore.shared
  @State private var selectedFolderID: SnippetFolder.ID?
  @State private var selectedSnippetID: Snippet.ID?
  @State private var iconPickerPresented = false

  private let iconGridColumns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6)

  private var selectedFolder: SnippetFolder? {
    snippetsStore.folder(id: selectedFolderID)
  }

  private var selectedSnippet: Snippet? {
    snippetsStore.snippet(id: selectedSnippetID, in: selectedFolderID)
  }

  var body: some View {
    HSplitView {
      folderList
        .frame(minWidth: 160, idealWidth: 180)

      VStack(alignment: .leading, spacing: 12) {
        if selectedFolder == nil {
          emptyFolderView
        } else {
          folderEditor
          snippetsTable
          snippetEditor
          searchHint
        }
      }
      .padding(.leading, 18)
      .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 650, minHeight: 420)
    .padding()
    .onAppear {
      normalizeSelection()
    }
    .onChange(of: snippetsStore.folders) {
      normalizeSelection()
    }
  }

  private var folderList: some View {
    VStack(alignment: .leading, spacing: 8) {
      List(selection: $selectedFolderID) {
        ForEach(snippetsStore.folders) { folder in
          HStack(spacing: 6) {
            folderIcon(folder)
              .frame(width: 16, alignment: .center)
            Text(folder.name.isEmpty ? localized("Untitled Folder") : folder.name)
          }
          .tag(folder.id as SnippetFolder.ID?)
        }
      }

      HStack(spacing: 8) {
        Button(action: addFolder) {
          Image(systemName: "plus")
        }
        .help(localized("Add Folder"))

        Button(action: deleteFolder) {
          Image(systemName: "minus")
        }
        .disabled(selectedFolderID == nil)
        .help(localized("Delete Folder"))
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
    }
  }

  private var emptyFolderView: some View {
    VStack(alignment: .center, spacing: 12) {
      Spacer()
      Text(localized("No Snippet Folders"))
        .font(.headline)
      Text(localized("Create a folder to start adding snippets."))
        .foregroundStyle(.secondary)
      Button(action: addFolder) {
        Label(localized("Add Folder"), systemImage: "plus")
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var folderEditor: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(localized("Folder"))
        .font(.headline)
      HStack(spacing: 8) {
        Button {
          iconPickerPresented.toggle()
        } label: {
          folderIconLabel(selectedFolder?.icon)
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .help(localized("Choose Folder Icon"))
        .popover(isPresented: $iconPickerPresented, arrowEdge: .bottom) {
          folderIconPicker
        }

        TextField(localized("Folder Name"), text: folderName)
      }
    }
  }

  private var folderIconPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(localized("Choose Folder Icon"))
        .font(.headline)

      LazyVGrid(columns: iconGridColumns, spacing: 6) {
        iconPickerButton(icon: nil)

        ForEach(SnippetFolderIcon.presets, id: \.self) { icon in
          iconPickerButton(icon: icon)
        }
      }
    }
    .padding(12)
    .frame(width: 230)
  }

  private var snippetsTable: some View {
    VStack(alignment: .leading, spacing: 8) {
      Table(selectedFolder?.snippets ?? [], selection: $selectedSnippetID) {
        TableColumn(localized("Name")) { snippet in
          Text(snippet.name.isEmpty ? localized("Untitled Snippet") : snippet.name)
        }
        .width(min: 130, ideal: 160)

        TableColumn(localized("Content")) { snippet in
          Text(snippet.content.replacingOccurrences(of: "\n", with: " "))
            .foregroundStyle(snippet.content.isEmpty ? .secondary : .primary)
            .lineLimit(1)
        }
      }
      .frame(minHeight: 140)

      HStack(spacing: 8) {
        Button(action: addSnippet) {
          Image(systemName: "plus")
        }
        .disabled(selectedFolderID == nil)
        .help(localized("Add Snippet"))

        Button(action: deleteSnippet) {
          Image(systemName: "minus")
        }
        .disabled(selectedSnippetID == nil)
        .help(localized("Delete Snippet"))
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
    }
  }

  @ViewBuilder
  private var snippetEditor: some View {
    if selectedSnippet != nil {
      VStack(alignment: .leading, spacing: 8) {
        Text(localized("Snippet"))
          .font(.headline)
        TextField(localized("Name"), text: snippetName)
        TextEditor(text: snippetContent)
          .font(.body)
          .frame(minHeight: 100)
          .border(.separator)
      }
    } else {
      Text(localized("Select a snippet to edit its name and content."))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }
  }

  private var searchHint: some View {
    Text(localized(
      "Snippets appear only after you type a search query. " +
        "Folder and name match immediately; content matches after at least two characters."
    ))
      .foregroundStyle(.secondary)
      .controlSize(.small)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var folderName: Binding<String> {
    Binding {
      selectedFolder?.name ?? ""
    } set: { name in
      snippetsStore.renameFolder(id: selectedFolderID, to: name)
    }
  }

  private var snippetName: Binding<String> {
    Binding {
      selectedSnippet?.name ?? ""
    } set: { name in
      snippetsStore.updateSnippet(id: selectedSnippetID, in: selectedFolderID, name: name)
    }
  }

  private var snippetContent: Binding<String> {
    Binding {
      selectedSnippet?.content ?? ""
    } set: { content in
      snippetsStore.updateSnippet(id: selectedSnippetID, in: selectedFolderID, content: content)
    }
  }

  private func addFolder() {
    selectedFolderID = snippetsStore.addFolder()
    selectedSnippetID = nil
  }

  private func deleteFolder() {
    snippetsStore.deleteFolder(id: selectedFolderID)
    selectedFolderID = snippetsStore.folders.first?.id
    selectedSnippetID = selectedFolder?.snippets.first?.id
  }

  private func addSnippet() {
    selectedSnippetID = snippetsStore.addSnippet(to: selectedFolderID)
  }

  private func deleteSnippet() {
    snippetsStore.deleteSnippet(id: selectedSnippetID, from: selectedFolderID)
    selectedSnippetID = selectedFolder?.snippets.first?.id
  }

  private func normalizeSelection() {
    if selectedFolder == nil {
      selectedFolderID = snippetsStore.folders.first?.id
    }
    if selectedSnippet == nil {
      selectedSnippetID = selectedFolder?.snippets.first?.id
    }
  }
}

private extension SnippetsSettingsPane {
  private func localized(_ key: String) -> String {
    NSLocalizedString(key, tableName: "SnippetsSettings", comment: "")
  }

  @ViewBuilder
  private func folderIcon(_ folder: SnippetFolder) -> some View {
    if let icon = folder.icon, !icon.isEmpty {
      Text(icon)
    } else {
      Image(systemName: "folder")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func folderIconLabel(_ icon: String?) -> some View {
    if let icon, !icon.isEmpty {
      Text(icon)
        .font(.title3)
    } else {
      Image(systemName: "folder")
        .foregroundStyle(.secondary)
    }
  }

  private func iconPickerButton(icon: String?) -> some View {
    let isSelected = selectedFolder?.icon == icon || (selectedFolder?.icon == nil && icon == nil)

    return Button {
      snippetsStore.updateFolderIcon(id: selectedFolderID, to: icon ?? "")
      iconPickerPresented = false
    } label: {
      folderIconLabel(icon)
        .frame(width: 30, height: 30)
        .background(
          isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
          in: RoundedRectangle(cornerRadius: 5)
        )
    }
    .buttonStyle(.plain)
    .help(icon ?? localized("Default Folder Icon"))
  }
}

#Preview {
  SnippetsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}

import AppKit
import Foundation
import Observation

@Observable
final class SnippetsStore {
  static let shared = SnippetsStore()

  var folders: [SnippetFolder] {
    didSet {
      save()
    }
  }

  private let userDefaults: UserDefaults
  private let defaultsKey = "snippets"
  private let search = SnippetSearch()

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    if let data = userDefaults.data(forKey: defaultsKey),
       let folders = try? JSONDecoder().decode([SnippetFolder].self, from: data) {
      self.folders = folders
    } else {
      self.folders = []
    }
  }

  @discardableResult
  func addFolder(name: String = "General") -> SnippetFolder.ID {
    let folder = SnippetFolder(name: name)
    folders.append(folder)
    return folder.id
  }

  func renameFolder(id: SnippetFolder.ID?, to name: String) {
    guard let folderIndex = folderIndex(id: id) else {
      return
    }

    folders[folderIndex].name = name
  }

  func updateFolderIcon(id: SnippetFolder.ID?, to icon: String) {
    guard let folderIndex = folderIndex(id: id) else {
      return
    }

    let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
    folders[folderIndex].icon = trimmedIcon.isEmpty ? nil : trimmedIcon
  }

  func deleteFolder(id: SnippetFolder.ID?) {
    guard let id else {
      return
    }

    folders.removeAll { $0.id == id }
  }

  @discardableResult
  func addSnippet(to folderID: SnippetFolder.ID?) -> Snippet.ID? {
    guard let folderIndex = folderIndex(id: folderID) else {
      return nil
    }

    let snippet = Snippet(name: "New Snippet")
    folders[folderIndex].snippets.append(snippet)
    return snippet.id
  }

  func deleteSnippet(id: Snippet.ID?, from folderID: SnippetFolder.ID?) {
    guard let id,
          let folderIndex = folderIndex(id: folderID) else {
      return
    }

    folders[folderIndex].snippets.removeAll { $0.id == id }
  }

  func updateSnippet(
    id: Snippet.ID?,
    in folderID: SnippetFolder.ID?,
    name: String? = nil,
    content: String? = nil
  ) {
    guard let snippetIndex = snippetIndex(id: id, in: folderID),
          let folderIndex = folderIndex(id: folderID) else {
      return
    }

    if let name {
      folders[folderIndex].snippets[snippetIndex].name = name
    }
    if let content {
      folders[folderIndex].snippets[snippetIndex].content = content
    }
  }

  func folder(id: SnippetFolder.ID?) -> SnippetFolder? {
    guard let id else {
      return nil
    }

    return folders.first { $0.id == id }
  }

  func snippet(id: Snippet.ID?, in folderID: SnippetFolder.ID?) -> Snippet? {
    guard let folder = folder(id: folderID),
          let id else {
      return nil
    }

    return folder.snippets.first { $0.id == id }
  }

  func searchResults(for query: String) -> [Search.SearchResult] {
    search.search(query, in: folders).map { result in
      Search.SearchResult(
        object: decorator(for: result),
        ranges: result.ranges
      )
    }
  }

  private func decorator(for result: SnippetSearchResult) -> HistoryItemDecorator {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: result.snippet.content.data(using: .utf8)
      )
    ]
    let item = HistoryItem(contents: contents)
    item.title = result.title

    return HistoryItemDecorator(
      item,
      source: .snippet(result.snippet.id),
      snippetFolderIcon: result.folder.icon
    )
  }

  private func folderIndex(id: SnippetFolder.ID?) -> Int? {
    guard let id else {
      return nil
    }

    return folders.firstIndex { $0.id == id }
  }

  private func snippetIndex(id: Snippet.ID?, in folderID: SnippetFolder.ID?) -> Int? {
    guard let folder = folder(id: folderID),
          let id else {
      return nil
    }

    return folder.snippets.firstIndex { $0.id == id }
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(folders) else {
      return
    }

    userDefaults.set(data, forKey: defaultsKey)
  }
}

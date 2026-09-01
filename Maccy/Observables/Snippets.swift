import AppKit
import Defaults
import Sauce
import SwiftData

enum SnippetRow: Identifiable {
  case folder(SnippetFolder)
  case snippet(Snippet)

  var id: UUID {
    switch self {
    case .folder(let folder): folder.id
    case .snippet(let snippet): snippet.id
    }
  }

  var name: String {
    switch self {
    case .folder(let folder): folder.name
    case .snippet(let snippet): snippet.name
    }
  }
}

@Observable
class Snippets {
  var folders: [SnippetFolder] = []
  var currentFolder: SnippetFolder?
  var selectedID: UUID?
  var searchQuery = "" {
    didSet {
      selectedID = visibleRows.first?.id
      AppState.shared.popup.needsResize = true
    }
  }

  var visibleRows: [SnippetRow] {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      return folders
        .flatMap(\.snippets)
        .filter { snippet in
          snippet.name.localizedCaseInsensitiveContains(query)
            || snippet.content.localizedCaseInsensitiveContains(query)
            || snippet.folder?.name.localizedCaseInsensitiveContains(query) == true
        }
        .sorted { ($0.folder?.order ?? 0, $0.order) < ($1.folder?.order ?? 0, $1.order) }
        .map(SnippetRow.snippet)
    }

    if let currentFolder {
      return currentFolder.snippets.sorted { $0.order < $1.order }.map(SnippetRow.snippet)
    }
    return folders.sorted { $0.order < $1.order }.map(SnippetRow.folder)
  }

  var pressedShortcutIndex: Int? {
    guard let event = NSApp.currentEvent else { return nil }
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)
    guard HistoryItemAction(modifierFlags) != .unknown else { return nil }

    let numberKeys: [Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
    guard let key = Sauce.shared.key(for: Int(event.keyCode)) else { return nil }
    return numberKeys.firstIndex(of: key).flatMap { $0 < visibleRows.count ? $0 : nil }
  }

  @MainActor
  func reload() {
    let descriptor = FetchDescriptor<SnippetFolder>(sortBy: [SortDescriptor(\.order)])
    folders = (try? Storage.shared.context.fetch(descriptor)) ?? []
    if let id = currentFolder?.id {
      currentFolder = folders.first { $0.id == id }
    }
    if !visibleRows.contains(where: { $0.id == selectedID }) {
      selectedID = visibleRows.first?.id
    }
  }

  func reset() {
    currentFolder = nil
    searchQuery = ""
    selectedID = visibleRows.first?.id
  }

  func select(_ id: UUID) {
    selectedID = id
  }

  func highlightFirst() { selectedID = visibleRows.first?.id }
  func highlightLast() { selectedID = visibleRows.last?.id }

  func highlightNext() {
    moveSelection(by: 1)
  }

  func highlightPrevious() {
    moveSelection(by: -1)
  }

  func goBack() -> Bool {
    guard currentFolder != nil else { return false }
    currentFolder = nil
    selectedID = visibleRows.first?.id
    AppState.shared.popup.needsResize = true
    return true
  }

  func openSelectedFolder() -> Bool {
    guard let row = visibleRows.first(where: { $0.id == selectedID }), case .folder(let folder) = row else {
      return false
    }
    currentFolder = folder
    selectedID = visibleRows.first?.id
    AppState.shared.popup.needsResize = true
    return true
  }

  func selectShortcut(at index: Int) {
    guard visibleRows.indices.contains(index) else { return }
    selectedID = visibleRows[index].id
  }

  @MainActor
  func activate(flags: NSEvent.ModifierFlags) {
    guard let row = visibleRows.first(where: { $0.id == selectedID }) else { return }
    switch row {
    case .folder(let folder):
      currentFolder = folder
      selectedID = visibleRows.first?.id
      AppState.shared.popup.needsResize = true
    case .snippet(let snippet):
      var paste = Defaults[.pasteByDefault]
      if !flags.isEmpty {
        switch HistoryItemAction(flags) {
        case .copy: paste = false
        case .paste, .pasteWithoutFormatting: paste = true
        case .unknown: return
        }
      }
      AppState.shared.popup.close()
      Clipboard.shared.copyInMaccy(snippet.content)
      if paste { Clipboard.shared.paste() }
      searchQuery = ""
    }
  }

  private func moveSelection(by offset: Int) {
    guard !visibleRows.isEmpty else { return }
    guard let selectedID, let index = visibleRows.firstIndex(where: { $0.id == selectedID }) else {
      self.selectedID = visibleRows.first?.id
      return
    }
    self.selectedID = visibleRows[(index + offset + visibleRows.count) % visibleRows.count].id
  }
}

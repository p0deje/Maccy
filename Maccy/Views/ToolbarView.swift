import Defaults
import KeyboardShortcuts
import SwiftUI

private struct KeyboardShortcutHelpModifier: ViewModifier {
  let name: KeyboardShortcuts.Name
  let key: String
  let tableName: String
  let comment: String = ""
  let replacementKey: String

  func body(content: Content) -> some View {
    if let shortcut = KeyboardShortcuts.Shortcut(name: name) {
      content
        .help(
          Text(
            NSLocalizedString(key, tableName: tableName, comment: comment)
              .replacingOccurrences(
                of: "{\(replacementKey)}",
                with: shortcut.description
              )
          )
        )
    } else {
      content
    }
  }
}

struct ToolbarButton<Label: View>: View {
  @Environment(AppState.self) private var appState

  let action: @MainActor () -> Void
  let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .frame(width: 23, height: 23)
    .onHover(perform: { inside in
      if let window = appState.appDelegate?.panel {
        window.isMovableByWindowBackground = !inside
      }
    })
  }

  func shortcutKeyHelp(
    name: KeyboardShortcuts.Name,
    key: String,
    tableName: String,
    replacementKey: String
  ) -> some View {
    self.modifier(
      KeyboardShortcutHelpModifier(
        name: name,
        key: key,
        tableName: tableName,
        replacementKey: replacementKey
      )
    )
  }

}

struct ToolbarView: View {
  @State private var appState = AppState.shared

  @Namespace var unionNamespace

  enum Section: Hashable {
    case itemOptions
  }

  private var shouldUnpin: Bool {
    return appState.navigator.selection.items.allSatisfy { $0.isPinned }
  }

  private var pinActionDisabled: Bool {
    return appState.navigator.selection.items.contains { $0.isPinned }
      && appState.navigator.selection.items.contains { !$0.isPinned }
  }

  private func savePreviewImage() {
    guard let item = appState.navigator.leadHistoryItem,
          let image = item.item.image else {
      return
    }

    let picturesDir = FileManager.default.urls(
      for: .picturesDirectory, in: .userDomainMask
    ).first ?? FileManager.default.homeDirectoryForCurrentUser

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let filename = "Maccy-\(formatter.string(from: item.item.firstCopiedAt)).png"
    let fileURL = picturesDir.appendingPathComponent(filename)

    // Remove existing file before writing to replace it.
    try? FileManager.default.removeItem(at: fileURL)

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
      return
    }

    try? pngData.write(to: fileURL)

    // Reveal in Finder
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
  }

  private func revealInFinder() {
    guard let item = appState.navigator.leadHistoryItem else {
      return
    }

    let urls = item.item.fileURLs.filter { url in
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    }

    guard !urls.isEmpty else { return }

    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  var body: some View {
    HStack {
      if !appState.navigator.selection.isEmpty {
        Spacer()

        if appState.navigator.leadHistoryItem?.hasFileURLs == true {
          ToolbarButton {
            revealInFinder()
          } label: {
            Image(systemName: "folder")
          }
          .help(Text("RevealInFinder", tableName: "PreviewItemView"))
        } else if appState.navigator.leadHistoryItem?.hasImage == true {
          ToolbarButton {
            savePreviewImage()
          } label: {
            Image(systemName: "square.and.arrow.down.on.square")
          }
          .help(Text("SaveImage", tableName: "PreviewItemView"))
        }

        ToolbarButton {
          withAnimation {
            appState.togglePin()
          }
        } label: {
          if (appState.navigator.selection.items.allSatisfy { $0.isPinned }) {
            Image(systemName: "pin.slash")
          } else {
            Image(systemName: "pin")
          }
        }
        .shortcutKeyHelp(
          name: .pin,
          key: shouldUnpin ? "UnpinKey" : "PinKey",
          tableName: "PreviewItemView",
          replacementKey: "pinKey"
        )
        .disabled(pinActionDisabled)

        ToolbarButton {
          appState.deleteSelection()
        } label: {
          Image(systemName: "trash")
        }
        .shortcutKeyHelp(
          name: .delete,
          key: "DeleteKey",
          tableName: "PreviewItemView",
          replacementKey: "deleteKey"
        )
      }

      if appState.navigator.pasteStackSelected {
        ToolbarButton {
          appState.removePasteStack()
        } label: {
          Image(systemName: "stop")
        }
      }
    }
  }
}

import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var selectionAppearance: SelectionAppearance {
    let previousSelected = previous?.isSelected ?? false
    let nextSelected = next?.isSelected ?? false
    switch (previousSelected, nextSelected) {
    case (true, false):
      return .topConnection
    case (false, true):
      return .bottomConnection
    case (true, true):
      return .topBottomConnection
    default:
      return .none
    }
  }

  @Default(.showHexColorSwatch) private var showHexColorSwatch
  @Environment(AppState.self) private var appState

  private var colorSwatchImage: NSImage? {
    guard showHexColorSwatch else { return nil }
    return ColorImage.from(item.title)
  }

  private func performSelect() {
    if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
      appState.navigator.addToSelection(item: item)
    } else {
      let flags = NSEvent.ModifierFlags.currentModifierFlags
      Task {
        appState.history.select(item, flags: flags)
      }
    }
  }

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : colorSwatchImage,
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected,
      selectionIndex: item.multiSelectionIndex,
      selectionAppearance: selectionAppearance,
      accessibilityLabel: item.accessibilityLabel
    ) {
      Text(verbatim: item.title)
    }
    .accessibilityIdentifier("copy-history-item")
    .buttonAction(performSelect)
    .contextMenu { contextMenuItems }
    .onAppear {
      item.ensureThumbnailImage()
    }
    .accessibilityAction(named: Text(item.isPinned ? "history_item_unpin_action" : "history_item_pin_action")) {
      appState.history.togglePin(item)
    }
    .accessibilityAction(named: Text("history_item_delete_action")) {
      appState.history.delete(item)
    }
  }

  @ViewBuilder
  private var contextMenuItems: some View {
    if let image = item.item.image {
      Button("history_item_share_action") {
        guard let png = Self.pngData(image) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(Self.fileName()).png")
        guard (try? png.write(to: url)) != nil else { return }
        SystemPanel.share(items: [url])
      }
      Button("history_item_save_action") {
        guard let png = Self.pngData(image) else { return }
        SystemPanel.save(png, fileName: "\(Self.fileName()).png")
      }
    } else if let text = item.item.text {
      Button("history_item_share_action") {
        SystemPanel.share(items: [text])
      }
    }
  }

  private static func pngData(_ image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
  }

  private static func fileName() -> String {
    "Maccy " + Date.now.formatted(
      .iso8601.year().month().day().dateSeparator(.omitted)
        .time(includingFractionalSeconds: false).timeSeparator(.omitted)
    )
  }
}

// Presents the system share menu and save panel from the history popup.
// SwiftUI ShareLink does nothing inside a macOS context menu, so AppKit is used instead.
@MainActor
private final class SystemPanel: NSObject, NSSharingServicePickerDelegate {
  private static let shared = SystemPanel()

  static func share(items: [Any]) {
    let mouse = NSEvent.mouseLocation
    // Wait for the context menu to close before opening another menu.
    DispatchQueue.main.async {
      guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(mouse) }),
            let view = window.contentView else { return }
      let point = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
      let picker = NSSharingServicePicker(items: items)
      picker.delegate = shared
      AppState.shared.isPresentingSystemPanel = true
      picker.show(relativeTo: NSRect(origin: point, size: NSSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
    }
  }

  static func save(_ data: Data, fileName: String) {
    DispatchQueue.main.async {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = fileName
      panel.allowedContentTypes = [.png]
      panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      AppState.shared.isPresentingSystemPanel = true
      // Maccy is not the active app while the popup is open, so activate it to bring the panel to front.
      NSApp.activate(ignoringOtherApps: true)
      panel.begin { response in
        AppState.shared.isPresentingSystemPanel = false
        if response == .OK, let url = panel.url {
          try? data.write(to: url)
        }
      }
    }
  }

  func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
    AppState.shared.isPresentingSystemPanel = false
  }
}

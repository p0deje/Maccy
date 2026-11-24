import Defaults
import KeyboardShortcuts
import SwiftUI

private enum QRCodeGenerator {
  static func generate(from string: String) -> NSImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let outputImage = filter.outputImage else { return nil }

    let transform = CGAffineTransform(scaleX: 10, y: 10)
    let scaledImage = outputImage.transformed(by: transform)
    let rep = NSCIImageRep(ciImage: scaledImage)
    let nsImage = NSImage(size: rep.size)
    nsImage.addRepresentation(rep)
    return nsImage
  }
}

private struct QRCodePopoverView: View {
  let image: NSImage?

  var body: some View {
    VStack(spacing: 12) {
      if let image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.none)
          .scaledToFit()
          .padding(12)
          .background(Color.white)
          .cornerRadius(8)
          .frame(width: 200, height: 200)
      } else {
        Text(NSLocalizedString("QRCodeError", tableName: "PreviewItemView", comment: ""))
          .foregroundColor(.secondary)
          .frame(width: 200, height: 200)
      }

      Text(NSLocalizedString("QRCodeScanHint", tableName: "PreviewItemView", comment: ""))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(16)
  }
}

private struct KeyboardShortcutHelpModifier: ViewModifier {
  // A nil name produces help text without a keyboard shortcut substitution.
  let name: KeyboardShortcuts.Name?
  let key: String
  let tableName: String
  let comment: String = ""
  let replacementKey: String

  // Use the same localized description for visual help and the accessibility label.
  private var resolvedText: Text? {
    let localized = NSLocalizedString(key, tableName: tableName, comment: comment)
    guard let name else {
      return Text(localized)
    }
    guard let shortcut = KeyboardShortcuts.Shortcut(name: name) else {
      return nil
    }
    return Text(localized.replacingOccurrences(of: "{\(replacementKey)}", with: shortcut.description))
  }

  func body(content: Content) -> some View {
    if let resolvedText {
      content
        .help(resolvedText)
        .accessibilityLabel(resolvedText)
    } else {
      content
    }
  }
}

struct ToolbarButton<Label: View>: View {
  let action: @MainActor () -> Void
  let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
    }
    .buttonStyle(.plain)
    .frame(height: 23)
    .excludeFromWindowMovableByBackground()
  }

  func shortcutKeyHelp(
    name: KeyboardShortcuts.Name? = nil,
    key: String,
    tableName: String,
    replacementKey: String = ""
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

private final class SharingPickerDelegate: NSObject, NSSharingServicePickerDelegate {
  private let qrText: String?
  private let onShowQRCode: () -> Void
  private let onCompletion: () -> Void

  init(
    qrText: String?,
    onShowQRCode: @escaping () -> Void,
    onCompletion: @escaping () -> Void
  ) {
    self.qrText = qrText
    self.onShowQRCode = onShowQRCode
    self.onCompletion = onCompletion
  }

  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker,
    sharingServicesForItems items: [Any],
    proposedSharingServices: [NSSharingService]
  ) -> [NSSharingService] {
    var services = proposedSharingServices

    if let qrText, !qrText.isEmpty {
      let qrTitle = NSLocalizedString("QRCode", tableName: "PreviewItemView", comment: "")
      let qrImage = NSImage(systemSymbolName: "qrcode", accessibilityDescription: nil) ?? NSImage()
      let qrService = NSSharingService(
        title: qrTitle,
        image: qrImage,
        alternateImage: nil
      ) { [weak self] in
        self?.onShowQRCode()
      }
      services.insert(qrService, at: 0)
    }

    return services
  }

  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker,
    didChoose service: NSSharingService?
  ) {
    let qrTitle = NSLocalizedString("QRCode", tableName: "PreviewItemView", comment: "")
    if service?.title == qrTitle {
      onShowQRCode()
    } else {
      onCompletion()
    }
  }
}

private struct ShareAnchorView: NSViewRepresentable {
  let onView: (NSView) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      onView(view)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      onView(nsView)
    }
  }
}

struct ToolbarView: View {
  @State private var appState = AppState.shared
  @State private var editingItem: HistoryItemDecorator?
  @State private var shareAnchorView: NSView?
  @State private var sharingDelegate: SharingPickerDelegate?
  @State private var qrCodeImage: NSImage?
  @State private var showQRCode: Bool = false

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

  private var selectedImageItem: HistoryItemDecorator? {
    guard appState.navigator.selection.count == 1,
          let item = appState.navigator.selection.first,
          item.hasImage else {
      return nil
    }

    return item
  }

  private var selectedImageText: String? {
    guard let item = selectedImageItem else {
      return nil
    }

    let text = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : item.title
  }

  private var editItemEnabled: Bool {
    guard appState.navigator.selection.count == 1 else { return false }
    guard let item = appState.navigator.selection.first else { return false }
    return item.hasPlainText || item.hasRichText || item.hasImage
  }

  private var editableItem: HistoryItemDecorator? {
    guard editItemEnabled else { return nil }
    return appState.navigator.selection.first
  }

  private var shareableItems: [Any]? {
    guard appState.navigator.selection.count == 1,
          let item = appState.navigator.selection.first else {
      return nil
    }
    let items = item.shareableItems
    return items.isEmpty ? nil : items
  }

  private var shareableText: String? {
    guard appState.navigator.selection.count == 1,
          let item = appState.navigator.selection.first else {
      return nil
    }
    return item.shareableText
  }

  private func shareSelection() {
    guard let items = shareableItems, !items.isEmpty else { return }

    appState.isSharing = true
    let picker = NSSharingServicePicker(items: items)
    let delegate = SharingPickerDelegate(
      qrText: shareableText,
      onShowQRCode: {
        DispatchQueue.main.async {
          if let text = shareableText, let image = QRCodeGenerator.generate(from: text) {
            self.qrCodeImage = image
            self.showQRCode = true
            self.appState.isSharing = true
          } else {
            self.appState.isSharing = false
          }
        }
      },
      onCompletion: {
        DispatchQueue.main.async {
          self.appState.isSharing = false
          self.sharingDelegate = nil
          if let panel = self.appState.appDelegate?.panel, !panel.isKeyWindow {
            self.appState.popup.close()
          }
        }
      }
    )
    self.sharingDelegate = delegate
    picker.delegate = delegate

    if let anchor = shareAnchorView, anchor.window != nil {
      picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    } else if let contentView = NSApp.keyWindow?.contentView {
      picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    } else {
      appState.isSharing = false
      self.sharingDelegate = nil
    }
  }

  var body: some View {
    HStack {
      if !appState.navigator.selection.isEmpty {
        Spacer()

        if selectedImageItem != nil {
          ToolbarButton {
            guard let selectedImageText else { return }
            Clipboard.shared.copyInMaccy(selectedImageText)
          } label: {
            Image(systemName: "text.viewfinder")
          }
          .shortcutKeyHelp(key: "CopyExtractedText", tableName: "PreviewItemView")
          .disabled(selectedImageText == nil)
        }

        ToolbarButton {
          withAnimation {
            appState.togglePin()
          }
        } label: {
          if (appState.navigator.selection.items.allSatisfy { $0.isPinned }) {
            Image(systemName: "pin.slash.fill")
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
          appState.isEditingItem = true
          editingItem = editableItem
        } label: {
          Image(systemName: "pencil.and.list.clipboard")
        }
        .shortcutKeyHelp(key: "EditItem", tableName: "PreviewItemView")
        .disabled(!editItemEnabled)
        .accessibilityIdentifier("edit-item")

        ToolbarButton {
          shareSelection()
        } label: {
          Image(systemName: "square.and.arrow.up")
            .background(ShareAnchorView { shareAnchorView = $0 })
        }
        .shortcutKeyHelp(key: "ShareItem", tableName: "PreviewItemView")
        .disabled(shareableItems == nil)
        .accessibilityIdentifier("share-item")
        .popover(isPresented: $showQRCode, arrowEdge: .top) {
          QRCodePopoverView(image: qrCodeImage)
        }

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
        .accessibilityLabel(Text("toolbar_remove_paste_stack_action"))
      }
    }
    .sheet(item: $editingItem, onDismiss: {
      finishEditingPinnedItem()
    }) { item in
      ItemEditorView(for: item)
    }
    .onChange(of: showQRCode) { _, isShowing in
      if !isShowing {
        appState.isSharing = false
        qrCodeImage = nil
      }
    }
  }

  private func finishEditingPinnedItem() {
    editingItem = nil
    appState.isEditingItem = false
  }
}

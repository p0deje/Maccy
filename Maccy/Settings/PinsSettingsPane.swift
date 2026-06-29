import SwiftData
import SwiftUI

/// Picker for assigning a pin key to a pinned history item.
struct PinPickerView: View {
  @Bindable var item: HistoryItem
  var availablePins: [String]

  var body: some View {
    if let pin = item.pin {
      // Ensure unique pins for ForEach
      let uniquePins = Array(Set(availablePins + [pin])).sorted()
      Picker("", selection: $item.pin) {
        ForEach(uniquePins, id: \.self) { pin in
          Text(pin)
            .tag(pin as String?)
        }
      }
      .controlSize(.small)
      .labelsHidden()
    }
  }
}

/// Editable alias (title) for a pinned item.
struct PinTitleView: View {
  @Bindable var item: HistoryItem

  var body: some View {
    TextField("", text: $item.title)
  }
}

/// Editable content field for a pinned item, with a rich-text editing warning.
struct PinValueView: View {
  @Bindable var item: HistoryItem
  @State private var editableValue: String
  @State private var isTextContent: Bool
  @State private var isRichText: Bool
  @FocusState private var isEditing: Bool
  @State private var showWarningPopover: Bool = false

  /// Initializes editable state, classifying the item as plain text or rich text.
  init(item: HistoryItem) {
    self.item = item
    self._editableValue = State(initialValue: item.previewableTextPrefix(maxLength: HistoryItem.textPreviewLimit))

    // Check if this item has editable text content
    let hasPlainText = item.textPrefix(maxLength: 1) != nil
    let hasImage = item.hasImageData
    let hasFileURLs = !item.fileURLs.isEmpty
    let hasRichText = item.rtfData != nil || item.htmlData != nil

    // Consider it text content only if it has plain text and doesn't have images or file URLs
    self._isTextContent = State(initialValue: hasPlainText && !hasImage && !hasFileURLs)
    self._isRichText = State(initialValue: hasRichText && !hasImage && !hasFileURLs)
  }

  var body: some View {
    Group {
      if isTextContent || isRichText {
        ZStack(alignment: .trailing) {
          TextField("", text: $editableValue)
            .focused($isEditing)
            .onSubmit {
              updateItemContent()
            }
            .onChange(of: editableValue) { _, _ in
              updateItemContent()
            }
            .padding(.trailing, isRichText ? 40 : 0) // increased space for icon

          if isRichText && isEditing {
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .help(Text("RichTextEditWarning", tableName: "PinsSettings"))
              Spacer().frame(width: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 4)
          }
        }
      } else {
        // Non-editable display for non-text content
        Text("ContentIsNotText", tableName: "PinsSettings")
          .foregroundStyle(.secondary)
          .italic()
      }
    }
  }

  /// Replaces the item's contents with the edited plain text, preserving the title.
  private func updateItemContent() {
    // Only update if we're dealing with text or rich text content
    guard isTextContent || isRichText else { return }

    // Remove all non-plain-text content
    let stringType = NSPasteboard.PasteboardType.string.rawValue
    item.contents.removeAll { $0.type != stringType }

    // Update or add the plain text content
    if let index = item.contents.firstIndex(where: { $0.type == stringType }) {
      if let data = editableValue.data(using: .utf8) {
        item.contents[index].value = data
      }
    } else {
      if let data = editableValue.data(using: .utf8) {
        let newContent = HistoryItemContent(type: stringType, value: data)
        item.contents.append(newContent)
      }
    }
  }
}

/// Settings pane for assigning pin keys, aliases, and editable content to pinned items.
struct PinsSettingsPane: View {
  @Environment(AppState.self) private var appState
  @Environment(\.modelContext) private var modelContext

  @Query(filter: #Predicate<HistoryItem> { $0.pin != nil }, sort: \.firstCopiedAt)
  private var items: [HistoryItem]

  @State private var availablePins: [String] = []
  @State private var selection: PersistentIdentifier?

  var body: some View {
    VStack(alignment: .leading) {
      Table(items, selection: $selection) {
        TableColumn(Text("Key", tableName: "PinsSettings")) { item in
          PinPickerView(item: item, availablePins: availablePins)
            .onChange(of: item.pin) {
              availablePins = HistoryItem.availablePins
            }
        }
        .width(60)

        TableColumn(Text("Alias", tableName: "PinsSettings")) { item in
          PinTitleView(item: item)
        }

        TableColumn(Text("Content", tableName: "PinsSettings")) { item in
          PinValueView(item: item)
        }
      }
      .onAppear {
        availablePins = HistoryItem.availablePins
      }
      .onDeleteCommand {
        guard let selection,
              let item = appState.history.items.first(where: { $0.item.id == selection }) else {
          return
        }

        appState.history.delete(item)
      }

      Text("PinCustomizationDescription", tableName: "PinsSettings")
        .foregroundStyle(.gray)
        .controlSize(.small)
    }
    .frame(minWidth: 500, minHeight: 400)
    .padding()
  }
}

#Preview {
  return PinsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
